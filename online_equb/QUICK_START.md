# Online Equb Application - Quick Start Guide

## 🚀 Installation & Setup

### Prerequisites
- Flutter SDK (3.0+)
- Node.js (18+)
- Firebase Project
- Git

### Step 1: Clone/Setup Project
```bash
# Navigate to project directory
cd online_equb

# Install Flutter dependencies
flutter pub get

# Install backend dependencies  
cd backend
npm install
cd ..
```

### Step 2: Firebase Configuration

1. **Create Firebase Project**
   - Go to https://console.firebase.google.com
   - Create new project (name: "online-equb")
   - Enable Firestore Database
   - Enable Firebase Authentication

2. **Download Service Account Key**
   - Go to Project Settings → Service Accounts
   - Click "Generate New Private Key"
   - Save as `backend/serviceAccountKey.json`

3. **Create .env File**
```bash
cd backend
cp .env.example .env
# Edit .env with your Firebase credentials
```

### Step 3: Initialize Firestore

Create the initial super admin profile in Firestore:

**Firestore Collection: `meta`**
**Document: `super_admin_profile`**
```json
{
  "email": "superadmin@equb.et",
  "username": "superadmin",
  "password": "admin123",
  "fullName": "Super Admin",
  "role": "super_admin"
}
```

**Initial Admins Collection**
```json
// Document in 'admins' collection
{
  "firstName": "Admin",
  "lastName": "Low",
  "email": "admin.low@equb.et",
  "username": "admin_low",
  "password": "admin123",
  "level": "low",
  "role": "admin",
  "status": "active",
  "phone": "+251911223344",
  "createdAt": "2024-08-17T10:00:00Z",
  "updatedAt": "2024-08-17T10:00:00Z",
  "permissions": {...}
}
```

---

## 🏃 Running the Application

### Backend Server
```bash
cd backend

# Development mode (with auto-reload)
npm run dev

# Production mode
npm start

# Should see:
# ✓ Express server running on http://localhost:8080
# ✓ Firebase connected
```

### Frontend Flutter App
```bash
# In root directory
flutter run

# For specific device:
flutter run -d <device_id>

# For web:
flutter run -d chrome
```

---

## 🧪 Testing the Application

### Super Admin Login
1. **Launch app** → Go to Login Screen
2. **Switch to Demo Credentials**
3. **Enter:**
   - Email: `superadmin@equb.et`
   - Password: `admin123`
4. **Click Sign In**
5. **You'll see:**
   - Super Admin Dashboard
   - List of all admins
   - Option to assign new admins
   - Ability to suspend/activate admins

### Admin Login (Low Level)
1. **Go back to Login**
2. **Switch language to English**
3. **Enter:**
   - Email: `admin.low@equb.et`
   - Password: `admin123`
4. **Click Sign In**
5. **You'll see:**
   - Admin Dashboard for Low Level
   - User management interface
   - Register new users button
   - Equb draw section

### Test Admin Functions
1. **Register a User:**
   - Click "Add User" button
   - Fill form: First Name, Last Name, Email, Phone, National ID
   - Click "Register"
   - Should see success message

2. **Search Users:**
   - Type in search field
   - Results filter in real-time

3. **Edit User:**
   - Click on user card
   - Select "Edit"
   - Update fields
   - Click "Save"

4. **Delete User:**
   - Click on user card
   - Select "Delete"
   - Confirm deletion

5. **Run Equb Draw:**
   - Users must be active (status = 'active')
   - Click "Run Draw"
   - Spin wheel animation
   - Winner selected
   - Notification created

### Test Equb Draw
1. **Register at least 3 users** with different National IDs
2. **Click "Run Draw" button**
3. **Expected flow:**
   - Loading spinner
   - Wheel animation starts
   - Random selection (fair algorithm)
   - Winner announcement
   - Notification created
   - User marked as `hasWon: true`
4. **Run draw again** → Different user should win
5. **Check Draw History** → List of all past draws

---

## 📱 User Interface Walkthrough

### Login Screen
- Email/Username field
- Password field
- Remember Me checkbox
- Language selector (EN/ዓ)
- Demo credentials hint

### Super Admin Dashboard
- Header with greeting
- Navigation menu
- Admin list with cards
  - Name, Email, Level, Status
  - Action buttons (Edit, Suspend, Delete)
- Filter by level and status
- Search admins
- Assign new admin button

### Admin Dashboard
- Header with level indicator
- Sidebar menu
  - Dashboard
  - Users
  - Equb Draw
  - Payments
  - Analytics
  - Settings
- User management section
  - Add user button
  - User list/cards
  - Search and filter
- Equb draw section
  - Run draw button
  - Draw history
  - Winners list

### User Registration Form
- First Name*
- Last Name*
- Middle Name (optional)
- Email*
- Phone Number*
- National ID* (unique)
- Submit button

### Admin Assignment Form
- First Name*
- Last Name*
- Middle Name (optional)
- Email* (unique)
- Username* (unique)
- Password*
- Phone Number
- Level* (low/medium/high)
- Address (optional)
- Submit button

---

## 🔑 API Testing with Curl/Postman

### Login
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "superadmin@equb.et",
    "password": "admin123"
  }'
```

### Get All Admins (Super Admin)
```bash
curl -X GET "http://localhost:8080/api/v1/super-admin/admins?level=all&status=active" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Assign New Admin (Super Admin)
```bash
curl -X POST http://localhost:8080/api/v1/super-admin/admins \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "firstName": "John",
    "lastName": "Doe",
    "email": "john.doe@equb.et",
    "username": "johndoe",
    "password": "secure123",
    "level": "medium",
    "phone": "+251922334455"
  }'
```

### Register User (Admin)
```bash
curl -X POST http://localhost:8080/api/v1/admin/users/register \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "firstName": "Jane",
    "lastName": "Smith",
    "email": "jane.smith@example.com",
    "phoneNumber": "+251913456789",
    "nationalId": "ETH123456789"
  }'
```

### Run Equb Draw (Admin)
```bash
curl -X POST http://localhost:8080/api/v1/equbs/draw \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{}' 
```

### Get Draw History (Admin)
```bash
curl -X GET "http://localhost:8080/api/v1/equbs/draws?limit=10" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## 🐛 Common Issues & Solutions

### Issue: Firebase Connection Error
**Solution:**
- Check `backend/.env` file has correct credentials
- Verify `serviceAccountKey.json` exists and is valid
- Check Firebase project is active

### Issue: Users/Admins not appearing
**Solution:**
- Verify users are in correct Firestore collection
- Check `status !== 'deleted'`
- Clear app cache: `flutter clean`

### Issue: Draw fails to run
**Solution:**
- Ensure at least 1 user is registered
- Check user status is 'active'
- Check user `hasWon = false`
- Look at server logs for errors

### Issue: One-to-one National ID mapping not working
**Solution:**
- Ensure new National ID is unique
- Check for typos in existing IDs
- Query Firestore directly to verify

### Issue: Login not working
**Solution:**
- Clear app storage: `SharedPreferences.getInstance().clear()`
- Verify credentials in Firestore
- Check email/username is lowercase
- Review auth middleware logs

---

## 📊 Database Schema Quick Reference

### Collections
```
meta/
  super_admin_profile  → Super admin credentials

admins/
  {adminId}           → Admin for each level

users/
  {userId}            → Users per level

draws/
  {drawId}            → Draw history

notifications/
  {notifId}           → User notifications
```

### User States
- `status`: active | suspended | deleted
- `hasWon`: true | false (marks if user won any draw)
- `level`: low | medium | high
- `nationalId`: unique identifier

### Admin States  
- `status`: active | suspended | deleted
- `level`: low | medium | high (assigned level)
- `role`: admin | super_admin

---

## 🎯 Features Checklist

### Super Admin
- ✅ Login with email/password
- ✅ View all admins
- ✅ Assign new admin (form with validation)
- ✅ Edit admin details
- ✅ Suspend/Activate admin
- ✅ Delete admin
- ✅ Search admins
- ✅ Filter by level and status

### Admin
- ✅ Login with email/password
- ✅ View users (filtered by level)
- ✅ Register user (one-to-one National ID)
- ✅ Edit user
- ✅ Delete user
- ✅ Suspend/Activate user
- ✅ Search users
- ✅ Run equb draw
- ✅ View draw history
- ✅ View winners list

### General
- ✅ Bilingual (English & Amharic)
- ✅ Language toggle
- ✅ Responsive design
- ✅ Demo credentials
- ✅ Error handling
- ✅ Loading states
- ✅ Notifications

---

## 📞 Support & Documentation

- **Implementation Guide**: See `IMPLEMENTATION_GUIDE.md`
- **API Documentation**: See backend routes
- **Firebase Setup**: https://firebase.google.com/docs
- **Flutter Docs**: https://flutter.dev/docs

---

**Version**: 1.0.0
**Last Updated**: August 17, 2024
**Status**: Ready for Testing
