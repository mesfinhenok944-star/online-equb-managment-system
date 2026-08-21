'use strict';

const { Router } = require('express');
const { db, nowIso } = require('../config/firebase');
const { verifyToken, requireSuperAdmin } = require('../middleware/auth');

const router = Router();

// All super-admin routes require a valid super-admin token
router.use(verifyToken, requireSuperAdmin);

// ─────────────────────────────────────────────────────────────────────────────
// Helper — build clean admin object from Firestore doc
// ─────────────────────────────────────────────────────────────────────────────
function formatAdmin(doc) {
  return { adminId: doc.id, ...doc.data() };
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/super-admin/admins?level=all|low|medium|high&status=all|active|suspended
// List all admins (multiple admins per level supported)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/admins', async (req, res) => {
  try {
    const { level = 'all', status = 'all' } = req.query;

    let query = db.collection('admins');
    if (level !== 'all') query = query.where('level', '==', level);
    if (status !== 'all') query = query.where('status', '==', status);

    const snap = await query.orderBy('createdAt', 'desc').get();
    const admins = snap.docs
      .filter(d => d.data().status !== 'deleted')
      .map(formatAdmin);

    return res.json(admins);
  } catch (err) {
    console.error('[superAdmin/getAdmins]', err);
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/super-admin/admins
// Create / assign a new admin to an equb level
// ─────────────────────────────────────────────────────────────────────────────
router.post('/admins', async (req, res) => {
  try {
    const {
      firstName = '', middleName = '', lastName = '',
      email = '', username, password = '',
      phone = '', address = '', level = 'low',
      contactInfo = {},
    } = req.body;

    if (!email) return res.status(400).json({ error: 'Email is required.' });

    const emailLower = email.toLowerCase().trim();
    const usernameFinal = (username || emailLower.split('@')[0]).toLowerCase().trim();

    // Duplicate checks
    const byEmail = await db.collection('admins')
      .where('email', '==', emailLower)
      .where('status', '!=', 'deleted').limit(1).get();
    if (!byEmail.empty) return res.status(409).json({ error: 'Email already registered.' });

    const byUsername = await db.collection('admins')
      .where('username', '==', usernameFinal)
      .where('status', '!=', 'deleted').limit(1).get();
    if (!byUsername.empty) return res.status(409).json({ error: 'Username already taken.' });

    const fullName = `${firstName} ${middleName} ${lastName}`.replace(/\s+/g, ' ').trim();
    const now = nowIso();

    const data = {
      firstName, middleName, lastName, fullName,
      email: emailLower, username: usernameFinal, password,
      phone, address, level,
      role: 'admin', status: 'active',
      contactInfo,
      permissions: defaultPermissions(level),
      createdAt: now, updatedAt: now,
    };

    const ref = await db.collection('admins').add(data);

    return res.status(201).json({
      adminId: ref.id, ...data,
      message: 'Admin assigned successfully.',
    });
  } catch (err) {
    console.error('[superAdmin/createAdmin]', err);
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/super-admin/admins/:id
// ─────────────────────────────────────────────────────────────────────────────
router.get('/admins/:id', async (req, res) => {
  try {
    const doc = await db.collection('admins').doc(req.params.id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Admin not found.' });
    return res.json(formatAdmin(doc));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/super-admin/admins/:id
// Update admin fields (email cannot be changed)
// ─────────────────────────────────────────────────────────────────────────────
router.put('/admins/:id', async (req, res) => {
  try {
    const ref = db.collection('admins').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ error: 'Admin not found.' });

    const existing = doc.data();
    const {
      firstName = existing.firstName,
      middleName = existing.middleName,
      lastName = existing.lastName,
      phone = existing.phone,
      address = existing.address,
      level = existing.level,
      contactInfo = existing.contactInfo,
      status = existing.status,
    } = req.body;

    const fullName = `${firstName} ${middleName} ${lastName}`.replace(/\s+/g, ' ').trim();

    const updates = {
      firstName, middleName, lastName, fullName,
      phone, address, level, contactInfo, status,
      updatedAt: nowIso(),
    };

    await ref.update(updates);
    const updated = await ref.get();
    return res.json({ adminId: req.params.id, ...updated.data(), message: 'Admin updated.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/v1/super-admin/admins/:id  (soft delete)
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/admins/:id', async (req, res) => {
  try {
    const ref = db.collection('admins').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ error: 'Admin not found.' });

    await ref.update({ status: 'deleted', deletedAt: nowIso() });
    return res.json({ message: 'Admin deleted successfully.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/super-admin/admins/:id/suspend
// ─────────────────────────────────────────────────────────────────────────────
router.put('/admins/:id/suspend', async (req, res) => {
  try {
    const { reason = '' } = req.body;
    await db.collection('admins').doc(req.params.id).update({
      status: 'suspended',
      suspensionReason: reason,
      suspendedAt: nowIso(),
    });
    return res.json({ message: 'Admin suspended.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/super-admin/admins/:id/activate
// ─────────────────────────────────────────────────────────────────────────────
router.put('/admins/:id/activate', async (req, res) => {
  try {
    await db.collection('admins').doc(req.params.id).update({
      status: 'active',
      updatedAt: nowIso(),
    });
    return res.json({ message: 'Admin activated.' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/super-admin/stats
// ─────────────────────────────────────────────────────────────────────────────
router.get('/stats', async (req, res) => {
  try {
    const [adminsSnap, usersSnap, drawsSnap] = await Promise.all([
      db.collection('admins').get(),
      db.collection('users').get(),
      db.collection('draws').get(),
    ]);

    const admins = adminsSnap.docs.map(d => d.data());
    const users  = usersSnap.docs.map(d => d.data());

    const countBy = (arr, field, val) => arr.filter(a => a[field] === val).length;

    return res.json({
      admins: {
        total:     admins.filter(a => a.status !== 'deleted').length,
        active:    countBy(admins, 'status', 'active'),
        suspended: countBy(admins, 'status', 'suspended'),
        low:       admins.filter(a => a.level === 'low'    && a.status !== 'deleted').length,
        medium:    admins.filter(a => a.level === 'medium' && a.status !== 'deleted').length,
        high:      admins.filter(a => a.level === 'high'   && a.status !== 'deleted').length,
      },
      users: {
        total:     users.filter(u => u.status !== 'deleted').length,
        active:    countBy(users, 'status', 'active'),
        suspended: countBy(users, 'status', 'suspended'),
      },
      draws: { total: drawsSnap.size },
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/super-admin/profile
// PUT /api/v1/super-admin/profile
// ─────────────────────────────────────────────────────────────────────────────
router.get('/profile', async (req, res) => {
  try {
    const doc = await db.collection('meta').doc('super_admin_profile').get();
    if (doc.exists) return res.json(doc.data());
    return res.json({
      email: process.env.SUPER_ADMIN_EMAIL || 'superadmin@equb.et',
      username: process.env.SUPER_ADMIN_USERNAME || 'superadmin',
      fullName: 'Super Admin', role: 'super_admin',
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

router.put('/profile', async (req, res) => {
  try {
    const updates = { ...req.body, updatedAt: nowIso() };
    delete updates.password; // password change is separate
    await db.collection('meta').doc('super_admin_profile').set(updates, { merge: true });
    return res.json({ message: 'Profile updated.', ...updates });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ── helper ─────────────────────────────────────────────────────────────────
function defaultPermissions(level) {
  return {
    canAddUsers: true, canEditUsers: true, canDeleteUsers: true,
    canViewUsers: true, canManageEqubs: true, canRunAlgorithms: true,
    canManagePayments: true, canViewReports: true,
    canSendNotifications: true, canViewAnalytics: true,
    canExportData: level === 'medium' || level === 'high',
    canManageAdmins: false,
  };
}

module.exports = router;
