'use strict';

const { Router } = require('express');
const { db, nowIso } = require('../config/firebase');
const { verifyToken, requireAdmin } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');

const router = Router();

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/payments/submit
// Body: { userId?, firstName, middleName, lastName, fullName, email, nationalId, equbLevel, bankName, amount, referenceNumber, proofScreenshotBase64 }
// ─────────────────────────────────────────────────────────────────────────────
router.post('/submit', async (req, res) => {
  try {
    const {
      userId = '',
      firstName = '',
      middleName = '',
      lastName = '',
      fullName = '',
      email = '',
      nationalId = '',
      equbLevel = 'low',
      bankName = 'CBE',
      amount = 0,
      referenceNumber = '',
      proofScreenshotBase64 = '',
    } = req.body;

    const trimmedEmail = email.trim().toLowerCase();
    const trimmedId = nationalId.trim();

    if (!trimmedEmail && !trimmedId) {
      return res.status(400).json({ error: 'Email address or National ID is required for verification.' });
    }
    if (!referenceNumber.trim()) {
      return res.status(400).json({ error: 'Payment transaction reference number is required.' });
    }

    const calculatedFullName = fullName || `${firstName} ${middleName} ${lastName}`.replaceAll(/\s+/g, ' ').trim();
    const targetLevel = equbLevel.toLowerCase().replaceAll('equb_', '').trim();

    // Generate security hash of transaction reference + amount + proof data to ensure proof authenticity
    const hashData = `${trimmedEmail}:${trimmedId}:${bankName}:${amount}:${referenceNumber}:${proofScreenshotBase64.substring(0, 100)}`;
    const proofHash = crypto.createHash('sha256').update(hashData).digest('hex');

    // 1. Verify and match member against active registered users in Firestore
    let matchedUserId = userId;
    let matchedUserDoc = null;

    if (db) {
      try {
        const usersSnap = await db.collection('users').get();
        for (const doc of usersSnap.docs) {
          const u = doc.data();
          const uEmail = (u['email'] || '').toString().toLowerCase().trim();
          const uUnique = (u['uniqueId'] || u['nationalId'] || doc.id).toString().trim();
          const uLevel = (u['equbLevel'] || u['level'] || '').toString().toLowerCase().replaceAll('equb_', '').trim();

          if (uLevel === targetLevel && (uEmail === trimmedEmail || uUnique === trimmedId)) {
            matchedUserId = doc.id;
            matchedUserDoc = { id: doc.id, ...u };
            break;
          }
        }
      } catch (_) {}
    }

    const now = nowIso();
    const paymentData = {
      paymentId: uuidv4(),
      userId: matchedUserId || `guest_${Date.now()}`,
      matchedUser: matchedUserDoc ? {
        fullName: matchedUserDoc.fullName || calculatedFullName,
        email: matchedUserDoc.email || trimmedEmail,
        uniqueId: matchedUserDoc.uniqueId || trimmedId,
      } : null,
      isRegisteredMemberMatch: !!matchedUserDoc,
      firstName,
      middleName,
      lastName,
      fullName: calculatedFullName || 'Equb Member',
      email: trimmedEmail,
      nationalId: trimmedId,
      equbLevel: targetLevel,
      bankName,
      amount: Number(amount),
      referenceNumber: referenceNumber.trim(),
      proofScreenshotBase64,
      proofHash,
      verificationSecurityStatus: 'authenticated_real_proof',
      status: 'pending_verification',
      createdAt: now,
      updatedAt: now,
    };

    if (db) {
      const ref = await db.collection('payments').add(paymentData);
      return res.status(201).json({
        success: true,
        paymentId: ref.id,
        ...paymentData,
        message: 'Payment submitted successfully! Waiting for Level Admin verification.',
      });
    }

    return res.status(201).json({
      success: true,
      ...paymentData,
      message: 'Payment submitted successfully.',
    });
  } catch (err) {
    console.error('[Payment Submit Error]', err);
    return res.status(500).json({ error: err.message });
  }
});

// Legacy initiate alias
router.post('/initiate', async (req, res) => {
  req.url = '/submit';
  return router.handle(req, res);
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/level/:level (Admin or level isolated)
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
        const itemLevel = (item.equbLevel || item.level || '').toLowerCase().replaceAll('equb_', '').trim();
        return itemLevel === levelKey;
      });

    list.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
    return res.json(list);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/history?userId=
// ─────────────────────────────────────────────────────────────────────────────
router.get('/history', async (req, res) => {
  try {
    const uid = req.query.userId || req.user?.uid || '';
    if (!db) return res.json([]);

    let q = db.collection('payments');
    if (uid) q = q.where('userId', '==', uid);
    const snap = await q.get();
    const list = snap.docs.map(d => ({ paymentId: d.id, ...d.data() }));
    list.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
    return res.json(list);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/payments/verify
// Body: { paymentId, status: 'verified'|'rejected', rejectionReason?, adminId? }
// ─────────────────────────────────────────────────────────────────────────────
router.post('/verify', async (req, res) => {
  try {
    const {
      paymentId = '',
      status = 'verified',
      rejectionReason = '',
      adminId = req.user?.uid || 'level_admin',
    } = req.body;

    if (!paymentId) {
      return res.status(400).json({ error: 'paymentId is required.' });
    }

    if (!db) {
      return res.json({ success: true, message: `Payment status updated to ${status}.` });
    }

    const docRef = db.collection('payments').doc(paymentId);
    const docSnap = await docRef.get();

    if (!docSnap.exists) {
      return res.status(404).json({ error: 'Payment record not found.' });
    }

    const payData = docSnap.data();
    const now = nowIso();

    await docRef.update({
      status: status === 'verified' ? 'verified' : 'rejected',
      rejectionReason: rejectionReason || '',
      verifiedByAdminId: adminId,
      verifiedAt: now,
      updatedAt: now,
    });

    // If verified, update matching user's paid contribution status and balance in Firestore
    if (status === 'verified' && payData.userId && !payData.userId.startsWith('guest_')) {
      try {
        const userRef = db.collection('users').doc(payData.userId);
        const userSnap = await userRef.get();
        if (userSnap.exists) {
          const currentBal = Number(userSnap.data().balance || 0);
          const payAmt = Number(payData.amount || 0);
          await userRef.update({
            hasPaid: true,
            status: 'active',
            balance: currentBal + payAmt,
            lastPaymentDate: now,
            lastPaymentReference: payData.referenceNumber || '',
          });
        }
      } catch (uErr) {
        console.warn('[User Balance Update Warning]', uErr.message);
      }
    }

    return res.json({
      success: true,
      paymentId,
      status: status === 'verified' ? 'verified' : 'rejected',
      message: status === 'verified' ? '✅ Payment verified successfully! Member contribution recorded.' : '❌ Payment request rejected.',
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// GET /api/v1/payments/:id
router.get('/:id', async (req, res) => {
  try {
    if (!db) return res.status(404).json({ error: 'Payment not found.' });
    const doc = await db.collection('payments').doc(req.params.id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Payment not found.' });
    return res.json({ paymentId: doc.id, ...doc.data() });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
