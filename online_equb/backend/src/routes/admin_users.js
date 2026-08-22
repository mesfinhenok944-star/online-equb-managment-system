// backend/src/routes/admin.js

'use strict';

const { Router } = require('express');
const { db, now, nowIso } = require('../config/firebase');
const { verifyToken, requireAdmin } = require('../middleware/auth');

const router = Router();

// Require admin token for all routes
router.use(verifyToken, requireAdmin);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/admin/users/register
// Register a new user (one-to-one mapping by national ID)
// ─────────────────────────────────────────────────────────────────────────────
router.post('/users/register', async (req, res) => {
  try {
    const {
      firstName, lastName, middleName,
      email, phoneNumber, nationalId
    } = req.body;

    // Get admin info from token (stored in req.user)
    const adminId = req.user?.adminId || '';
    const adminLevel = req.user?.level || 'low';

    if (!firstName || !lastName || !email || !phoneNumber || !nationalId) {
      return res.status(400).json({
        error: 'Missing required fields'
      });
    }

    // Check if national ID is already registered (one-to-one)
    const existingNIDSnap = await db.collection('users').where('nationalId', '==', nationalId).get();
    const activeNID = existingNIDSnap.docs.filter(d => d.data().status !== 'deleted');

    if (activeNID.length > 0) {
      return res.status(409).json({
        error: 'National ID already registered (One-to-One mapping)'
      });
    }

    // Check if email exists
    const existingEmailSnap = await db.collection('users').where('email', '==', email.toLowerCase().trim()).get();
    const activeEmail = existingEmailSnap.docs.filter(d => d.data().status !== 'deleted');

    if (activeEmail.length > 0) {
      return res.status(409).json({
        error: 'Email already registered'
      });
    }

    // Create user
    const fullName = `${firstName} ${middleName || ''} ${lastName}`.replace(/\s+/g, ' ').trim();
    const userData = {
      firstName,
      lastName,
      middleName: middleName || '',
      fullName,
      email: email.toLowerCase().trim(),
      phoneNumber: phoneNumber || '',
      nationalId: nationalId || '',
      uniqueId: nationalId || '',
      level: adminLevel,
      equbLevel: adminLevel,
      adminId: adminId || '',
      role: 'user',
      status: 'active',
      hasWon: false,
      balance: 0,
      participationHistory: [],
      createdAt: nowIso(),
      updatedAt: nowIso()
    };

    const userRef = await db.collection('users').add(userData);

    return res.status(201).json({
      message: 'User registered successfully',
      data: {
        userId: userRef.id,
        ...userData
      }
    });
  } catch (error) {
    console.error('[admin/registerUser]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/admin/users?status=all|active|suspended
// Get users for this admin's level
// ─────────────────────────────────────────────────────────────────────────────
router.get('/users', async (req, res) => {
  try {
    const adminLevel = req.user?.level || 'low';
    const { status = 'all' } = req.query;

    const snapshot = await db.collection('users').get();
    let docs = snapshot.docs.filter(d => (d.data().level === adminLevel || d.data().equbLevel === adminLevel));
    if (status !== 'all') {
      docs = docs.filter(d => d.data().status === status);
    } else {
      docs = docs.filter(d => d.data().status !== 'deleted');
    }
    docs.sort((a, b) => (b.data().createdAt || '').localeCompare(a.data().createdAt || ''));

    const users = docs.map(doc => ({
      userId: doc.id,
      ...doc.data()
    }));

    return res.status(200).json({
      data: users,
      total: users.length
    });
  } catch (error) {
    console.error('[admin/getUsers]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/admin/users/search?q=query
// Search users by name, email, phone, national ID
// ─────────────────────────────────────────────────────────────────────────────
router.get('/users/search', async (req, res) => {
  try {
    const adminLevel = req.user?.level || 'low';
    const { q = '' } = req.query;

    const snapshot = await db.collection('users').get();
    const docs = snapshot.docs.filter(d =>
      (d.data().level === adminLevel || d.data().equbLevel === adminLevel) &&
      d.data().status !== 'deleted'
    );

    const users = snapshot.docs
      .map(doc => ({ userId: doc.id, ...doc.data() }))
      .filter(user => {
        const searchTerm = q.toLowerCase();
        const fullName = `${user.firstName} ${user.lastName}`.toLowerCase();
        return fullName.includes(searchTerm) ||
               user.email.toLowerCase().includes(searchTerm) ||
               user.phoneNumber.includes(searchTerm) ||
               user.nationalId.includes(searchTerm);
      });

    return res.status(200).json({
      data: users,
      total: users.length
    });
  } catch (error) {
    console.error('[admin/searchUsers]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/admin/users/:id
// Get user by ID
// ─────────────────────────────────────────────────────────────────────────────
router.get('/users/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const doc = await db.collection('users').doc(id).get();
    if (!doc.exists || doc.data().status === 'deleted') {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.status(200).json({
      data: {
        userId: doc.id,
        ...doc.data()
      }
    });
  } catch (error) {
    console.error('[admin/getUser]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/admin/users/:id
// Update user
// ─────────────────────────────────────────────────────────────────────────────
router.put('/users/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;

    const doc = await db.collection('users').doc(id).get();
    if (!doc.exists || doc.data().status === 'deleted') {
      return res.status(404).json({ error: 'User not found' });
    }

    // Prevent updating certain fields
    delete updates.nationalId; // Can't change national ID
    delete updates.createdAt;
    delete updates.level; // Can't change level
    delete updates.adminId;

    await db.collection('users').doc(id).update({
      ...updates,
      updatedAt: now()
    });

    const updatedDoc = await db.collection('users').doc(id).get();

    return res.status(200).json({
      message: 'User updated successfully',
      data: {
        userId: updatedDoc.id,
        ...updatedDoc.data()
      }
    });
  } catch (error) {
    console.error('[admin/updateUser]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/v1/admin/users/:id/suspend
// Suspend user
// ─────────────────────────────────────────────────────────────────────────────
router.patch('/users/:id/suspend', async (req, res) => {
  try {
    const { id } = req.params;
    const { reason } = req.body;

    const doc = await db.collection('users').doc(id).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    await db.collection('users').doc(id).update({
      status: 'suspended',
      suspensionReason: reason || 'No reason provided',
      suspendedAt: now(),
      updatedAt: now()
    });

    const updatedDoc = await db.collection('users').doc(id).get();

    return res.status(200).json({
      message: 'User suspended successfully',
      data: {
        userId: updatedDoc.id,
        ...updatedDoc.data()
      }
    });
  } catch (error) {
    console.error('[admin/suspendUser]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/v1/admin/users/:id/activate
// Activate user
// ─────────────────────────────────────────────────────────────────────────────
router.patch('/users/:id/activate', async (req, res) => {
  try {
    const { id } = req.params;

    const doc = await db.collection('users').doc(id).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    await db.collection('users').doc(id).update({
      status: 'active',
      suspendedAt: null,
      suspensionReason: null,
      updatedAt: now()
    });

    const updatedDoc = await db.collection('users').doc(id).get();

    return res.status(200).json({
      message: 'User activated successfully',
      data: {
        userId: updatedDoc.id,
        ...updatedDoc.data()
      }
    });
  } catch (error) {
    console.error('[admin/activateUser]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/v1/admin/users/:id
// Delete user (soft delete)
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/users/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const doc = await db.collection('users').doc(id).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    await db.collection('users').doc(id).update({
      status: 'deleted',
      deletedAt: now(),
      updatedAt: now()
    });

    return res.status(200).json({
      message: 'User deleted successfully'
    });
  } catch (error) {
    console.error('[admin/deleteUser]', error);
    return res.status(500).json({ error: error.message });
  }
});

module.exports = router;
