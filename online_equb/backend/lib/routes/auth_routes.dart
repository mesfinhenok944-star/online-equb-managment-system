import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../firebase_service.dart';
import '../config.dart';
import '../helpers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Auth Routes  —  /api/v1/auth/*
// POST /api/v1/auth/login    → super-admin | admin | user login
// POST /api/v1/auth/register → register a new regular user
// ─────────────────────────────────────────────────────────────────────────────

Router authRouter() {
  final router = Router();

  // ── POST /api/v1/auth/login ──────────────────────────────────────────────
  router.post('/login', (Request req) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final input = (body['email'] ?? body['username'] ?? '').toString().trim().toLowerCase();
    final password = (body['password'] ?? '').toString();

    if (input.isEmpty || password.isEmpty) {
      return jsonError('Email/username and password are required');
    }

    // ── 1. Super admin check ────────────────────────────────────────────────
    final superProfile = await _getSuperAdminProfile();
    final superEmail    = (superProfile['email'] ?? '').toString().toLowerCase();
    final superUsername = (superProfile['username'] ?? '').toString().toLowerCase();
    final superPassword = (superProfile['password'] ?? '').toString();

    if ((input == superEmail || input == superUsername) && password == superPassword) {
      return jsonResponse({
        'token': 'super_admin_token',
        'user': {
          ...superProfile,
          'role': 'super_admin',
        },
      });
    }

    // ── 2. Admin check (admins collection) ──────────────────────────────────
    List<Map<String, dynamic>> adminDocs = [];
    // try email first
    adminDocs = await FirebaseService.queryCollection('admins', 'email', input);
    if (adminDocs.isEmpty) {
      adminDocs = await FirebaseService.queryCollection('admins', 'username', input);
    }

    if (adminDocs.isNotEmpty) {
      final admin = adminDocs.first;
      final storedPwd = (admin['password'] ?? '').toString();
      final status    = (admin['status'] ?? 'active').toString();

      if (status == 'suspended') {
        return jsonError('Account suspended. Contact super admin.', status: 403);
      }
      if (status == 'deleted') {
        return jsonError('Account not found.', status: 404);
      }

      if (storedPwd == password) {
        // Update lastLogin
        await FirebaseService.updateDocument(
          'admins', admin['id'] as String, {'lastLogin': nowIso()});

        return jsonResponse({
          'token': 'admin_token_${admin['id']}',
          'user': {
            ...admin,
            'role': 'admin',
          },
        });
      }
      return jsonError('Invalid password.', status: 401);
    }

    // ── 3. Regular user — Firebase Auth ─────────────────────────────────────
    final authResult = await FirebaseService.signInWithPassword(input, password);
    if (authResult != null) {
      final uid = authResult['localId'] as String? ?? '';
      final idToken = authResult['idToken'] as String? ?? '';

      // Fetch user profile from Firestore
      final userDoc = await FirebaseService.getDocument('users', uid);
      final profile = userDoc ?? {'uid': uid, 'email': input, 'role': 'user'};

      return jsonResponse({'token': idToken, 'user': profile});
    }

    return jsonError('Invalid credentials.', status: 401);
  });

  // ── POST /api/v1/auth/register ───────────────────────────────────────────
  router.post('/register', (Request req) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final email    = (body['email'] ?? '').toString().trim().toLowerCase();
    final password = (body['password'] ?? '').toString();
    final firstName = (body['firstName'] ?? '').toString().trim();
    final lastName  = (body['lastName'] ?? '').toString().trim();
    final phone     = (body['phoneNumber'] ?? body['phone'] ?? '').toString().trim();
    final fullName  = (body['fullName'] ?? '$firstName $lastName').toString().trim();

    if (email.isEmpty || password.isEmpty) {
      return jsonError('Email and password are required');
    }

    // Check duplicate in users collection
    final existing = await FirebaseService.queryCollection('users', 'email', email);
    if (existing.isNotEmpty) {
      return jsonError('Email already registered.', status: 409);
    }

    // Create Firebase Auth user
    final authResult = await FirebaseService.createAuthUser(email, password);
    final uid = authResult?['localId'] as String? ?? generateId('usr');

    final now = nowIso();
    final profile = <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'email': email,
      'phoneNumber': phone,
      'role': 'user',
      'status': 'active',
      'verificationStatus': 'unverified',
      'hasWon': false,
      'balance': 0.0,
      'createdAt': now,
      'updatedAt': now,
    };

    // Save to Firestore users/<uid>
    await FirebaseService.setDocument('users', uid, profile);

    return jsonResponse(
      {
        'userId': uid,
        'id': uid,
        ...profile,
        'message': 'User registered successfully',
      },
      status: 201,
    );
  });

  return router;
}

// ── helpers ────────────────────────────────────────────────────────────────
Future<Map<String, dynamic>> _getSuperAdminProfile() async {
  // Try Firestore meta/super_admin_profile first
  final doc = await FirebaseService.getDocument('meta', 'super_admin_profile');
  if (doc != null && doc.isNotEmpty) return doc;

  // Fallback to env defaults
  return {
    'firstName': 'Super',
    'lastName': 'Admin',
    'fullName': 'Super Admin',
    'email': Config.superAdminEmail,
    'username': Config.superAdminUsername,
    'password': Config.superAdminPassword,
    'role': 'super_admin',
  };
}
