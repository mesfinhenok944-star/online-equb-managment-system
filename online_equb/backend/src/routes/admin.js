'use strict';

const { Router } = require('express');
const { db, nowIso } = require('../config/firebase');
const { verifyToken, requireAdmin } = require('../middleware/auth');

const router = Router();
router.use(verifyToken, requireAdmin);

// ─── level config ─────────────────────────────────────────────────────────────
const LEVEL_CONFIG = {
  low:    { price: Number(process.env.LOW_PRICE)    || 5000,  max: Math.max(100, Number(process.env.LOW_MAX)    || 100) },
  medium: { price: Number(process.env.MEDIUM_PRICE) || 10000, max: Math.max(100, Number(process.env.MEDIUM_MAX) || 100) },
  high:   { price: Number(process.env.HIGH_PRICE)   || 20000, max: Math.max(100, Number(process.env.HIGH_MAX)   || 100) },
};
const minimumDrawParticipants = Math.max(
  1,
  Number(process.env.MIN_DRAW_PARTICIPANTS) || 1,
);

function levelCfg(level) {
  return LEVEL_CONFIG[level] || LEVEL_CONFIG.low;
}

// A level admin is deliberately restricted at the API boundary.  UI checks are
// helpful, but they can be bypassed by a crafted request.
function canManageLevel(req, level) {
  return req.user?.role === 'super_admin' || req.user?.level === level;
}

async function requireManagedLevel(req, res, level) {
  if (canManageLevel(req, level)) return true;
  res.status(403).json({ error: 'You can manage only your assigned Equb level.' });
  return false;
}

async function requireManagedUser(req, res, userId) {
  const doc = await db.collection('users').doc(userId).get();
  if (!doc.exists) {
    res.status(404).json({ error: 'User not found.' });
    return null;
  }
  if (!canManageLevel(req, doc.data().equbLevel)) {
    res.status(403).json({ error: 'This user belongs to another Equb level.' });
    return null;
  }
  return doc;
}

// ─────────────────────────────────────────────────────────────────────────────
// GET  /api/v1/admin/dashboard          — all 3 levels
// GET  /api/v1/admin/dashboard/:level   — single level
// ─────────────────────────────────────────────────────────────────────────────
router.get('/dashboard', async (req, res) => {
  try {
    const result = {};
    const levels = req.user.role === 'super_admin'
      ? ['low', 'medium', 'high']
      : [req.user.level];
    for (const level of levels) {
      result[level] = await buildLevelStats(level);
    }
    return res.json(result);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.get('/dashboard/:level', async (req, res) => {
  try {
    if (!await requireManagedLevel(req, res, req.params.level)) return;
    return res.json(await buildLevelStats(req.params.level));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// USER CRUD
// GET    /api/v1/admin/users?level=     list users
// POST   /api/v1/admin/users            create user
// GET    /api/v1/admin/users/:id        get user
// PUT    /api/v1/admin/users/:id        update user
// DELETE /api/v1/admin/users/:id        soft delete
// PUT    /api/v1/admin/users/:id/suspend
// PUT    /api/v1/admin/users/:id/activate
// PUT    /api/v1/admin/users/:id/verify
// ─────────────────────────────────────────────────────────────────────────────
router.get('/users', async (req, res) => {
  try {
    const level = req.query.level || (req.user.role === 'admin' ? req.user.level : '');
    if (level && !await requireManagedLevel(req, res, level)) return;
    let q = db.collection('users');
    if (level) q = q.where('equbLevel', '==', level);
    const snap = await q.orderBy('createdAt', 'desc').get();
    const users = snap.docs
      .filter(d => d.data().status !== 'deleted')
      .map(d => ({ userId: d.id, ...d.data() }));
    return res.json(users);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.post('/users', async (req, res) => {
  try {
    const {
      firstName = '', middleName = '', lastName = '',
      email = '', phoneNumber = '', uniqueId = '',
      equbLevel = req.user.role === 'admin' ? req.user.level : 'low', adminId = '',
    } = req.body;

    if (!await requireManagedLevel(req, res, equbLevel)) return;

    if (!email)    return res.status(400).json({ error: 'Email is required.' });
    if (!uniqueId) return res.status(400).json({ error: 'Unique ID is required.' });

    const emailLower = email.toLowerCase().trim();

    // Duplicate email
    const byEmail = await db.collection('users').where('email', '==', emailLower).limit(1).get();
    if (!byEmail.empty) return res.status(409).json({ error: 'Email already registered.' });

    // One-to-one uniqueId check
    const byUid = await db.collection('users').where('uniqueId', '==', uniqueId.trim()).limit(1).get();
    if (!byUid.empty && byUid.docs[0].data().status !== 'deleted') {
      return res.status(409).json({ error: 'Unique ID already registered to another user.' });
    }

    // Capacity check
    const cfg = levelCfg(equbLevel);
    const existingCount = await db.collection('users')
      .where('equbLevel', '==', equbLevel)
      .where('status', '!=', 'deleted').get();
    if (existingCount.size >= cfg.max) {
      return res.status(422).json({ error: `${equbLevel} level is at full capacity (${cfg.max}).` });
    }

    const fullName = `${firstName} ${middleName} ${lastName}`.replace(/\s+/g, ' ').trim();
    const now = nowIso();

    const data = {
      firstName, middleName, lastName, fullName,
      email: emailLower, phoneNumber, uniqueId: uniqueId.trim(),
      equbLevel,
      adminId: req.user.role === 'admin' ? req.user.adminId : adminId,
      role: 'user', status: 'active',
      hasWon: false, participationHistory: [], balance: 0,
      createdAt: now, updatedAt: now,
    };

    const ref = await db.collection('users').add(data);
    return res.status(201).json({ userId: ref.id, ...data, message: 'User registered successfully.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.get('/users/:id', async (req, res) => {
  try {
    const doc = await requireManagedUser(req, res, req.params.id);
    if (!doc) return;
    return res.json({ userId: doc.id, ...doc.data() });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.put('/users/:id', async (req, res) => {
  try {
    const doc = await requireManagedUser(req, res, req.params.id);
    if (!doc) return;
    const ref = doc.ref;

    const existing = doc.data();
    const {
      firstName  = existing.firstName,
      middleName = existing.middleName,
      lastName   = existing.lastName,
      phoneNumber = existing.phoneNumber,
      uniqueId   = existing.uniqueId,
      equbLevel  = existing.equbLevel,
    } = req.body;

    // uniqueId change — re-check
    if (uniqueId !== existing.uniqueId) {
      const taken = await db.collection('users').where('uniqueId', '==', uniqueId.trim()).limit(1).get();
      if (!taken.empty && taken.docs[0].id !== req.params.id) {
        return res.status(409).json({ error: 'Unique ID already taken.' });
      }
    }

    const fullName = `${firstName} ${middleName} ${lastName}`.replace(/\s+/g, ' ').trim();
    if (!await requireManagedLevel(req, res, equbLevel)) return;
    const updates = { firstName, middleName, lastName, fullName, phoneNumber, uniqueId, equbLevel, updatedAt: nowIso() };

    await ref.update(updates);
    const updated = await ref.get();
    return res.json({ userId: req.params.id, ...updated.data(), message: 'User updated.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.delete('/users/:id', async (req, res) => {
  try {
    const doc = await requireManagedUser(req, res, req.params.id);
    if (!doc) return;
    await doc.ref.update({ status: 'deleted', deletedAt: nowIso() });
    return res.json({ message: 'User deleted.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.put('/users/:id/suspend', async (req, res) => {
  try {
    const doc = await requireManagedUser(req, res, req.params.id);
    if (!doc) return;
    await doc.ref.update({ status: 'suspended', suspendedAt: nowIso() });
    return res.json({ message: 'User suspended.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.put('/users/:id/activate', async (req, res) => {
  try {
    const doc = await requireManagedUser(req, res, req.params.id);
    if (!doc) return;
    await doc.ref.update({ status: 'active', updatedAt: nowIso() });
    return res.json({ message: 'User activated.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.put('/users/:id/verify', async (req, res) => {
  try {
    const doc = await requireManagedUser(req, res, req.params.id);
    if (!doc) return;
    await doc.ref.update({ verificationStatus: 'verified', updatedAt: nowIso() });
    return res.json({ message: 'User verified.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/admin/dashboard/register  — assign user to a level
// DELETE /api/v1/admin/dashboard/remove  — remove participant
// ─────────────────────────────────────────────────────────────────────────────
router.post('/dashboard/register', async (req, res) => {
  try {
    const { userId, level } = req.body;
    if (!userId || !level) return res.status(400).json({ error: 'userId and level required.' });
    if (!await requireManagedLevel(req, res, level)) return;

    const doc = await requireManagedUser(req, res, userId);
    if (!doc) return;

    await doc.ref.update({ equbLevel: level, updatedAt: nowIso() });
    return res.json({ message: `User assigned to ${level} level.` });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.delete('/dashboard/remove', async (req, res) => {
  try {
    const { participantId } = req.body;
    if (!participantId) return res.status(400).json({ error: 'participantId required.' });
    const doc = await requireManagedUser(req, res, participantId);
    if (!doc) return;
    await doc.ref.update({ status: 'deleted', deletedAt: nowIso() });
    return res.json({ message: 'Participant removed.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DRAW ALGORITHM
// POST /api/v1/admin/draw/:level        — run one draw
// GET  /api/v1/admin/draw/:level/history — draw history
// ─────────────────────────────────────────────────────────────────────────────
router.post('/draw/:level', async (req, res) => {
  try {
    const { level } = req.params;
    if (!await requireManagedLevel(req, res, level)) return;

    // Load all active, non-winner users for this level
    const snap = await db.collection('users')
      .where('equbLevel', '==', level)
      .where('status', '==', 'active')
      .where('hasWon', '==', false)
      .get();

    if (snap.empty) {
      return res.status(422).json({ error: `No eligible participants for ${level} level.` });
    }

    const eligible = snap.docs.map(d => ({ userId: d.id, ...d.data() }));
    if (eligible.length < minimumDrawParticipants) {
      return res.status(422).json({
        error: `At least ${minimumDrawParticipants} eligible participants are required before a draw.`,
        eligibleCount: eligible.length,
        minimumRequired: minimumDrawParticipants,
      });
    }

    // Cryptographically secure, fair, tamper-proof random selection
    const crypto = require('crypto');
    const winnerIndex = eligible.length > 1 ? crypto.randomInt(0, eligible.length) : 0;
    const winner = eligible[winnerIndex];

    // Count existing draws for this level
    const histSnap = await db.collection('draws').where('equbLevel', '==', level).get();
    const drawNumber = histSnap.size + 1;

    const now = nowIso();
    const drawData = {
      equbLevel: level,
      adminId: req.user.adminId || req.user.uid || '',
      winnerId: winner.userId,
      winnerName: winner.fullName || '',
      winnerUniqueId: winner.uniqueId || '',
      drawNumber,
      participants: snap.docs.map(d => d.id),
      totalParticipants: snap.size,
      eligibleRemaining: eligible.length - 1,
      status: 'completed',
      createdAt: now,
    };

    const drawRef = await db.collection('draws').add(drawData);

    // Mark winner
    await db.collection('users').doc(winner.userId).update({
      hasWon: true,
      lastWinDate: now,
      updatedAt: now,
    });

    return res.json({
      drawId: drawRef.id,
      drawNumber,
      winnerId: winner.userId,
      winnerName: winner.fullName || '',
      winnerUniqueId: winner.uniqueId || '',
      level,
      eligibleRemaining: eligible.length - 1,
      message: 'Draw completed successfully.',
    });
  } catch (err) {
    console.error('[admin/draw]', err);
    return res.status(500).json({ error: err.message });
  }
});

router.get('/draw/:level/history', async (req, res) => {
  try {
    if (!await requireManagedLevel(req, res, req.params.level)) return;
    const snap = await db.collection('draws')
      .where('equbLevel', '==', req.params.level)
      .orderBy('drawNumber', 'desc')
      .get();
    return res.json(snap.docs.map(d => ({ drawId: d.id, ...d.data() })));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/admin/analytics
// ─────────────────────────────────────────────────────────────────────────────
router.get('/analytics', async (req, res) => {
  try {
    const [usersSnap, drawsSnap, paymentsSnap] = await Promise.all([
      db.collection('users').get(),
      db.collection('draws').get(),
      db.collection('payments').get(),
    ]);

    const payments = paymentsSnap.docs.map(d => d.data());
    const totalCollected = payments
      .filter(p => p.status === 'completed')
      .reduce((s, p) => s + (p.amount || 0), 0);

    const byLevel = {};
    for (const level of ['low', 'medium', 'high']) {
      byLevel[level] = {
        users: usersSnap.docs.filter(d => d.data().equbLevel === level && d.data().status !== 'deleted').length,
        draws: drawsSnap.docs.filter(d => d.data().equbLevel === level).length,
      };
    }

    return res.json({
      totalUsers: usersSnap.docs.filter(d => d.data().status !== 'deleted').length,
      totalDraws: drawsSnap.size,
      totalPayments: paymentsSnap.size,
      totalCollected,
      byLevel,
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Helper — build full level stats for dashboard
// ─────────────────────────────────────────────────────────────────────────────
async function buildLevelStats(level) {
  const cfg = levelCfg(level);

  const [usersSnap, drawsSnap] = await Promise.all([
    db.collection('users').where('equbLevel', '==', level).where('status', '!=', 'deleted').get(),
    db.collection('draws').where('equbLevel', '==', level).orderBy('drawNumber', 'desc').get(),
  ]);

  const users    = usersSnap.docs.map(d => ({ userId: d.id, ...d.data() }));
  const active   = users.filter(u => u.status === 'active');
  const eligible = active.filter(u => !u.hasWon);
  const draws    = drawsSnap.docs.map(d => ({ drawId: d.id, ...d.data() }));

  return {
    equbId: `equb_${level}`,
    level,
    price: cfg.price,
    netPrize: cfg.price * cfg.max * 0.93,
    adminFee: cfg.price * cfg.max * 0.07,
    maxParticipants: cfg.max,
    currentParticipants: active.length,
    eligibleCount: eligible.length,
    drawsHeld: draws.length,
    totalCollected: active.length * cfg.price,
    status: 'active',
    participants: active.map(u => ({
      participantId: u.userId,
      userId: u.userId,
      fullName: u.fullName || '',
      phoneNumber: u.phoneNumber || '',
      uniqueId: u.uniqueId || '',
      email: u.email || '',
      hasWon: u.hasWon || false,
      status: u.status || 'active',
    })),
    draws: draws.map(d => ({
      drawId: d.drawId,
      drawNumber: d.drawNumber,
      winnerName: d.winnerName || '',
      winnerUniqueId: d.winnerUniqueId || '',
      createdAt: d.createdAt || '',
    })),
  };
}

module.exports = router;
