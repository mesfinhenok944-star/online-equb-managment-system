'use strict';

// Load env vars FIRST — before any other require
require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });

const express = require('express');
const { db, nowIso } = require('./config/firebase');
const corsMiddleware = require('./middleware/cors');

// ── Route modules ──────────────────────────────────────────────────────────
const authRoutes       = require('./routes/auth');
const superAdminRoutes = require('./routes/superAdmin');
const adminRoutes      = require('./routes/admin');
const equbRoutes       = require('./routes/equbs');
const paymentRoutes    = require('./routes/payments');
const userRoutes       = require('./routes/users');

const app  = express();
const PORT = process.env.PORT || 8080;
const HOST = process.env.HOST || '0.0.0.0';

// ── Global middleware ──────────────────────────────────────────────────────
app.use(corsMiddleware);
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Request logger
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// ── Health check ───────────────────────────────────────────────────────────
app.get('/', (_req, res) => res.json({
  service: 'Online Equb Backend',
  version: '1.0.0',
  status:  'running',
  time:    nowIso(),
}));

app.get('/health', (_req, res) => res.json({ status: 'ok', time: nowIso() }));

// ── API Routes ─────────────────────────────────────────────────────────────
app.use('/api/v1/auth',        authRoutes);
app.use('/api/v1/super-admin', superAdminRoutes);
app.use('/api/v1/admin',       adminRoutes);
app.use('/api/v1/equbs',       equbRoutes);
app.use('/api/v1/payments',    paymentRoutes);
app.use('/api/v1/users',       userRoutes);

// ── 404 handler ────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.method} ${req.path} not found.` });
});

// ── Error handler ──────────────────────────────────────────────────────────
app.use((err, _req, res, _next) => {
  console.error('[Unhandled Error]', err);
  res.status(500).json({ error: 'Internal server error.', detail: err.message });
});

// ── Seed super admin profile on first boot ─────────────────────────────────
async function seedSuperAdmin() {
  try {
    const ref = db.collection('meta').doc('super_admin_profile');
    const doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        firstName: 'Super',
        lastName:  'Admin',
        fullName:  'Super Admin',
        email:     process.env.SUPER_ADMIN_EMAIL    || 'superadmin@equb.et',
        username:  process.env.SUPER_ADMIN_USERNAME || 'superadmin',
        password:  process.env.SUPER_ADMIN_PASSWORD || 'admin123',
        role:      'super_admin',
        createdAt: nowIso(),
        updatedAt: nowIso(),
      });
      console.log('[Seed] Super admin profile created in Firestore.');
    }
  } catch (err) {
    console.warn('[Seed] Could not seed super admin (Firebase may not be configured yet):', err.message);
  }
}

// ── Start server (with auto port release to prevent EADDRINUSE) ───────────
const { execSync } = require('child_process');

try {
  // Free target port if occupied by a previous process
  execSync(`fuser -k ${PORT}/tcp || true`, { stdio: 'ignore' });
} catch (_) {}

const server = app.listen(PORT, HOST, async () => {
  console.log('');
  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║        Online Equb Backend — Running             ║');
  console.log(`║  URL  : http://${HOST}:${PORT}                   ║`);
  console.log(`║  Time : ${nowIso()}  ║`);
  console.log('╚══════════════════════════════════════════════════╝');
  console.log('');
  console.log('  Endpoints:');
  console.log(`  POST   http://localhost:${PORT}/api/v1/auth/login`);
  console.log(`  POST   http://localhost:${PORT}/api/v1/auth/register`);
  console.log(`  GET    http://localhost:${PORT}/api/v1/super-admin/admins`);
  console.log(`  POST   http://localhost:${PORT}/api/v1/super-admin/admins`);
  console.log(`  GET    http://localhost:${PORT}/api/v1/admin/dashboard`);
  console.log(`  GET    http://localhost:${PORT}/api/v1/admin/users`);
  console.log(`  POST   http://localhost:${PORT}/api/v1/admin/draw/:level`);
  console.log(`  GET    http://localhost:${PORT}/api/v1/equbs/`);
  console.log(`  POST   http://localhost:${PORT}/api/v1/payments/initiate`);
  console.log(`  GET    http://localhost:${PORT}/api/v1/users/profile`);
  console.log('');

  await seedSuperAdmin();
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.warn(`[Port ${PORT}] Busy. Auto-clearing zombie processes...`);
    try {
      execSync(`fuser -k ${PORT}/tcp || true`, { stdio: 'ignore' });
    } catch (_) {}
  } else {
    console.error('[Server Error]', err);
  }
});

module.exports = app;
