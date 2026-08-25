'use strict';

const { auth, db } = require('../config/firebase');

// ─────────────────────────────────────────────────────────────────────────────
// verifyToken middleware
// Validates Firebase ID tokens OR simple "role_token" strings issued by our
// own login endpoint (for admins whose accounts live in Firestore, not Auth).
// ─────────────────────────────────────────────────────────────────────────────
async function verifyToken(req, res, next) {
  const header = req.headers['authorization'] || '';
  const token  = header.startsWith('Bearer ') ? header.slice(7) : header;

  if (!token) {
    return res.status(401).json({ error: 'No token provided.' });
  }

  // ── Internal tokens issued by our login endpoint ─────────────────────────
  if (token === 'super_admin_token') {
    req.user = { role: 'super_admin', uid: 'super_admin' };
    return next();
  }

  if (token.startsWith('admin_token_')) {
    const adminId = token.replace('admin_token_', '');
    try {
      // First try exact doc ID lookup
      const snap = await db.collection('admins').doc(adminId).get();
      if (snap.exists && snap.data().status !== 'deleted') {
        req.user = { role: 'admin', uid: adminId, adminId, level: snap.data().level || 'low', ...snap.data() };
        return next();
      }
      // Fallback: search by adminId field, email, or username
      const byField = await db.collection('admins')
        .where('adminId', '==', adminId).limit(1).get();
      if (!byField.empty && byField.docs[0].data().status !== 'deleted') {
        const d = byField.docs[0];
        req.user = { role: 'admin', uid: d.id, adminId: d.id, level: d.data().level || 'low', ...d.data() };
        return next();
      }
      // Fallback: if adminId looks like an email, search by email
      if (adminId.includes('@')) {
        const byEmail = await db.collection('admins')
          .where('email', '==', adminId.toLowerCase()).limit(1).get();
        if (!byEmail.empty && byEmail.docs[0].data().status !== 'deleted') {
          const d = byEmail.docs[0];
          req.user = { role: 'admin', uid: d.id, adminId: d.id, level: d.data().level || 'low', ...d.data() };
          return next();
        }
      }
    } catch (_) {}
    return res.status(401).json({ error: 'Invalid admin token.' });
  }

  // ── Firebase ID token ─────────────────────────────────────────────────────
  try {
    const decoded = await auth.verifyIdToken(token);
    req.user = { uid: decoded.uid, email: decoded.email, role: 'user' };

    // Attach Firestore profile if available
    try {
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      if (userDoc.exists) {
        req.user = { ...req.user, ...userDoc.data() };
      }
    } catch (_) {}

    return next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token.' });
  }
}

// ── Role guard helpers ────────────────────────────────────────────────────────
function requireSuperAdmin(req, res, next) {
  if (req.user?.role === 'super_admin') return next();
  return res.status(403).json({ error: 'Super admin access required.' });
}

function requireAdmin(req, res, next) {
  if (req.user?.role === 'admin' || req.user?.role === 'super_admin') return next();
  return res.status(403).json({ error: 'Admin access required.' });
}

module.exports = { verifyToken, requireSuperAdmin, requireAdmin };
