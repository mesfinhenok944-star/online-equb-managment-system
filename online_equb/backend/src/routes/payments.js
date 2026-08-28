'use strict';

const { Router }  = require('express');
const { db, nowIso } = require('../config/firebase');
const { verifyToken, requireAdmin } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');
const { sendPaymentApprovedEmail, sendPaymentRejectedEmail } = require('../config/email');

const router = Router();

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/payments/submit
// ─────────────────────────────────────────────────────────────────────────────
router.post('/submit', async (req, res) => {
  try {
    const {
      userId = '',
      firstName = '', middleName = '', lastName = '',
      fullName = '', email = '', nationalId = '', uniqueId = '',
      equbLevel = 'low', bankName = 'CBE', amount = 0,
      referenceNumber = '', proofScreenshotBase64 = '',
    } = req.body;

    const trimmedEmail = email.trim().toLowerCase();
    const trimmedId    = (nationalId || uniqueId).trim();
    const targetLevel  = equbLevel.toLowerCase().replaceAll('equb_', '').trim();
    const calculatedFullName = fullName ||
      `${firstName} ${middleName} ${lastName}`.replace(/\s+/g, ' ').trim();

    if (!trimmedEmail && !trimmedId) {
      return res.status(400).json({ error: 'Email or Member ID required.' });
    }
    if (!referenceNumber.trim()) {
      return res.status(400).json({ error: 'Transaction reference number required.' });
    }

    const hashData  = `${trimmedEmail}:${trimmedId}:${bankName}:${amount}:${referenceNumber}:${proofScreenshotBase64.substring(0, 100)}`;
    const proofHash = crypto.createHash('sha256').update(hashData).digest('hex');

    let matchedUserId  = userId;
    let matchedUserDoc = null;
    if (db) {
      try {
        const usersSnap = await db.collection('users').get();
        for (const doc of usersSnap.docs) {
          const u      = doc.data();
          const uEmail  = (u.email  || '').toLowerCase().trim();
          const uUnique = (u.uniqueId || u.nationalId || '').trim();
          const uLevel  = (u.equbLevel || u.level || '').toLowerCase().replaceAll('equb_', '').trim();
          if (uLevel === targetLevel && (uEmail === trimmedEmail || uUnique === trimmedId)) {
            matchedUserId  = doc.id;
            matchedUserDoc = { id: doc.id, ...u };
            break;
          }
        }
      } catch (_) {}
    }

    const now         = nowIso();
    const paymentData = {
      paymentId:   uuidv4(),
      userId:      matchedUserId || `guest_${Date.now()}`,
      matchedUser: matchedUserDoc
        ? { fullName: matchedUserDoc.fullName || calculatedFullName, email: matchedUserDoc.email || trimmedEmail, uniqueId: matchedUserDoc.uniqueId || trimmedId }
        : null,
      isRegisteredMemberMatch: !!matchedUserDoc,
      firstName, middleName, lastName,
      fullName:             calculatedFullName || 'Equb Member',
      email:                trimmedEmail,
      nationalId:           trimmedId,
      uniqueId:             trimmedId,
      equbLevel:            targetLevel,
      level:                targetLevel,
      bankName,
      amount:               Number(amount),
      referenceNumber:      referenceNumber.trim(),
      proofScreenshotBase64,
      proofHash,
      status:               'pending_verification',
      createdAt:            now,
      updatedAt:            now,
    };

    if (db) {
      const ref = await db.collection('payments').add(paymentData);
      return res.status(201).json({ success: true, paymentId: ref.id, ...paymentData,
        message: 'Payment submitted. Waiting for admin verification.' });
    }
    return res.status(201).json({ success: true, ...paymentData });
  } catch (err) {
    console.error('[Payment Submit]', err);
    return res.status(500).json({ error: err.message });
  }
});

// Legacy alias
router.post('/initiate', (req, res) => { req.url = '/submit'; router.handle(req, res); });

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/level/:level
// ─────────────────────────────────────────────────────────────────────────────
router.get('/level/:level', async (req, res) => {
  try {
    const levelKey = req.params.level.toLowerCase().replaceAll('equb_', '').trim();
    if (!db) return res.json([]);
    const snap = await db.collection('payments').get();
    const list = snap.docs
      .map(d => ({ paymentId: d.id, id: d.id, ...d.data() }))
      .filter(item => {
        if (levelKey === 'all') return true;
        const lvl = (item.equbLevel || item.level || '').toLowerCase().replaceAll('equb_', '').trim();
        return lvl === levelKey;
      });
    list.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
    return res.json(list);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/history?userId=&email=
// ─────────────────────────────────────────────────────────────────────────────
router.get('/history', async (req, res) => {
  try {
    const uid   = req.query.userId || req.user?.uid || '';
    const email = (req.query.email || '').toLowerCase().trim();
    if (!db) return res.json([]);
    const snap = await db.collection('payments').get();
    const list = snap.docs
      .map(d => ({ paymentId: d.id, id: d.id, ...d.data() }))
      .filter(item => {
        if (uid   && (item.userId === uid))                           return true;
        if (email && (item.email || '').toLowerCase() === email)      return true;
        return false;
      });
    list.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
    return res.json(list);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/payments/verify  — approve or reject + send email notification
// ─────────────────────────────────────────────────────────────────────────────
router.post('/verify', async (req, res) => {
  try {
    const {
      paymentId       = '',
      status          = 'verified',
      rejectionReason = '',
      adminId         = req.user?.uid || 'level_admin',
    } = req.body;

    if (!paymentId) return res.status(400).json({ error: 'paymentId is required.' });
    if (!db) return res.json({ success: true, message: `Payment ${status}.` });

    const docRef  = db.collection('payments').doc(paymentId);
    const docSnap = await docRef.get();
    if (!docSnap.exists) return res.status(404).json({ error: 'Payment record not found.' });

    const payData = docSnap.data();
    const now     = nowIso();
    const isApproved = status === 'verified';

    // ── Update payment document ──────────────────────────────────────────────
    await docRef.update({
      status:            isApproved ? 'verified' : 'rejected',
      rejectionReason:   rejectionReason || '',
      verifiedByAdminId: adminId,
      verifiedAt:        now,
      updatedAt:         now,
    });

    // ── Update user balance if approved ──────────────────────────────────────
    if (isApproved && payData.userId && !payData.userId.startsWith('guest_')) {
      try {
        const userRef  = db.collection('users').doc(payData.userId);
        const userSnap = await userRef.get();
        if (userSnap.exists) {
          const bal    = Number(userSnap.data().balance || 0);
          const payAmt = Number(payData.amount || 0);
          await userRef.update({
            hasPaid:              true,
            status:               'active',
            balance:              bal + payAmt,
            lastPaymentDate:      now,
            lastPaymentReference: payData.referenceNumber || '',
            updatedAt:            now,
          });
        }
      } catch (_) {}
    }

    // ── Save in-app notification to Firestore notifications collection ────────
    const notifData = {
      userId:      payData.userId      || '',
      userEmail:   payData.email       || '',
      fullName:    payData.fullName    || payData.firstName || '',
      title:       isApproved ? '✅ ክፍያዎ ፀድቋል — Payment Approved' : '❌ ክፍያዎ ተሰርዟል — Payment Rejected',
      body:        isApproved
        ? `${payData.equbLevel?.toUpperCase()} Level equb payment of ETB ${payData.amount} approved.`
        : `Payment rejected. Reason: ${rejectionReason || 'See admin'}`,
      type:        `payment_${isApproved ? 'verified' : 'rejected'}`,
      level:       payData.equbLevel   || '',
      amount:      String(payData.amount || 0),
      paymentId,
      isRead:      false,
      createdAt:   now,
    };
    try { await db.collection('notifications').add(notifData); } catch (_) {}

    // ── Send email notification (fire-and-forget) ────────────────────────────
    const recipientEmail = payData.email || '';
    const recipientName  = payData.fullName || payData.firstName || 'Member';
    if (recipientEmail) {
      const emailPayload = {
        to:               recipientEmail,
        fullName:         recipientName,
        amount:           String(payData.amount || 0),
        level:            payData.equbLevel || payData.level || 'low',
        referenceNumber:  payData.referenceNumber || '',
        rejectionReason:  rejectionReason || '',
      };
      if (isApproved) {
        sendPaymentApprovedEmail(emailPayload).catch(() => {});
      } else {
        sendPaymentRejectedEmail(emailPayload).catch(() => {});
      }
    }

    // ── Send SMS notification (fire-and-forget) ───────────────────────────────
    try {
      const { sendPaymentSms } = require('../config/sms');
      const recipientPhone = payData.phoneNumber || payData.phone || '';
      if (recipientPhone) {
        sendPaymentSms({
          phone:           recipientPhone,
          fullName:        recipientName,
          status:          isApproved ? 'verified' : 'rejected',
          amount:          String(payData.amount || 0),
          level:           payData.equbLevel || payData.level || 'low',
          rejectionReason: rejectionReason || '',
        }).catch(() => {});
      }
    } catch (_) {}

    return res.json({
      success:   true,
      paymentId,
      status:    isApproved ? 'verified' : 'rejected',
      emailSent: !!recipientEmail,
      message:   isApproved
        ? '✅ Payment approved. Member notified.'
        : '❌ Payment rejected. Member notified.',
    });
  } catch (err) {
    console.error('[payments/verify]', err);
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/v1/payments/:id  — admin deletes/clears payment record
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const paymentId = req.params.id;
    if (!db) return res.json({ success: true });
    const docRef  = db.collection('payments').doc(paymentId);
    const docSnap = await docRef.get();
    if (!docSnap.exists) return res.status(404).json({ error: 'Payment not found.' });
    // Clear screenshot to free storage, mark as deleted
    await docRef.update({
      proofScreenshotBase64: '',
      screenshotClearedAt:   nowIso(),
      status:                'deleted',
      updatedAt:             nowIso(),
    });
    return res.json({ success: true, message: 'Payment record deleted. Screenshot cleared.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/account/:level  — level bank account info
// ─────────────────────────────────────────────────────────────────────────────
router.get('/account/:level', async (req, res) => {
  try {
    const lvl = req.params.level.toLowerCase().replaceAll('equb_', '').trim();
    if (!db) return res.status(404).json({ error: 'DB unavailable.' });
    const doc = await db.collection('equb_payment_accounts').doc(lvl).get();
    if (!doc.exists) return res.status(404).json({ error: `Account info not found for: ${lvl}` });
    return res.json({ level: lvl, ...doc.data() });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/:id  — single payment
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    if (!db) return res.status(404).json({ error: 'Not found.' });
    const doc = await db.collection('payments').doc(req.params.id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Not found.' });
    return res.json({ paymentId: doc.id, id: doc.id, ...doc.data() });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
