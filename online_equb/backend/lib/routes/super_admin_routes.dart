import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../firebase_service.dart';
import '../helpers.dart';
import '../models/admin_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Super Admin Routes  —  /api/v1/super-admin/*
//
// GET    /api/v1/super-admin/admins              → list all admins
// GET    /api/v1/super-admin/admins?level=low    → filtered by level
// POST   /api/v1/super-admin/admins              → create admin
// GET    /api/v1/super-admin/admins/:id          → get one admin
// PUT    /api/v1/super-admin/admins/:id          → update admin
// DELETE /api/v1/super-admin/admins/:id          → soft-delete admin
// PUT    /api/v1/super-admin/admins/:id/suspend  → suspend admin
// PUT    /api/v1/super-admin/admins/:id/activate → activate admin
// GET    /api/v1/super-admin/stats               → aggregated stats
// GET    /api/v1/super-admin/profile             → super admin profile
// PUT    /api/v1/super-admin/profile             → update profile
// ─────────────────────────────────────────────────────────────────────────────

Router superAdminRouter() {
  final router = Router();

  // ── GET /admins ───────────────────────────────────────────────────────────
  router.get('/admins', (Request req) async {
    final level = req.url.queryParameters['level'];

    List<Map<String, dynamic>> admins;
    if (level != null && level != 'all') {
      admins = await FirebaseService.queryCollection('admins', 'level', level);
    } else {
      admins = await FirebaseService.getCollection('admins');
    }

    // Exclude deleted
    admins = admins
        .where((a) => (a['status'] ?? 'active') != 'deleted')
        .toList();

    // Sort newest first (by createdAt string — ISO 8601 sorts lexicographically)
    admins.sort((a, b) =>
        (b['createdAt'] ?? '').toString().compareTo(
            (a['createdAt'] ?? '').toString()));

    return jsonResponse(admins);
  });

  // ── POST /admins ──────────────────────────────────────────────────────────
  router.post('/admins', (Request req) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final email    = (body['email'] ?? '').toString().trim().toLowerCase();
    final username = (body['username'] ?? email.split('@').first)
        .toString()
        .trim()
        .toLowerCase();

    if (email.isEmpty) return jsonError('Email is required');

    // Duplicate check
    final byEmail = await FirebaseService.queryCollection('admins', 'email', email);
    final active = byEmail.where((a) => (a['status'] ?? '') != 'deleted').toList();
    if (active.isNotEmpty) return jsonError('Email already registered.', status: 409);

    if (username.isNotEmpty) {
      final byUsername =
          await FirebaseService.queryCollection('admins', 'username', username);
      final activeU =
          byUsername.where((a) => (a['status'] ?? '') != 'deleted').toList();
      if (activeU.isNotEmpty) {
        return jsonError('Username already taken.', status: 409);
      }
    }

    final firstName  = (body['firstName'] ?? '').toString().trim();
    final middleName = (body['middleName'] ?? '').toString().trim();
    final lastName   = (body['lastName'] ?? '').toString().trim();
    final fullName   =
        '$firstName $middleName $lastName'.trim().replaceAll(RegExp(r'\s+'), ' ');
    final level      = (body['level'] ?? 'low').toString();
    final now        = nowIso();

    final data = <String, dynamic>{
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'fullName': fullName,
      'email': email,
      'username': username,
      'password': (body['password'] ?? '').toString(),
      'phone': (body['phone'] ?? '').toString().trim(),
      'address': (body['address'] ?? '').toString().trim(),
      'level': level,
      'role': 'admin',
      'status': 'active',
      'permissions': AdminModel.defaultPermissions(level),
      'contactInfo': body['contactInfo'] ?? {},
      'createdAt': now,
      'updatedAt': now,
    };

    final docId = await FirebaseService.createDocument('admins', data);
    if (docId == null) {
      return jsonError('Failed to create admin. Try again.', status: 500);
    }

    return jsonResponse({'adminId': docId, ...data, 'message': 'Admin assigned successfully.'}, status: 201);
  });

  // ── GET /admins/:id ───────────────────────────────────────────────────────
  router.get('/admins/<id>', (Request req, String id) async {
    final admin = await FirebaseService.getDocument('admins', id);
    if (admin == null) return jsonError('Admin not found.', status: 404);
    return jsonResponse(admin);
  });

  // ── PUT /admins/:id ───────────────────────────────────────────────────────
  router.put('/admins/<id>', (Request req, String id) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final existing = await FirebaseService.getDocument('admins', id);
    if (existing == null) return jsonError('Admin not found.', status: 404);

    final firstName  = (body['firstName']  ?? existing['firstName']  ?? '').toString().trim();
    final middleName = (body['middleName'] ?? existing['middleName'] ?? '').toString().trim();
    final lastName   = (body['lastName']   ?? existing['lastName']   ?? '').toString().trim();
    final fullName   =
        '$firstName $middleName $lastName'.trim().replaceAll(RegExp(r'\s+'), ' ');

    final updates = <String, dynamic>{
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'fullName': fullName,
      'phone':    (body['phone']    ?? existing['phone']    ?? '').toString(),
      'address':  (body['address']  ?? existing['address']  ?? '').toString(),
      'level':    (body['level']    ?? existing['level']    ?? 'low').toString(),
      'updatedAt': nowIso(),
    };

    if (body.containsKey('contactInfo')) updates['contactInfo'] = body['contactInfo'];

    final ok = await FirebaseService.updateDocument('admins', id, updates);
    if (!ok) return jsonError('Failed to update admin.', status: 500);

    final updated = await FirebaseService.getDocument('admins', id);
    return jsonResponse({...?updated, 'message': 'Admin updated successfully.'});
  });

  // ── DELETE /admins/:id → soft delete ─────────────────────────────────────
  router.delete('/admins/<id>', (Request req, String id) async {
    final existing = await FirebaseService.getDocument('admins', id);
    if (existing == null) return jsonError('Admin not found.', status: 404);

    final ok = await FirebaseService.updateDocument('admins', id, {
      'status': 'deleted',
      'deletedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed to delete admin.', status: 500);
    return jsonResponse({'message': 'Admin deleted successfully.'});
  });

  // ── PUT /admins/:id/suspend ───────────────────────────────────────────────
  router.put('/admins/<id>/suspend', (Request req, String id) async {
    final body = await parseBody(req);
    final reason = (body?['reason'] ?? '').toString();

    final ok = await FirebaseService.updateDocument('admins', id, {
      'status': 'suspended',
      'suspensionReason': reason,
      'suspendedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed to suspend admin.', status: 500);
    return jsonResponse({'message': 'Admin suspended.'});
  });

  // ── PUT /admins/:id/activate ──────────────────────────────────────────────
  router.put('/admins/<id>/activate', (Request req, String id) async {
    final ok = await FirebaseService.updateDocument('admins', id, {
      'status': 'active',
      'updatedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed to activate admin.', status: 500);
    return jsonResponse({'message': 'Admin activated.'});
  });

  // ── GET /stats ────────────────────────────────────────────────────────────
  router.get('/stats', (Request req) async {
    final admins = await FirebaseService.getCollection('admins');
    final users  = await FirebaseService.getCollection('users');
    final draws  = await FirebaseService.getCollection('draws');

    int countStatus(List<Map<String, dynamic>> list, String status) =>
        list.where((a) => (a['status'] ?? '') == status).length;

    int countLevel(String level) =>
        admins.where((a) =>
            (a['level'] ?? '') == level &&
            (a['status'] ?? '') != 'deleted').length;

    return jsonResponse({
      'admins': {
        'total': admins.where((a) => (a['status'] ?? '') != 'deleted').length,
        'active': countStatus(admins, 'active'),
        'suspended': countStatus(admins, 'suspended'),
        'low': countLevel('low'),
        'medium': countLevel('medium'),
        'high': countLevel('high'),
      },
      'users': {
        'total': users.where((u) => (u['status'] ?? '') != 'deleted').length,
        'active': countStatus(users, 'active'),
        'suspended': countStatus(users, 'suspended'),
      },
      'draws': {'total': draws.length},
    });
  });

  // ── GET /profile ──────────────────────────────────────────────────────────
  router.get('/profile', (Request req) async {
    final doc =
        await FirebaseService.getDocument('meta', 'super_admin_profile');
    if (doc != null) return jsonResponse(doc);
    return jsonResponse({
      'email': 'superadmin@equb.et',
      'username': 'superadmin',
      'fullName': 'Super Admin',
      'role': 'super_admin',
    });
  });

  // ── PUT /profile ──────────────────────────────────────────────────────────
  router.put('/profile', (Request req) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final updates = <String, dynamic>{...body, 'updatedAt': nowIso()};
    updates.remove('password'); // password change handled separately

    await FirebaseService.setDocument('meta', 'super_admin_profile', updates);
    return jsonResponse({'message': 'Profile updated.', ...updates});
  });

  return router;
}
