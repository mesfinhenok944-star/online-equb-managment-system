'use strict';

const { Router } = require('express');
const { db, auth, nowIso } = require('../config/firebase');
const { verifyToken } = require('../middleware/auth');

const router = Router();
// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC — GET /api/v1/users/notifications-by-email?email= (no auth needed)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/notifications-by-email', async (req, res) => {
  try {
    const email = (req.query.email || '').toLowerCase().trim();
    if (!email || !email.includes('@')) return res.status(400).json({ error: 'Valid email required.' });
    if (!db) return res.json([]);
    let list = [];
    try {
      const snap = await db.collection('notifications')
        .where('userEmail', '==', email)
        .orderBy('createdAt', 'desc').limit(50).get();
      list = snap.docs.map(d => ({ id: d.id, docId: d.id, ...d.data() }));
    } catch (_) {
      const snap = await db.collection('notifications').get();
      list = snap.docs
        .filter(d => (d.data().userEmail||'').toLowerCase()===email)
        .map(d => ({ id: d.id, docId: d.id, ...d.data() }))
        .sort((a,b) => (b.createdAt||'').localeCompare(a.createdAt||''));
    }
    console.log('[notifications-by-email]', email, '->', list.length);
    return res.json(list);
  } catch (err) { return res.status(500).json({ error: err.message }); }
});

router.use(verifyToken);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/users/profile
// ─────────────────────────────────────────────────────────────────────────────
router.get('/profile', async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) return res.status(401).json({ error: 'Not authenticated.' });

    const doc = await db.collection('users').doc(uid).get();
    if (!doc.exists) {
      // Return minimal from auth token
      return res.json({ uid, email: req.user.email, role: req.user.role || 'user' });
    }
    return res.json({ userId: doc.id, ...doc.data() });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/users/profile
// ─────────────────────────────────────────────────────────────────────────────
router.put('/profile', async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) return res.status(401).json({ error: 'Not authenticated.' });

    const allowed = ['firstName', 'lastName', 'fullName', 'phoneNumber', 'address'];
    const updates = {};
    for (const key of allowed) {
      if (req.body[key] !== undefined) updates[key] = req.body[key];
    }
    updates.updatedAt = nowIso();

    await db.collection('users').doc(uid).set(updates, { merge: true });
    const updated = await db.collection('users').doc(uid).get();
    return res.json({ userId: uid, ...updated.data(), message: 'Profile updated.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/users/notifications
// ─────────────────────────────────────────────────────────────────────────────
router.get('/notifications', async (req, res) => {
  try {
    const uid = req.user?.uid;
    const snap = await db.collection('notifications')
      .where('userId', '==', uid)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();

    const notifications = snap.docs.map(d => ({ id: d.id, ...d.data() }));

    // Seed a welcome notification if none exist
    if (notifications.length === 0) {
      notifications.push({
        id: 'welcome',
        title: 'Welcome to Online Equb!',
        message: 'Your account is ready. Start participating in EQUB circles.',
        type: 'info',
        read: false,
        createdAt: nowIso(),
      });
    }

    return res.json(notifications);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/users/notifications/:id/read
// ─────────────────────────────────────────────────────────────────────────────
router.put('/notifications/:id/read', async (req, res) => {
  try {
    await db.collection('notifications').doc(req.params.id).update({ read: true });
    return res.json({ message: 'Notification marked as read.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/users/kyc
// ─────────────────────────────────────────────────────────────────────────────
router.post('/kyc', async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) return res.status(401).json({ error: 'Not authenticated.' });

    const { idType = 'national_id', idNumber = '', documentUrl = '' } = req.body;

    await db.collection('users').doc(uid).update({
      verificationStatus: 'pending',
      kycData: { idType, idNumber, documentUrl, submittedAt: nowIso() },
      updatedAt: nowIso(),
    });

    // Also store in a separate kyc collection for admin review
    await db.collection('kyc').doc(uid).set({
      userId: uid, idType, idNumber, documentUrl,
      status: 'pending', submittedAt: nowIso(),
    });

    return res.json({ status: 'pending', message: 'KYC submitted successfully.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/users/change-password
// ─────────────────────────────────────────────────────────────────────────────
router.put('/change-password', async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) return res.status(401).json({ error: 'Not authenticated.' });

    const { newPassword } = req.body;
    if (!newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: 'New password must be at least 6 characters.' });
    }

    await auth.updateUser(uid, { password: newPassword });
    return res.json({ message: 'Password changed successfully.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});


module.exports = router;
