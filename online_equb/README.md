# 🏦 Online Equb - Complete Equb Management System

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)](https://flutter.dev/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green.svg)](https://nodejs.org/)
[![Firebase](https://img.shields.io/badge/Firebase-Latest-orange.svg)](https://firebase.google.com/)
[![License](https://img.shields.io/badge/License-MIT-red.svg)](#)

A modern, full-stack Equb (Ethiopian Rotating Savings) management application built with Flutter and Node.js/Express. Features bilingual support (English & Amharic), fair draw algorithm, multi-level equb management, and comprehensive admin dashboards.

## ✨ Features

### 🔐 Authentication & Roles
- **Super Admin**: Manage all system admins and settings
- **Admin (Per Level)**: Manage users and run draws for assigned level
- **User**: Participate in equbs and track draw history
- Secure login with email/username and password
- Demo credentials for testing

### 💰 Three Equb Levels
| Level | Price | Participants | Returns | Color |
|-------|-------|-------------|---------|-------|
| Low | 100 ETB | 50+ | Standard | 🔵 Blue |
| Medium | 500 ETB | 100+ | Better | 🟠 Orange |
| High | 1000 ETB | 150+ | Best | 🟢 Green |

### 🎰 Equb Draw System
- **Fair Algorithm**: Weighted random selection ensuring fairness
- **No Repeats**: User marked as winner until full cycle completes
- **Draw Wheel**: Animated spin wheel visualization
- **History**: Complete draw history with dates and winners
- **Notifications**: Winners notified immediately

### 👥 User Management
- One-to-one National ID mapping (no duplicates)
- Full CRUD operations (Create, Read, Update, Delete)
- User status: active, suspended, deleted
- Real-time search and filtering
- User participation history

### 🌍 Bilingual Interface
- **English** - Professional interface
- **Amharic (ዓማርኛ)** - Complete UI translation
- Language toggle button
- Localized strings and formats

### 📊 Admin Dashboards
- **Super Admin**: Assign admins, manage permissions, view system stats
- **Admin**: Manage users, run draws, view reports
- Real-time statistics and charts
- Export capabilities (planned)

---

## 🏗️ Project Structure

```
online_equb/
├── 📁 lib/
│   ├── main.dart              # App entry point
│   ├── models/                # Data models
│   ├── screens/               # UI screens
│   ├── widgets/               # Reusable widgets
│   ├── services/              # API & Firebase
│   ├── providers/             # State management
│   └── utils/                 # Constants & helpers
│
├── 📁 backend/
│   ├── src/
│   │   ├── server.js          # Express server
│   │   ├── config/            # Firebase setup
│   │   ├── routes/            # API endpoints
│   │   └── middleware/        # Auth, CORS, etc.
│   ├── .env                   # Environment config
│   ├── package.json           # Node dependencies
│   └── serviceAccountKey.json # Firebase credentials
│
├── IMPLEMENTATION_GUIDE.md    # Technical architecture
├── QUICK_START.md             # Setup & testing guide
└── README.md                  # This file
```

---

## 🚀 Quick Start

### Prerequisites
- Flutter SDK 3.0+
- Node.js 18+
- Firebase Project
- Git

### 1️⃣ Setup Firebase
```bash
# Create Firebase project at https://console.firebase.google.com
# Download service account key
# Place in: backend/serviceAccountKey.json
```

### 2️⃣ Setup Backend
```bash
cd backend
npm install
cp .env.example .env
# Edit .env with Firebase credentials
npm run dev
# Server starts on http://localhost:8080
```

### 3️⃣ Setup Frontend
```bash
cd ..
flutter pub get
flutter run
```

### 4️⃣ Login with Demo Credentials
- **Super Admin**: `superadmin@equb.et` / `admin123`
- **Admin**: `admin.low@equb.et` / `admin123`

---

## 📚 Documentation

- **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** - Technical architecture
- **[QUICK_START.md](QUICK_START.md)** - Setup and testing

---

**Version:** 1.0.0  
**Last Updated:** August 17, 2024  
**Status:** Beta - Ready for Testing

Made with ❤️ for the Ethiopian community
