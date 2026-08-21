'use strict';

const { Router } = require('express');
const { db, nowIso } = require('../config/firebase');
const { verifyToken, requireAdmin } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

const router = Router();
router.use(verifyToken);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/payments/initiate
// Body: { userId, equbId, equbLevel, amount, paymentMethod, transactionId? }
// ─────────────────────────────────────────────────────────────────────────────
router.post('/initiate', async (req, res) => {
  try {
    const {
      userId = req.user?.uid || '',
      equbId = '', equbLevel = '',
      amount = 0,
      paymentMethod = 'bank_transfer',
      transactionId = uuidv4(),
    } = req.body;

    if (!userId || !amount) {
      return res.status(400).json({ error: 'userId and amount are required.' });
    }

    const now = nowIso();
    const data = {
      userId, equbId, equbLevel,
      amount: Number(amount),
      paymentMethod, transactionId,
      type: 'contribution',
      status: 'pending',
      createdAt: now, updatedAt: now,
    };

    const ref = await db.collection('payments').add(data);
    return res.status(201).json({
      paymentId: ref.id, ...data,
      message: 'Payment initiated.',
    });
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
    let q = db.collection('payments');
    if (uid) q = q.where('userId', '==', uid);
    const snap = await q.orderBy('createdAt', 'desc').get();
    return res.json(snap.docs.map(d => ({ paymentId: d.id, ...d.data() })));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/pending   (admin only)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/pending', requireAdmin, async (req, res) => {
  try {
    const snap = await db.collection('payments')
      .where('status', '==', 'pending')
      .orderBy('createdAt', 'desc').get();
    return res.json(snap.docs.map(d => ({ paymentId: d.id, ...d.data() })));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/payments/verify   (admin only)
// Body: { transactionId } or { paymentId }
// ─────────────────────────────────────────────────────────────────────────────
router.post('/verify', requireAdmin, async (req, res) => {
  try {
    const { transactionId, paymentId } = req.body;

    let docRef;
    if (paymentId) {
      docRef = db.collection('payments').doc(paymentId);
    } else if (transactionId) {
      const snap = await db.collection('payments')
        .where('transactionId', '==', transactionId).limit(1).get();
      if (snap.empty) return res.status(404).json({ error: 'Payment not found.' });
      docRef = snap.docs[0].ref;
    } else {
      return res.status(400).json({ error: 'paymentId or transactionId required.' });
    }

    await docRef.update({ status: 'completed', verifiedAt: nowIso() });
    return res.json({ message: 'Payment verified.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/payments/:id
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const doc = await db.collection('payments').doc(req.params.id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Payment not found.' });
    return res.json({ paymentId: doc.id, ...doc.data() });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
