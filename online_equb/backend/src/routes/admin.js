'use strict';

const { Router } = require('express');
const { db, nowIso } = require('../config/firebase');
const { verifyToken, requireAdmin } = require('../middleware/auth');

const router = Router();
router.use(verifyToken, requireAdmin);

// ─── level config ─────────────────────────────────────────────────────────────
const LEVEL_CONFIG = {
  low:    { price: Number(process.env.LOW_PRICE)    || 5000,  max: Math.max(1000, Number(process.env.LOW_MAX)    || 1000) },
  medium: { price: Number(process.env.MEDIUM_PRICE) || 10000, max: Math.max(1000, Number(process.env.MEDIUM_MAX) || 1000) },
  high:   { price: Number(process.env.HIGH_PRICE)   || 20000, max: Math.max(1000, Number(process.env.HIGH_MAX)   || 1000) },
};
const minimumDrawParticipants = Math.max(
  1,
  Number(process.env.MIN_DRAW_PARTICIPANTS) || 1,
);

function levelCfg(level) {
  const key = (level || 'low').toLowerCase();
  return LEVEL_CONFIG[key] || { price: 5000, max: 1000 };
}

function canManageLevel(req, level) {
  if (req.user?.role === 'super_admin') return true;
  if (!level) return true;
  const userLevel = (req.user?.level || req.user?.equbLevel || '').toLowerCase();
  return userLevel === level.toLowerCase();
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
  const uLevel = doc.data().equbLevel || doc.data().level || '';
  if (!canManageLevel(req, uLevel)) {
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
      : [req.user.level || 'low'];
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
    const snap = await db.collection('users').get();
    let users = snap.docs
      .map(d => ({ userId: d.id, id: d.id, ...d.data() }))
      .filter(u => u.status !== 'deleted');
    if (level) {
      const lvlLower = level.toLowerCase();
      users = users.filter(u => (u.equbLevel || u.level || '').toLowerCase() === lvlLower);
    }
    users.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
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
      equbLevel = req.user.role === 'admin' ? (req.user.level || 'low') : 'low',
      level: bodyLevel, adminId = '',
    } = req.body;

    const targetLevel = (bodyLevel || equbLevel || 'low').toLowerCase();

    if (!await requireManagedLevel(req, res, targetLevel)) return;

    if (!email)    return res.status(400).json({ error: 'Email is required.' });
    if (!uniqueId) return res.status(400).json({ error: 'Unique ID is required.' });

    const emailLower = email.toLowerCase().trim();
    const uidTrimmed = uniqueId.trim();
    const fullName = `${firstName} ${middleName} ${lastName}`.replace(/\s+/g, ' ').trim();
    const now = nowIso();

    // Load all users to avoid compound Firestore queries requiring custom indexes
    const allUsersSnap = await db.collection('users').get();
    const allUsers = allUsersSnap.docs.map(d => ({ docId: d.id, ref: d.ref, ...d.data() }));

    const activeByEmail = allUsers.filter(u => (u.email || '').toLowerCase() === emailLower && u.status !== 'deleted');

    if (activeByEmail.length > 0) {
      // User with email already exists — UPDATE & re-assign to target level (UPSERT)
      const existingUser = activeByEmail[0];

      // Verify uniqueId is not used by ANOTHER active user
      if (uidTrimmed && uidTrimmed !== existingUser.uniqueId) {
        const otherWithUid = allUsers.find(u => u.uniqueId === uidTrimmed && u.docId !== existingUser.docId && u.status !== 'deleted');
        if (otherWithUid) {
          const otherName = otherWithUid.fullName || otherWithUid.email || 'another member';
          return res.status(409).json({ error: `Unique ID "${uidTrimmed}" is already registered to ${otherName}.` });
        }
      }

      const updates = {
        firstName: firstName || existingUser.firstName || '',
        middleName: middleName || existingUser.middleName || '',
        lastName: lastName || existingUser.lastName || '',
        fullName: fullName || existingUser.fullName || emailLower,
        phoneNumber: phoneNumber || existingUser.phoneNumber || '',
        uniqueId: uidTrimmed || existingUser.uniqueId || '',
        nationalId: uidTrimmed || existingUser.nationalId || '',
        equbLevel: targetLevel,
        level: targetLevel,
        adminId: req.user.role === 'admin' ? (req.user.adminId || req.user.uid || '') : (adminId || existingUser.adminId || ''),
        status: 'active',
        updatedAt: now,
      };

      await existingUser.ref.update(updates);
      const updated = await existingUser.ref.get();
      return res.status(200).json({
        userId: existingUser.docId,
        id: existingUser.docId,
        ...updated.data(),
        message: 'User updated and assigned to level.',
      });
    }

    // Check soft-deleted email user
    const deletedByEmail = allUsers.filter(u => (u.email || '').toLowerCase() === emailLower && u.status === 'deleted');
    if (deletedByEmail.length > 0) {
      const deletedUser = deletedByEmail[0];
      const updates = {
        firstName, middleName, lastName, fullName: fullName || emailLower,
        email: emailLower, phoneNumber,
        uniqueId: uidTrimmed, nationalId: uidTrimmed,
        equbLevel: targetLevel, level: targetLevel,
        adminId: req.user.role === 'admin' ? (req.user.adminId || req.user.uid || '') : adminId,
        status: 'active',
        hasWon: false,
        updatedAt: now,
      };
      await deletedUser.ref.update(updates);
      const updated = await deletedUser.ref.get();
      return res.status(200).json({
        userId: deletedUser.docId,
        id: deletedUser.docId,
        ...updated.data(),
        message: 'User restored and assigned to level.',
      });
    }

    // Check uniqueId collision with active user
    const activeByUid = allUsers.filter(u => u.uniqueId === uidTrimmed && u.status !== 'deleted');
    if (activeByUid.length > 0) {
      const existingUser = activeByUid[0];
      const name = existingUser.fullName || existingUser.email || 'another member';
      return res.status(409).json({ error: `Unique ID "${uidTrimmed}" is already registered to ${name}.` });
    }

    // Capacity check
    const cfg = levelCfg(targetLevel);
    const activeCount = allUsers.filter(u => ((u.equbLevel || u.level || '').toLowerCase() === targetLevel) && u.status !== 'deleted').length;
    if (activeCount >= cfg.max) {
      return res.status(422).json({ error: `${targetLevel} level is at full capacity (${cfg.max}).` });
    }

    // Create new user doc
    const data = {
      firstName, middleName, lastName, fullName: fullName || emailLower,
      email: emailLower, phoneNumber,
      uniqueId: uidTrimmed, nationalId: uidTrimmed,
      level: targetLevel, equbLevel: targetLevel,
      adminId: req.user.role === 'admin' ? (req.user.adminId || req.user.uid || '') : adminId,
      role: 'user', status: 'active',
      hasWon: false, participationHistory: [], balance: 0,
      createdAt: now, updatedAt: now,
    };

    const ref = await db.collection('users').add(data);
    return res.status(201).json({ userId: ref.id, id: ref.id, ...data, message: 'User registered successfully.' });
  } catch (err) {
    console.error('[admin/createUser error]', err);
    return res.status(500).json({ error: err.message });
  }
});

router.get('/users/:id', async (req, res) => {
  try {
    const doc = await requireManagedUser(req, res, req.params.id);
    if (!doc) return;
    return res.json({ userId: doc.id, id: doc.id, ...doc.data() });
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
      equbLevel  = existing.equbLevel || existing.level || 'low',
    } = req.body;

    const targetLevel = equbLevel.toLowerCase();

    // uniqueId change — re-check
    if (uniqueId && uniqueId !== existing.uniqueId) {
      const allUsersSnap = await db.collection('users').get();
      const taken = allUsersSnap.docs.find(d => d.id !== req.params.id && d.data().uniqueId === uniqueId.trim() && d.data().status !== 'deleted');
      if (taken) {
        return res.status(409).json({ error: 'Unique ID already taken by another active member.' });
      }
    }

    const fullName = `${firstName} ${middleName} ${lastName}`.replace(/\s+/g, ' ').trim();
    if (!await requireManagedLevel(req, res, targetLevel)) return;
    const updates = {
      firstName, middleName, lastName, fullName,
      phoneNumber, uniqueId,
      equbLevel: targetLevel, level: targetLevel,
      updatedAt: nowIso(),
    };

    await ref.update(updates);
    const updated = await ref.get();
    return res.json({ userId: req.params.id, id: req.params.id, ...updated.data(), message: 'User updated.' });
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

    const targetLevel = level.toLowerCase();
    await doc.ref.update({ equbLevel: targetLevel, level: targetLevel, updatedAt: nowIso() });
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
    const lvlLower = level.toLowerCase();
    if (!await requireManagedLevel(req, res, lvlLower)) return;

    // Load all active, non-winner users for this level
    const usersSnap = await db.collection('users').get();
    const eligibleDocs = usersSnap.docs.filter(d => {
      const u = d.data();
      const uLvl = (u.equbLevel || u.level || '').toLowerCase();
      return uLvl === lvlLower && (u.status || 'active') === 'active' && u.hasWon !== true;
    });

    if (eligibleDocs.length === 0) {
      return res.status(422).json({ error: `No eligible participants for ${level} level.` });
    }

    const eligible = eligibleDocs.map(d => ({ userId: d.id, id: d.id, ...d.data() }));
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
    const histSnap = await db.collection('draws').get();
    const levelDraws = histSnap.docs.filter(d => (d.data().equbLevel || d.data().level || '').toLowerCase() === lvlLower);
    const drawNumber = levelDraws.length + 1;

    const now = nowIso();
    const winnerName = winner.fullName || `${winner.firstName || ''} ${winner.lastName || ''}`.trim() || winner.email;
    const drawData = {
      equbLevel: lvlLower,
      level: lvlLower,
      adminId: req.user.adminId || req.user.uid || '',
      winnerId: winner.userId,
      winnerName,
      winnerUniqueId: winner.uniqueId || '',
      drawNumber,
      participants: eligible.map(u => u.userId),
      totalParticipants: eligible.length,
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
      winnerName,
      winnerUniqueId: winner.uniqueId || '',
      level: lvlLower,
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
    const lvlLower = req.params.level.toLowerCase();
    if (!await requireManagedLevel(req, res, lvlLower)) return;
    const snap = await db.collection('draws').get();
    const draws = snap.docs
      .map(d => ({ drawId: d.id, ...d.data() }))
      .filter(d => (d.equbLevel || d.level || '').toLowerCase() === lvlLower)
      .sort((a, b) => (b.drawNumber || 0) - (a.drawNumber || 0));
    return res.json(draws);
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
        users: usersSnap.docs.filter(d => ((d.data().equbLevel || d.data().level || '').toLowerCase() === level) && d.data().status !== 'deleted').length,
        draws: drawsSnap.docs.filter(d => (d.data().equbLevel || d.data().level || '').toLowerCase() === level).length,
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
// PUT /api/v1/admin/settings — Admin update own profile settings
// ─────────────────────────────────────────────────────────────────────────────
router.put('/settings', async (req, res) => {
  try {
    const role = req.user.role;
    const { fullName, username, phone, address, password, email } = req.body;
    const now = nowIso();
    const updates = { updatedAt: now };

    if (fullName) updates.fullName = fullName.trim();
    if (username) updates.username = username.trim();
    if (phone) updates.phone = phone.trim();
    if (address) updates.address = address.trim();
    if (password) updates.password = password.trim();
    if (email) updates.email = email.trim().toLowerCase();

    if (role === 'super_admin') {
      const superRef = db.collection('meta').doc('super_admin_profile');
      await superRef.set(updates, { merge: true });
      const updated = await superRef.get();
      return res.json({ id: 'super_admin_profile', ...updated.data(), message: 'Super admin settings updated successfully.' });
    }

    const adminId = req.user.adminId || req.user.uid || req.user.id;
    if (adminId) {
      const ref = db.collection('admins').doc(adminId);
      await ref.set(updates, { merge: true });
      const updated = await ref.get();
      return res.json({ adminId, id: adminId, ...updated.data(), message: 'Admin settings updated successfully.' });
    }

    // Fallback: lookup admin by email
    const adminEmail = (email || req.user.email || '').toLowerCase();
    if (adminEmail) {
      const byEmail = await db.collection('admins').where('email', '==', adminEmail).limit(1).get();
      if (!byEmail.empty) {
        await byEmail.docs[0].ref.set(updates, { merge: true });
        const updated = await byEmail.docs[0].ref.get();
        return res.json({ adminId: byEmail.docs[0].id, id: byEmail.docs[0].id, ...updated.data(), message: 'Admin settings updated successfully.' });
      }
    }

    return res.status(404).json({ error: 'Admin account record not found.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Helper — build full level stats for dashboard
// ─────────────────────────────────────────────────────────────────────────────
async function buildLevelStats(level) {
  const lvlLower = (level || 'low').toLowerCase();
  const cfg = levelCfg(lvlLower);

  const [usersSnap, drawsSnap] = await Promise.all([
    db.collection('users').get(),
    db.collection('draws').get(),
  ]);

  const users = usersSnap.docs
    .map(d => ({ userId: d.id, id: d.id, ...d.data() }))
    .filter(u => ((u.equbLevel || u.level || '').toLowerCase() === lvlLower) && u.status !== 'deleted');

  const active = users.filter(u => (u.status || 'active') === 'active');
  const eligible = active.filter(u => !u.hasWon);

  const draws = drawsSnap.docs
    .map(d => ({ drawId: d.id, id: d.id, ...d.data() }))
    .filter(d => (d.equbLevel || d.level || '').toLowerCase() === lvlLower)
    .sort((a, b) => (b.drawNumber || 0) - (a.drawNumber || 0));

  return {
    equbId: `equb_${lvlLower}`,
    level: lvlLower,
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
      id: u.userId,
      fullName: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(),
      firstName: u.firstName || '',
      middleName: u.middleName || '',
      lastName: u.lastName || '',
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
