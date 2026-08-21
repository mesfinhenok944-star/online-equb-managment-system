# Online Equb Application - Complete Implementation Guide

## 🎯 Project Overview
A comprehensive Flutter + Node.js Equb (Rotating Savings) management system with:
- **Three Equb Levels**: Low, Medium, High (with different prices & returns)
- **Multi-tier Users**: Super Admin, Admin (per level), Regular Users
- **Fair Draw Algorithm**: Weighted selection ensuring no repeated winners
- **Bilingual Interface**: English & Amharic
- **Real-time Management**: Add/Edit/Delete/Search users
- **Draw History & Reports**: Track all draws and winners

---

## 🏗️ Architecture

### Backend (Node.js/Express)
```
backend/src/
├── server.js                 # Main entry point
├── config/
│   └── firebase.js          # Firebase Admin SDK config
├── middleware/
│   ├── auth.js              # JWT/Token verification
│   └── cors.js              # CORS configuration
├── routes/
│   ├── auth.js              # Login/Auth endpoints
│   ├── superAdmin.js        # Super Admin endpoints
│   ├── admin.js             # Admin endpoints
│   ├── users.js             # User management
│   ├── equbs.js             # Equb draw & history
│   └── payments.js          # Payment tracking
└── controllers/             # (Business logic - optional)
```

### Frontend (Flutter/Dart)
```
lib/
├── main.dart                # App entry point
├── config/
│   ├── router.dart          # Navigation/routing
│   └── theme.dart           # Theme configuration
├── models/
│   ├── user.dart           # User model
│   ├── admin.dart          # Admin model
│   └── equb_draw.dart      # Draw model
├── providers/
│   └── auth_provider.dart  # Auth state management
├── services/
│   └── api_service.dart    # HTTP client
├── screens/
│   ├── auth/
│   │   └── login_screen.dart
│   ├── home/
│   │   └── home_screen.dart
│   ├── admin/
│   │   ├── dashboard.dart
│   │   └── user_registration_form.dart
│   └── super_admin/
│       ├── dashboard.dart
│       └── admin_registration_form.dart
├── widgets/
│   ├── level_card.dart
│   ├── user_card.dart
│   └── equb_draw_wheel.dart
└── utils/
    └── constants.dart
```

---

## 📱 Key Features

### 1. **Super Admin Dashboard**
- ✅ Manage all admins across all levels
- ✅ Assign admins with form (First Name, Last Name, Email, Username, Password, Level)
- ✅ View/Edit/Delete/Suspend/Activate admins
- ✅ Search and filter admins by level and status
- ✅ Dashboard stats (Total, Active, Suspended)

### 2. **Admin Dashboard (Per Level)**
- ✅ Manage users for assigned level
- ✅ Register users (First, Last, Email, Phone, National ID)
- ✅ One-to-one mapping (unique National ID)
- ✅ Full CRUD operations
- ✅ Search and filter users
- ✅ Run equb draw algorithm
- ✅ View draw history

### 3. **Equb Draw Algorithm**
- ✅ Weighted fair selection
- ✅ No repeated winners until all have won
- ✅ Spin wheel animation
- ✅ Winner notification
- ✅ Draw history with dates
- ✅ Support for all three levels

### 4. **User Features**
- Profile view
- View equb level participation
- Check draw history
- Winner status

### 5. **Bilingual Support**
- English & Amharic
- Language toggle in UI
- Localized strings and date formats

---

## 🔑 Default Credentials

### Super Admin
- Email: `superadmin@equb.et`
- Password: `admin123`

### Admin Accounts
- Low Level: `admin.low@equb.et` / `admin123`
- Medium Level: `admin.med@equb.et` / `admin123`
- High Level: `admin.high@equb.et` / `admin123`

---

## 💾 Firebase Firestore Collections

### 1. `meta/super_admin_profile`
```json
{
  "email": "superadmin@equb.et",
  "username": "superadmin",
  "password": "admin123",
  "fullName": "Super Admin",
  "role": "super_admin"
}
```

### 2. `admins` Collection
```json
{
  "firstName": "John",
  "lastName": "Doe",
  "middleName": "Michael",
  "email": "admin.low@equb.et",
  "username": "admin_low",
  "password": "admin123",
  "phone": "+251911223344",
  "address": "Addis Ababa",
  "level": "low",
  "role": "admin",
  "status": "active",
  "permissions": [...],
  "createdAt": "2024-08-17T10:30:00Z",
  "updatedAt": "2024-08-17T10:30:00Z"
}
```

### 3. `users` Collection
```json
{
  "firstName": "Jane",
  "lastName": "Smith",
  "middleName": "Grace",
  "email": "jane.smith@example.com",
  "phoneNumber": "+251912345678",
  "nationalId": "ETH123456789",
  "level": "low",
  "adminId": "admin_doc_id",
  "status": "active",
  "hasWon": false,
  "balance": 500.00,
  "participationHistory": [],
  "createdAt": "2024-08-17T10:30:00Z",
  "updatedAt": "2024-08-17T10:30:00Z"
}
```

### 4. `draws` Collection
```json
{
  "level": "low",
  "adminId": "admin_doc_id",
  "winnerId": "user_doc_id",
  "winnerName": "Jane Smith",
  "winnerNationalId": "ETH123456789",
  "totalParticipants": 50,
  "participants": ["user_id_1", "user_id_2", ...],
  "drawNumber": 1,
  "createdAt": "2024-08-17T14:30:00Z"
}
```

### 5. `notifications` Collection
```json
{
  "userId": "user_doc_id",
  "type": "winner",
  "title": "🎉 Congratulations!",
  "message": "You won the Low Level draw!",
  "isRead": false,
  "createdAt": "2024-08-17T14:30:00Z"
}
```

---

## 🚀 Getting Started

### Backend Setup
```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your Firebase credentials
npm run dev
```

### Frontend Setup
```bash
cd ..
flutter pub get
flutter run
```

### Firebase Setup
1. Create Firebase project at https://console.firebase.google.com
2. Enable Firestore Database
3. Download service account key JSON
4. Place in `backend/serviceAccountKey.json`
5. Update `.env` with Firebase credentials

---

## 🔌 API Endpoints

### Authentication
- `POST /api/v1/auth/login` - Login (email/username + password)

### Super Admin
- `GET /api/v1/super-admin/admins` - List all admins
- `POST /api/v1/super-admin/admins` - Assign new admin
- `GET /api/v1/super-admin/admins/:id` - Get admin details
- 
- `PUT /api/v1/super-admin/admins/:id` - Update admin
- `DELETE /api/v1/super-admin/admins/:id` - Delete admin
- `PATCH /api/v1/super-admin/admins/:id/suspend` - Suspend admin
- `PATCH /api/v1/super-admin/admins/:id/activate` - Activate admin

### Admin
- `GET /api/v1/admin/users` - List users (filtered by admin's level)
- `POST /api/v1/admin/users/register` - Register new user
- `GET /api/v1/admin/users/:id` - Get user details
- `PUT /api/v1/admin/users/:id` - Update user
- `DELETE /api/v1/admin/users/:id` - Delete user
- `GET /api/v1/admin/users/search` - Search users

### Equb Draw
- `POST /api/v1/equbs/draw` - Run draw for level
- `GET /api/v1/equbs/:level/draws` - Get draw history
- `GET /api/v1/equbs/:level/winners` - Get winners list

---

## ⚙️ Environment Variables (.env)

```env
# Server
PORT=8080
NODE_ENV=production

# Firebase
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_CLIENT_EMAIL=your_email@appspot.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"

# Super Admin
SUPER_ADMIN_EMAIL=superadmin@equb.et
SUPER_ADMIN_USERNAME=superadmin
SUPER_ADMIN_PASSWORD=admin123

# JWT (if using)
JWT_SECRET=your_jwt_secret_key
JWT_EXPIRES_IN=7d
```

---

## 🎨 Equb Levels Configuration

### Low Level
- Price: 100 ETB
- Participants: 50+
- Returns: Standard
- Color: Blue

### Medium Level
- Price: 500 ETB
- Participants: 100+
- Returns: Better
- Color: Orange

### High Level
- Price: 1000 ETB
- Participants: 150+
- Returns: Best
- Color: Green

---

## 🔄 Draw Algorithm

### Fair Weighted Selection
```
1. Get all active users who haven't won yet
2. Calculate weight for each user:
   - Base weight: 1.0
   - Participation bonus: +0.1 per previous draw entry
   - Random factor: +random(0, 0.5)
3. Sort by weight (descending)
4. Perform weighted random selection
5. Mark winner, update history, notify
```

---

## 📊 User Roles & Permissions

### Super Admin
- ✅ Manage all admins
- ✅ Assign admins to levels
- ✅ View system analytics
- ✅ Change super admin credentials
- ✅ Suspend/Activate admins

### Admin (Per Level)
- ✅ Manage users for their level
- ✅ Run equb draws
- ✅ View draw history
- ✅ Add/Edit/Delete users
- ✅ Search users
- ✅ Export reports (High level only)

### User
- ✅ View profile
- ✅ Check participation status
- ✅ View draw history
- ✅ Receive notifications

---

## 🎯 Next Steps

1. **Complete Backend Implementation**
   - Implement JWT authentication
   - Add password hashing (bcryptjs)
   - Add request validation
   - Add error handling middleware

2. **Complete Frontend Implementation**
   - Create equb draw wheel animation
   - Implement winner notification
   - Add user registration form
   - Add admin assignment form
   - Create draw history screen

3. **Testing**
   - Unit tests for draw algorithm
   - API integration tests
   - UI widget tests

4. **Deployment**
   - Deploy backend to Heroku/AWS/Firebase
   - Deploy frontend to App Stores
   - Setup monitoring and logging

---

## 📞 Support
For issues or questions, contact the development team.

**Last Updated**: August 17, 2024
**Version**: 1.0.0
**Status**: In Development
