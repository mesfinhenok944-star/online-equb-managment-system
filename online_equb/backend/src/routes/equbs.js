'use strict';

const { Router } = require('express');
const { db, nowIso } = require('../config/firebase');
const { verifyToken } = require('../middleware/auth');

const router = Router();
router.use(verifyToken);

const EQUB_DEFAULTS = {
  low:    { equbId: 'equb_low',    name: 'ዝቅተኛ · Low Level EQUB',    level: 'low',    price: 5000,  netPrize: 465000, adminFee: 35000, maxParticipants: 100 },
  medium: { equbId: 'equb_medium', name: 'መካከለኛ · Medium Level EQUB', level: 'medium', price: 10000, netPrize: 465000, adminFee: 35000, maxParticipants: 100 },
  high:   { equbId: 'equb_high',   name: 'ከፍተኛ · High Level EQUB',   level: 'high',   price: 20000, netPrize: 360000, adminFee: 40000, maxParticipants: 100 },
};

async function getOrBuildEqub(level) {
  const snap = await db.collection('equbs').where('level', '==', level).limit(1).get();
  if (!snap.empty) return { id: snap.docs[0].id, ...snap.docs[0].data() };

  // Auto-create from defaults if not in Firestore yet
  const def = EQUB_DEFAULTS[level];
  if (!def) return null;

  const data = { ...def, currentParticipants: 0, drawsHeld: 0, totalCollected: 0, status: 'active', createdAt: nowIso() };
  const ref  = await db.collection('equbs').add(data);
  return { id: ref.id, ...data };
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/equbs/   — list all equbs (default + custom registered)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const equbsSnap = await db.collection('equbs').get();
    const storedEqubs = equbsSnap.docs.map(d => ({ id: d.id, ...d.data() }));

    const levelsMap = new Map();

    // 1. Defaults
    for (const level of ['low', 'medium', 'high']) {
      const snap = await db.collection('users')
        .where('equbLevel', '==', level).where('status', '!=', 'deleted').get();
      const def = EQUB_DEFAULTS[level];
      levelsMap.set(level, {
        ...def,
        currentParticipants: snap.size,
        status: 'active',
        description: `${def.name} — ${def.price.toLocaleString()} ETB/cycle`,
      });
    }

    // 2. Custom registered levels
    for (const item of storedEqubs) {
      const key = item.level || item.id;
      const snap = await db.collection('users')
        .where('equbLevel', '==', key).where('status', '!=', 'deleted').get();
      levelsMap.set(key, {
        ...item,
        currentParticipants: snap.size,
        status: item.status || 'active',
      });
    }

    return res.json(Array.from(levelsMap.values()));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/equbs   — Register a new Equb Level (Super Admin / Admin)
// ─────────────────────────────────────────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const {
      name, level, price, netPrize, maxParticipants, cycle, description
    } = req.body;

    if (!name || !price) {
      return res.status(400).json({ error: 'Name and price are required.' });
    }

    const key = (level || name.toLowerCase().replace(/[^a-z0-9]/g, '_')).trim();

    const data = {
      equbId: `equb_${key}`,
      name,
      level: key,
      price: Number(price),
      netPrize: Number(netPrize || (price * (maxParticipants || 10))),
      adminFee: Number(price * 0.05),
      maxParticipants: Math.max(100, Number(maxParticipants || 100)),
      cycle: cycle || 'Weekly',
      description: description || `${name} — ${price} ETB/cycle`,
      currentParticipants: 0,
      drawsHeld: 0,
      totalCollected: 0,
      status: 'active',
      createdAt: nowIso(),
    };

    const ref = await db.collection('equbs').add(data);
    return res.status(201).json({ id: ref.id, ...data });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/equbs/:id   — single equb by id or level name
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const id = req.params.id;

    // Try Firestore doc first
    const byId = await db.collection('equbs').doc(id).get();
    if (byId.exists) return res.json({ id: byId.id, ...byId.data() });

    // Try by level field
    const byLevel = await db.collection('equbs').where('level', '==', id).limit(1).get();
    if (!byLevel.empty) return res.json({ id: byLevel.docs[0].id, ...byLevel.docs[0].data() });

    // Fallback to default
    const def = EQUB_DEFAULTS[id];
    if (def) return res.json({ ...def, currentParticipants: 0 });

    return res.status(404).json({ error: 'Equb not found.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/equbs/:id/join
// ─────────────────────────────────────────────────────────────────────────────
router.post('/:id/join', async (req, res) => {
  try {
    const equbId = req.params.id;
    const userId = req.user?.uid || req.user?.userId || '';

    if (!userId) return res.status(401).json({ error: 'User not identified.' });

    // Determine level from equb
    const equb = await getOrBuildEqub(equbId) || { level: equbId };
    const level = equb.level || equbId;

    // Check already joined
    const existing = await db.collection('users').doc(userId).get();
    if (existing.exists && existing.data().equbLevel === level) {
      return res.status(409).json({ error: 'Already joined this level.' });
    }

    await db.collection('users').doc(userId).update({ equbLevel: level, updatedAt: nowIso() });

    return res.json({
      participantId: userId,
      equbId,
      message: 'Joined successfully.',
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/equbs/:id/stats
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id/stats', async (req, res) => {
  try {
    const id    = req.params.id;
    const level = EQUB_DEFAULTS[id] ? id : id.replace('equb_', '');
    const cfg   = EQUB_DEFAULTS[level] || EQUB_DEFAULTS.low;

    const [usersSnap, drawsSnap] = await Promise.all([
      db.collection('users').where('equbLevel', '==', level).where('status', '!=', 'deleted').get(),
      db.collection('draws').where('equbLevel', '==', level).get(),
    ]);

    return res.json({
      equbId: id,
      level,
      currentParticipants: usersSnap.size,
      maxParticipants: cfg.maxParticipants,
      totalCollected: usersSnap.size * cfg.price,
      drawsHeld: drawsSnap.size,
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/equbs/:id/draws
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id/draws', async (req, res) => {
  try {
    const level = req.params.id.replace('equb_', '');
    const snap  = await db.collection('draws')
      .where('equbLevel', '==', level)
      .orderBy('drawNumber', 'desc').get();
    return res.json(snap.docs.map(d => ({ drawId: d.id, ...d.data() })));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
