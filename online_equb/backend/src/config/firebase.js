'use strict';

const admin = require('firebase-admin');
const path  = require('path');
const fs    = require('fs');

// ─────────────────────────────────────────────────────────────────────────────
// Firebase Admin SDK Initialisation
// Supports two strategies:
//   1. GOOGLE_APPLICATION_CREDENTIALS env var pointing to a JSON key file
//   2. Inline env vars FIREBASE_PROJECT_ID / CLIENT_EMAIL / PRIVATE_KEY
// ─────────────────────────────────────────────────────────────────────────────

let app;
const useRealFirebase = process.env.FIREBASE_USE_REAL === 'true';

function initFirebase() {
  if (admin.apps.length > 0) {
    app = admin.apps[0];
    return;
  }

  const keyFilePath = process.env.GOOGLE_APPLICATION_CREDENTIALS
    ? path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS)
    : null;

  try {
    if (useRealFirebase && keyFilePath && fs.existsSync(keyFilePath)) {
      // Strategy 1 — JSON service account file
      const serviceAccount = JSON.parse(fs.readFileSync(keyFilePath, 'utf8'));
      app = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      console.log('[Firebase] Initialised with service account file.');
      return;
    }

    const projectId   = process.env.FIREBASE_PROJECT_ID;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const privateKey  = (process.env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n');

    const credentialsLookReal =
      useRealFirebase &&
      projectId &&
      clientEmail &&
      privateKey.includes('BEGIN PRIVATE KEY');

    if (credentialsLookReal) {
      // Strategy 2 — inline env vars
      app = admin.initializeApp({
        credential: admin.credential.cert({ projectId, clientEmail, privateKey }),
      });
      console.log('[Firebase] Initialised with inline credentials.');
      return;
    }

    // Strategy 3 — Emulator / Application Default Credentials
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      app = admin.initializeApp({ projectId: projectId || 'equb-local' });
      console.log('[Firebase] Initialised with Firestore emulator.');
      return;
    }

    // Strategy 4 — Application Default Credentials (Google Cloud Run / GKE)
    // Only use if GOOGLE_APPLICATION_CREDENTIALS is explicitly set and valid.
    if (useRealFirebase && process.env.GOOGLE_APPLICATION_CREDENTIALS && keyFilePath && fs.existsSync(keyFilePath)) {
      app = admin.initializeApp();
      console.log('[Firebase] Initialised with Application Default Credentials.');
      return;
    }

    // No valid credentials found — throw so we fall into mock mode
    throw new Error('No valid Firebase credentials found.');
  } catch (err) {
    // Graceful fallback — start server without Firebase so routes can still
    // return mock data. Warn clearly.
    console.warn('');
    console.warn('╔══════════════════════════════════════════════════════════════╗');
    console.warn('║  WARNING: Firebase not configured — running in MOCK mode.    ║');
    console.warn('║  Set GOOGLE_APPLICATION_CREDENTIALS or inline env vars in    ║');
    console.warn('║  backend/.env to connect to real Firestore.                  ║');
    console.warn('╚══════════════════════════════════════════════════════════════╝');
    console.warn('');
    // Init with a dummy project so admin.firestore() doesn't throw
    if (admin.apps.length === 0) {
      app = admin.initializeApp({ projectId: 'equb-mock' });
    }
  }
}

initFirebase();

// ─────────────────────────────────────────────────────────────────────────────
// In-Memory Firestore & Auth Mock for Offline/Local Dev Mode
// ─────────────────────────────────────────────────────────────────────────────
class MemoryQuery {
  constructor(collection, filters = [], order = null, limitVal = null) {
    this.collection = collection;
    this.filters = filters;
    this.order = order;
    this.limitVal = limitVal;
  }

  where(field, op, val) {
    return new MemoryQuery(this.collection, [...this.filters, { field, op, val }], this.order, this.limitVal);
  }

  orderBy(field, dir = 'asc') {
    return new MemoryQuery(this.collection, this.filters, { field, dir }, this.limitVal);
  }

  limit(n) {
    return new MemoryQuery(this.collection, this.filters, this.order, n);
  }

  async get() {
    let items = Array.from(this.collection.docs.entries()).map(([id, data]) => ({
      id,
      ref: this.collection.doc(id).ref,
      data: () => ({ ...data }),
    }));

    for (const filter of this.filters) {
      const { field, op, val } = filter;
      items = items.filter((item) => {
        const d = item.data();
        const itemVal = d[field];
        if (op === '==') return itemVal === val;
        if (op === '!=') return itemVal !== val;
        if (op === '>=') return itemVal >= val;
        if (op === '<=') return itemVal <= val;
        if (op === '>') return itemVal > val;
        if (op === '<') return itemVal < val;
        return true;
      });
    }

    if (this.order) {
      const { field, dir } = this.order;
      items.sort((a, b) => {
        const va = a.data()[field] || '';
        const vb = b.data()[field] || '';
        if (va < vb) return dir === 'desc' ? 1 : -1;
        if (va > vb) return dir === 'desc' ? -1 : 1;
        return 0;
      });
    }

    if (this.limitVal) {
      items = items.slice(0, this.limitVal);
    }

    return {
      empty: items.length === 0,
      size: items.length,
      docs: items,
    };
  }
}

class MemoryCollection {
  constructor(name) {
    this.name = name;
    this.docs = new Map();
  }

  doc(id) {
    const docId = id || `doc_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
    const col = this;
    return {
      id: docId,
      ref: {
        update: async (data) => col._updateDoc(docId, data),
        delete: async () => col._deleteDoc(docId),
      },
      get: async () => {
        const data = col.docs.get(docId);
        return {
          id: docId,
          ref: this.doc(docId).ref,
          exists: !!data,
          data: () => (data ? { ...data } : undefined),
        };
      },
      set: async (data, options = {}) => col._setDoc(docId, data, options),
      update: async (data) => col._updateDoc(docId, data),
      delete: async () => col._deleteDoc(docId),
    };
  }

  async add(data) {
    const id = `id_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
    await this._setDoc(id, data);
    return { id, ref: this.doc(id).ref };
  }

  _setDoc(id, data, options = {}) {
    if (options.merge && this.docs.has(id)) {
      this.docs.set(id, { ...this.docs.get(id), ...data });
    } else {
      this.docs.set(id, { ...data });
    }
    return Promise.resolve();
  }

  _updateDoc(id, data) {
    if (this.docs.has(id)) {
      this.docs.set(id, { ...this.docs.get(id), ...data });
    } else {
      this.docs.set(id, { ...data });
    }
    return Promise.resolve();
  }

  _deleteDoc(id) {
    this.docs.delete(id);
    return Promise.resolve();
  }

  where(field, op, val) {
    return new MemoryQuery(this, [{ field, op, val }]);
  }

  orderBy(field, dir = 'asc') {
    return new MemoryQuery(this, [], { field, dir });
  }

  limit(n) {
    return new MemoryQuery(this, [], null, n);
  }

  async get() {
    return new MemoryQuery(this).get();
  }
}

class MemoryDb {
  constructor() {
    this.collections = new Map();
  }

  collection(name) {
    if (!this.collections.has(name)) {
      this.collections.set(name, new MemoryCollection(name));
    }
    return this.collections.get(name);
  }
}

let db, auth;
let isRealFirebase = false;

try {
  const keyFilePath = process.env.GOOGLE_APPLICATION_CREDENTIALS
    ? path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS)
    : null;

  const projectId   = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey  = (process.env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n');

  const inlineCredentialsLookReal =
    useRealFirebase &&
    projectId && clientEmail && privateKey.includes('BEGIN PRIVATE KEY');
  if ((useRealFirebase && keyFilePath && fs.existsSync(keyFilePath)) || inlineCredentialsLookReal) {
    db = admin.firestore();
    auth = admin.auth();
    isRealFirebase = true;
  } else {
    throw new Error('Using MemoryDb fallback');
  }
} catch (_) {
  console.log('[Firebase] Running in standalone MemoryStore mode.');
  db = new MemoryDb();
  auth = {
    createUser: async (opts) => ({ uid: `usr_${Date.now()}`, ...opts }),
    verifyIdToken: async (t) => ({ uid: t }),
    updateUser: async (uid, data) => ({ uid, ...data }),
  };
}

// Seed initial default admin in MemoryDb if not exists
(async () => {
  try {
    const adminRef = db.collection('admins').doc('admin_low_default');
    const existing = await adminRef.get();
    if (!existing.exists) {
      await adminRef.set({
        firstName: 'Low', lastName: 'Admin', fullName: 'Low Level Admin',
        email: 'admin@equb.et', username: 'admin', password: 'admin123',
        level: 'low', role: 'admin', status: 'active',
        createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
      });
    }
  } catch (_) {}
})();

// ─────────────────────────────────────────────────────────────────────────────
// Convenience wrappers around Firestore so routes stay clean
// ─────────────────────────────────────────────────────────────────────────────

const now = () => isRealFirebase ? admin.firestore.FieldValue.serverTimestamp() : new Date().toISOString();
const nowIso = () => new Date().toISOString();
const increment = (n = 1) => isRealFirebase ? admin.firestore.FieldValue.increment(n) : n;
const arrayUnion = (...items) => isRealFirebase ? admin.firestore.FieldValue.arrayUnion(...items) : items;

module.exports = { admin, db, auth, now, nowIso, increment, arrayUnion };
