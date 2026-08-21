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
      const snap = await db.collection('admins').doc(adminId).get();
      if (snap.exists && snap.data().status === 'active') {
        req.user = { role: 'admin', uid: adminId, adminId, ...snap.data() };
        return next();
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
