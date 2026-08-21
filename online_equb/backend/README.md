# Online Equb — Backend

Node.js/Express server with Firebase Admin SDK.  
All data lives in **Firebase Firestore**. Authentication uses **Firebase Auth** for regular users and a custom password-based flow for super admin and admins.

---

## Project Structure

```
backend/
├── .env                      ← environment variables (never commit)
├── package.json
├── serviceAccountKey.json    ← Firebase service account (download from console, never commit)
└── src/
    ├── server.js             ← entry point
    ├── config/
    │   └── firebase.js       ← Firebase Admin SDK init
    ├── middleware/
    │   ├── auth.js           ← token verification + role guards
    │   └── cors.js           ← CORS config
    └── routes/
        ├── auth.js           ← /api/v1/auth/*
        ├── superAdmin.js     ← /api/v1/super-admin/*
        ├── admin.js          ← /api/v1/admin/*
        ├── equbs.js          ← /api/v1/equbs/*
        ├── payments.js       ← /api/v1/payments/*
        └── users.js          ← /api/v1/users/*
```

---

## Setup

### 1. Install Node.js
Make sure Node.js ≥ 18 is installed:
```bash
node -v
```

### 2. Install dependencies
```bash
cd backend
npm install
```

### 3. Firebase Service Account
1. Go to **Firebase Console** → Project Settings → **Service Accounts**
2. Click **Generate new private key** → download the JSON file
3. Rename it to `serviceAccountKey.json` and place it in the `backend/` folder

### 4. Configure .env
Edit `backend/.env` and fill in your Firebase project details:
```env
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
FIREBASE_PROJECT_ID=your-actual-project-id
SUPER_ADMIN_EMAIL=superadmin@equb.et
SUPER_ADMIN_USERNAME=superadmin
SUPER_ADMIN_PASSWORD=admin123
PORT=8080
```

### 5. Firestore Security Rules (Firebase Console)
Set these rules in **Firestore → Rules**:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```
> Tighten these rules before going to production.

---

## Running the Server

### Development (auto-restart on file change)
```bash
cd backend
npm run dev
```

### Production
```bash
cd backend
npm start
```

Server starts at: **http://localhost:8080**

---

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/v1/auth/login` | None | Login (super admin / admin / user) |
| POST | `/api/v1/auth/register` | None | Register new user |
| GET | `/api/v1/super-admin/admins` | Super Admin | List all admins |
| POST | `/api/v1/super-admin/admins` | Super Admin | Create admin |
| PUT | `/api/v1/super-admin/admins/:id` | Super Admin | Update admin |
| DELETE | `/api/v1/super-admin/admins/:id` | Super Admin | Delete admin |
| PUT | `/api/v1/super-admin/admins/:id/suspend` | Super Admin | Suspend admin |
| PUT | `/api/v1/super-admin/admins/:id/activate` | Super Admin | Activate admin |
| GET | `/api/v1/super-admin/stats` | Super Admin | System-wide stats |
| GET | `/api/v1/admin/dashboard` | Admin | All levels dashboard |
| GET | `/api/v1/admin/dashboard/:level` | Admin | Single level dashboard |
| GET | `/api/v1/admin/users` | Admin | List users |
| POST | `/api/v1/admin/users` | Admin | Create user |
| PUT | `/api/v1/admin/users/:id` | Admin | Update user |
| DELETE | `/api/v1/admin/users/:id` | Admin | Delete user |
| PUT | `/api/v1/admin/users/:id/suspend` | Admin | Suspend user |
| PUT | `/api/v1/admin/users/:id/activate` | Admin | Activate user |
| POST | `/api/v1/admin/draw/:level` | Admin | Run draw for level |
| GET | `/api/v1/admin/draw/:level/history` | Admin | Draw history |
| GET | `/api/v1/admin/analytics` | Admin | Analytics |
| GET | `/api/v1/equbs/` | Token | List equbs |
| GET | `/api/v1/equbs/:id` | Token | Single equb |
| POST | `/api/v1/equbs/:id/join` | Token | Join equb |
| GET | `/api/v1/equbs/:id/stats` | Token | Equb stats |
| GET | `/api/v1/equbs/:id/draws` | Token | Equb draws |
| POST | `/api/v1/payments/initiate` | Token | Initiate payment |
| GET | `/api/v1/payments/history` | Token | Payment history |
| POST | `/api/v1/payments/verify` | Admin | Verify payment |
| GET | `/api/v1/users/profile` | Token | Get profile |
| PUT | `/api/v1/users/profile` | Token | Update profile |
| GET | `/api/v1/users/notifications` | Token | Notifications |
| POST | `/api/v1/users/kyc` | Token | Submit KYC |

---

## Running Frontend + Backend Together

**Terminal 1 — Backend:**
```bash
cd /home/abebe/Documents/flutter/online_equb/backend
npm install
npm run dev
```

**Terminal 2 — Flutter:**
```bash
cd /home/abebe/Documents/flutter/online_equb
flutter run -d linux
```

The Flutter app connects to `http://localhost:8080/api/v1`.

---

## Firestore Collections

| Collection | Purpose |
|------------|---------|
| `meta/super_admin_profile` | Super admin credentials |
| `admins/` | Admin accounts per equb level |
| `users/` | Equb members (uniqueId 1:1 enforced) |
| `draws/` | Draw results per level |
| `payments/` | Payment records |
| `notifications/` | User notifications |
| `kyc/` | KYC submissions |
