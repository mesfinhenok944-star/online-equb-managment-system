import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../firebase_service.dart';
import '../helpers.dart';
import '../models/equb_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin Routes  —  /api/v1/admin/*
//
// GET    /api/v1/admin/dashboard              → stats for all 3 levels
// GET    /api/v1/admin/dashboard/:level       → stats for one level
//
// GET    /api/v1/admin/users                  → all users (all levels)
// GET    /api/v1/admin/users?level=low        → users for a level
// POST   /api/v1/admin/users                  → create user
// GET    /api/v1/admin/users/:id              → get user
// PUT    /api/v1/admin/users/:id              → update user
// DELETE /api/v1/admin/users/:id              → soft delete
// PUT    /api/v1/admin/users/:id/suspend      → suspend
// PUT    /api/v1/admin/users/:id/activate     → activate
//
// POST   /api/v1/admin/dashboard/register     → assign user to level
// DELETE /api/v1/admin/dashboard/remove       → remove participant
//
// POST   /api/v1/admin/draw/:level            → run draw for a level
// GET    /api/v1/admin/draw/:level/history    → draw history for a level
//
// GET    /api/v1/admin/analytics              → analytics summary
// ─────────────────────────────────────────────────────────────────────────────

Router adminRouter() {
  final router = Router();
  final rng = Random();

  // ══════════════════════════════════════════════════════════════════════════
  // DASHBOARD
  // ══════════════════════════════════════════════════════════════════════════

  router.get('/dashboard', (Request req) async {
    final result = <String, dynamic>{};
    for (final level in ['low', 'medium', 'high']) {
      result[level] = await _buildLevelStats(level);
    }
    return jsonResponse(result);
  });

  router.get('/dashboard/<level>', (Request req, String level) async {
    return jsonResponse(await _buildLevelStats(level));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // USER CRUD
  // ══════════════════════════════════════════════════════════════════════════

  // GET /users — list, optional ?level=
  router.get('/users', (Request req) async {
    final level = req.url.queryParameters['level'];
    List<Map<String, dynamic>> users;
    if (level != null && level.isNotEmpty) {
      users = await FirebaseService.queryCollection('users', 'equbLevel', level);
    } else {
      users = await FirebaseService.getCollection('users');
    }
    users = users
        .where((u) => (u['status'] ?? '') != 'deleted')
        .toList();
    users.sort((a, b) => (b['createdAt'] ?? '').toString()
        .compareTo((a['createdAt'] ?? '').toString()));
    return jsonResponse(users);
  });

  // POST /users — create user
  router.post('/users', (Request req) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final email    = (body['email'] ?? '').toString().trim().toLowerCase();
    final uniqueId = (body['uniqueId'] ?? '').toString().trim();

    if (email.isEmpty) return jsonError('Email is required');
    if (uniqueId.isEmpty) return jsonError('Unique ID is required');

    // Email duplicate check
    final byEmail = await FirebaseService.queryCollection('users', 'email', email);
    if (byEmail.any((u) => (u['status'] ?? '') != 'deleted')) {
      return jsonError('Email already registered.', status: 409);
    }

    // Unique ID one-to-one check
    final byUid = await FirebaseService.queryCollection('users', 'uniqueId', uniqueId);
    if (byUid.any((u) => (u['status'] ?? '') != 'deleted')) {
      return jsonError('Unique ID already registered to another user.', status: 409);
    }

    final firstName  = (body['firstName'] ?? '').toString().trim();
    final middleName = (body['middleName'] ?? '').toString().trim();
    final lastName   = (body['lastName'] ?? '').toString().trim();
    final fullName   =
        '$firstName $middleName $lastName'.trim().replaceAll(RegExp(r'\s+'), ' ');
    final now = nowIso();

    final data = <String, dynamic>{
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'fullName': fullName,
      'email': email,
      'phoneNumber': (body['phoneNumber'] ?? '').toString().trim(),
      'uniqueId': uniqueId,
      'equbLevel': (body['equbLevel'] ?? 'low').toString(),
      'adminId': (body['adminId'] ?? '').toString(),
      'role': 'user',
      'status': 'active',
      'hasWon': false,
      'participationHistory': <dynamic>[],
      'balance': 0.0,
      'createdAt': now,
      'updatedAt': now,
    };

    final docId = await FirebaseService.createDocument('users', data);
    if (docId == null) return jsonError('Failed to create user.', status: 500);

    return jsonResponse({
      'userId': docId,
      ...data,
      'message': 'User registered successfully.',
    }, status: 201);
  });

  // GET /users/:id
  router.get('/users/<id>', (Request req, String id) async {
    final user = await FirebaseService.getDocument('users', id);
    if (user == null) return jsonError('User not found.', status: 404);
    return jsonResponse(user);
  });

  // PUT /users/:id
  router.put('/users/<id>', (Request req, String id) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final existing = await FirebaseService.getDocument('users', id);
    if (existing == null) return jsonError('User not found.', status: 404);

    // Unique ID change — re-check uniqueness
    final newUid = (body['uniqueId'] ?? existing['uniqueId'] ?? '').toString().trim();
    final oldUid = (existing['uniqueId'] ?? '').toString().trim();
    if (newUid != oldUid && newUid.isNotEmpty) {
      final taken = await FirebaseService.queryCollection('users', 'uniqueId', newUid);
      if (taken.any((u) => (u['id'] ?? '') != id && (u['status'] ?? '') != 'deleted')) {
        return jsonError('Unique ID already taken.', status: 409);
      }
    }

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
      'phoneNumber': (body['phoneNumber'] ?? existing['phoneNumber'] ?? '').toString(),
      'uniqueId': newUid,
      'updatedAt': nowIso(),
    };
    if (body.containsKey('equbLevel')) updates['equbLevel'] = body['equbLevel'];

    final ok = await FirebaseService.updateDocument('users', id, updates);
    if (!ok) return jsonError('Failed to update user.', status: 500);

    final updated = await FirebaseService.getDocument('users', id);
    return jsonResponse({...?updated, 'message': 'User updated successfully.'});
  });

  // DELETE /users/:id → soft delete
  router.delete('/users/<id>', (Request req, String id) async {
    final ok = await FirebaseService.updateDocument('users', id, {
      'status': 'deleted',
      'deletedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed to delete user.', status: 500);
    return jsonResponse({'message': 'User deleted.'});
  });

  // PUT /users/:id/suspend
  router.put('/users/<id>/suspend', (Request req, String id) async {
    final ok = await FirebaseService.updateDocument('users', id, {
      'status': 'suspended',
      'suspendedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed to suspend user.', status: 500);
    return jsonResponse({'message': 'User suspended.'});
  });

  // PUT /users/:id/activate
  router.put('/users/<id>/activate', (Request req, String id) async {
    final ok = await FirebaseService.updateDocument('users', id, {
      'status': 'active',
      'updatedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed to activate user.', status: 500);
    return jsonResponse({'message': 'User activated.'});
  });

  // PUT /users/:id/verify
  router.put('/users/<id>/verify', (Request req, String id) async {
    final ok = await FirebaseService.updateDocument('users', id, {
      'verificationStatus': 'verified',
      'updatedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed.', status: 500);
    return jsonResponse({'message': 'User verified.'});
  });

  // ══════════════════════════════════════════════════════════════════════════
  // LEVEL ASSIGNMENT
  // ══════════════════════════════════════════════════════════════════════════

  // POST /dashboard/register — assign existing user to a level
  router.post('/dashboard/register', (Request req) async {
    final body = await parseBody(req);
    if (body == null) return jsonError('Invalid JSON body');

    final userId = (body['userId'] ?? '').toString().trim();
    final level  = (body['level'] ?? 'low').toString();

    if (userId.isEmpty) return jsonError('userId required');

    final user = await FirebaseService.getDocument('users', userId);
    if (user == null) return jsonError('User not found.', status: 404);

    if ((user['equbLevel'] ?? '') == level) {
      return jsonError('User already assigned to $level level.', status: 409);
    }

    final ok = await FirebaseService.updateDocument('users', userId, {
      'equbLevel': level,
      'updatedAt': nowIso(),
    });
    if (!ok) return jsonError('Failed to assign user.', status: 500);
    return jsonResponse({'message': 'User registered to $level level.'});
  });

  // DELETE /dashboard/remove — remove participant (soft delete)
  router.delete('/dashboard/remove', (Request req) async {
    final body = await parseBody(req);
    final participantId = (body?['participantId'] ?? '').toString().trim();
    if (participantId.isEmpty) return jsonError('participantId required');

    await FirebaseService.updateDocument('users', participantId, {
      'status': 'deleted',
      'deletedAt': nowIso(),
    });
    return jsonResponse({'message': 'Participant removed.'});
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DRAW ALGORITHM
  // ══════════════════════════════════════════════════════════════════════════

  // POST /draw/:level — run one draw for a level
  router.post('/draw/<level>', (Request req, String level) async {
    // Get eligible participants (active, hasWon==false)
    final allUsers =
        await FirebaseService.queryCollection('users', 'equbLevel', level);
    final eligible = allUsers
        .where((u) =>
            u['hasWon'] != true &&
            (u['status'] ?? 'active') == 'active')
        .toList();

    if (eligible.isEmpty) {
      return jsonError('No eligible participants for $level level.', status: 422);
    }

    // Fair weighted random selection
    final winnerIndex = rng.nextInt(eligible.length);
    final winner      = eligible[winnerIndex];
    final winnerId    = (winner['id'] ?? winner['userId'] ?? '').toString();
    final winnerName  = (winner['fullName'] ?? '').toString();
    final winnerUID   = (winner['uniqueId'] ?? '').toString();

    // Get current draw number
    final history =
        await FirebaseService.queryCollection('draws', 'equbLevel', level);
    final drawNumber = history.length + 1;

    final now = nowIso();
    final drawData = <String, dynamic>{
      'equbLevel': level,
      'winnerId': winnerId,
      'winnerName': winnerName,
      'winnerUniqueId': winnerUID,
      'drawNumber': drawNumber,
      'participants': allUsers
          .map((u) => (u['id'] ?? u['userId'] ?? '').toString())
          .toList(),
      'totalParticipants': allUsers.length,
      'status': 'completed',
      'createdAt': now,
    };

    // Persist draw
    final drawId = await FirebaseService.createDocument('draws', drawData);

    // Mark winner
    if (winnerId.isNotEmpty) {
      await FirebaseService.updateDocument('users', winnerId, {
        'hasWon': true,
        'lastWinDate': now,
        'updatedAt': now,
      });
    }

    return jsonResponse({
      'drawId': drawId ?? '',
      'drawNumber': drawNumber,
      'winnerId': winnerId,
      'winnerName': winnerName,
      'winnerUniqueId': winnerUID,
      'level': level,
      'eligibleRemaining': eligible.length - 1,
      'message': 'Draw completed successfully.',
    });
  });

  // GET /draw/:level/history
  router.get('/draw/<level>/history', (Request req, String level) async {
    final draws =
        await FirebaseService.queryCollection('draws', 'equbLevel', level);
    draws.sort((a, b) => (b['drawNumber'] as int? ?? 0)
        .compareTo(a['drawNumber'] as int? ?? 0));
    return jsonResponse(draws);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ANALYTICS
  // ══════════════════════════════════════════════════════════════════════════

  router.get('/analytics', (Request req) async {
    final users  = await FirebaseService.getCollection('users');
    final draws  = await FirebaseService.getCollection('draws');
    final payments = await FirebaseService.getCollection('payments');

    double totalCollected = 0;
    for (final p in payments) {
      if ((p['status'] ?? '') == 'completed') {
        totalCollected += (p['amount'] as num?)?.toDouble() ?? 0;
      }
    }

    return jsonResponse({
      'totalUsers': users.where((u) => (u['status'] ?? '') != 'deleted').length,
      'totalDraws': draws.length,
      'totalPayments': payments.length,
      'totalCollected': totalCollected,
      'byLevel': {
        for (final level in ['low', 'medium', 'high'])
          level: {
            'users': users.where((u) =>
                u['equbLevel'] == level &&
                (u['status'] ?? '') != 'deleted').length,
            'draws': draws.where((d) => d['equbLevel'] == level).length,
          }
      },
    });
  });

  return router;
}

// ── helper ─────────────────────────────────────────────────────────────────
Future<Map<String, dynamic>> _buildLevelStats(String level) async {
  final users = await FirebaseService.queryCollection('users', 'equbLevel', level);
  final active    = users.where((u) => (u['status'] ?? 'active') == 'active').toList();
  final winners   = users.where((u) => u['hasWon'] == true).toList();
  final eligible  = active.where((u) => u['hasWon'] != true).toList();
  final draws     = await FirebaseService.queryCollection('draws', 'equbLevel', level);

  final defaults = EqubModel.defaultForLevel(level);

  return {
    'equbId': 'equb_$level',
    'level': level,
    'price': defaults.price,
    'netPrize': defaults.netPrize,
    'adminFee': defaults.adminFee,
    'maxParticipants': defaults.maxParticipants,
    'currentParticipants': active.length,
    'eligibleCount': eligible.length,
    'drawsHeld': draws.length,
    'totalCollected': active.length * defaults.price,
    'status': 'active',
    'participants': active
        .where((u) => (u['status'] ?? '') != 'deleted')
        .map((u) => {
              'participantId': u['id'] ?? u['userId'] ?? '',
              'userId': u['id'] ?? u['userId'] ?? '',
              'fullName': u['fullName'] ?? '',
              'phoneNumber': u['phoneNumber'] ?? '',
              'uniqueId': u['uniqueId'] ?? '',
              'email': u['email'] ?? '',
              'hasWon': u['hasWon'] ?? false,
              'status': u['status'] ?? 'active',
            })
        .toList(),
    'draws': draws
        .map((d) => {
              'drawId': d['id'] ?? '',
              'drawNumber': d['drawNumber'] ?? 0,
              'winnerName': d['winnerName'] ?? '',
              'winnerUniqueId': d['winnerUniqueId'] ?? '',
              'createdAt': d['createdAt'] ?? '',
            })
        .toList(),
  };
}
