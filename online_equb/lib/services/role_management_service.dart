import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Full role management service.
/// - Super admin is stored in meta/super_admin_profile
/// - Admins are stored in admins/ collection (NOT users/)
/// - Users (equb members) are stored in users/ collection
class RoleManagementService {
  static const String _superProfileKey = 'super_admin_profile';

  static FirebaseFirestore? get _maybeDb {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Non-nullable accessor that throws when Firestore is unavailable.
  static FirebaseFirestore get _db {
    final db = _maybeDb;
    if (db == null) throw StateError('Firestore is unavailable on this platform');
    return db;
  }

  // ──────────────────────────────── SUPER ADMIN ────────────────────────────

  static Map<String, dynamic> defaultSuperAdminProfile() => {
        'firstName': 'Super',
        'middleName': '',
        'lastName': 'Admin',
        'fullName': 'Super Admin',
        'username': 'superadmin',
        'email': 'abebe@gmail.com',
        'password': 'abebe1212',
        'phone': '+251900000000',
        'address': 'Addis Ababa, Ethiopia',
        'role': 'super_admin',
      };

  static Future<Map<String, dynamic>> getSuperAdminProfile() async {
    try {
      final db = _maybeDb;
      if (db != null) {
        final doc = await db.collection('meta').doc('super_admin_profile').get();
        if (doc.exists && doc.data() != null) {
          return Map<String, dynamic>.from(doc.data()!);
        }
      }
    } catch (_) {}

    try {
      final res = await ApiService.superAdminGetStats();
      if (res.isNotEmpty) {
        return defaultSuperAdminProfile();
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_superProfileKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return {...defaultSuperAdminProfile(), ...decoded};
        }
      } catch (_) {}
    }

    final profile = defaultSuperAdminProfile();
    await prefs.setString(_superProfileKey, jsonEncode(profile));
    return profile;
  }

  static Future<void> saveSuperAdminProfile(
      Map<String, dynamic> profile) async {
    try {
      await _db
          .collection('meta')
          .doc('super_admin_profile')
          .set(profile, SetOptions(merge: true));
      return;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final merged = {...defaultSuperAdminProfile(), ...profile};
    merged['fullName'] =
        '${merged['firstName'] ?? ''} ${merged['middleName'] ?? ''} ${merged['lastName'] ?? ''}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    merged['role'] = 'super_admin';
    await prefs.setString(_superProfileKey, jsonEncode(merged));
  }

  // ──────────────────────────────── ADMINS ─────────────────────────────────

  /// Fetch all non-deleted admins, optionally filtered by level.
  /// Fetch all non-deleted admins, optionally filtered by level.
  static Future<List<Map<String, dynamic>>> getAdmins(
      {String? level}) async {
    try {
      final snap = await _db.collection('admins').get();
      var docs = snap.docs
          .where((d) => (d.data()['status'] ?? 'active') != 'deleted');
      if (level != null && level != 'all') {
        docs = docs.where((d) => (d.data()['level'] ?? 'low') == level);
      }
      return docs
          .map((d) => <String, dynamic>{...d.data(), 'adminId': d.id, 'id': d.id})
          .toList();
    } catch (e) {
      debugPrint('[getAdmins error] $e');
      final list = await ApiService.superAdminGetAdmins(level: level);
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
  }

  /// Alias used by legacy callers.
  static Future<List<Map<String, dynamic>>> getAssignedAdmins(
      {String? level}) =>
      getAdmins(level: level);

  /// Get a single admin by doc id.
  static Future<Map<String, dynamic>?> getAdminById(String adminId) async {
    try {
      final doc = await _db.collection('admins').doc(adminId).get();
      if (!doc.exists) return null;
      return <String, dynamic>{...doc.data()!, 'adminId': doc.id, 'id': doc.id};
    } catch (_) {
      final res = await ApiService.superAdminGetAdmin(adminId);
      if (res.containsKey('error')) return null;
      return res;
    }
  }

  /// Create a new admin document (max 3 admins allowed per level).
  /// If admin email already exists, updates & re-assigns admin to the specified level.
  static Future<Map<String, dynamic>> createAdminResult(Map<String, dynamic> admin) async {
    final email = (admin['email'] ?? '').toString().trim().toLowerCase();
    final username = (admin['username'] ?? '').toString().trim().toLowerCase();
    final level = (admin['level'] ?? 'low').toString();
    if (email.isEmpty) {
      return {'success': false, 'error': 'Email address is required.'};
    }

    // 1. Try Backend REST API first
    try {
      final apiRes = await ApiService.superAdminCreateAdmin(admin);
      if (!apiRes.containsKey('error') && (apiRes['adminId'] != null || apiRes['id'] != null)) {
        final id = (apiRes['adminId'] ?? apiRes['id']).toString();
        return {'success': true, 'id': id, 'message': apiRes['message'] ?? 'Admin assigned successfully.'};
      }
      if (apiRes.containsKey('error') && !apiRes['error'].toString().contains('Cannot reach server')) {
        return {'success': false, 'error': apiRes['error'].toString()};
      }
    } catch (_) {}

    // 2. Firestore fallback
    try {
      final db = _maybeDb;
      if (db != null) {
        final firstName = (admin['firstName'] ?? '').toString().trim();
        final middleName = (admin['middleName'] ?? '').toString().trim();
        final lastName = (admin['lastName'] ?? '').toString().trim();
        final fullName =
            '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();

        // Check if admin with this email already exists
        final byEmail = await db
            .collection('admins')
            .where('email', isEqualTo: email)
            .get();
        final activeEmail = byEmail.docs.where((d) => (d.data()['status'] ?? 'active') != 'deleted');

        if (activeEmail.isNotEmpty) {
          // Admin already exists — UPDATE & re-assign to level
          final docId = activeEmail.first.id;
          final payload = <String, dynamic>{
            if (firstName.isNotEmpty) 'firstName': firstName,
            if (middleName.isNotEmpty) 'middleName': middleName,
            if (lastName.isNotEmpty) 'lastName': lastName,
            'fullName': fullName.isEmpty ? (activeEmail.first.data()['fullName'] ?? email) : fullName,
            'level': level,
            'status': 'active',
            'updatedAt': DateTime.now().toIso8601String(),
            'permissions': _defaultPermissions(level),
          };
          if (admin['password'] != null && admin['password'].toString().isNotEmpty) {
            payload['password'] = admin['password'];
          }
          if (admin['phone'] != null && admin['phone'].toString().isNotEmpty) {
            payload['phone'] = admin['phone'];
          }
          await db.collection('admins').doc(docId).set(payload, SetOptions(merge: true));
          return {'success': true, 'id': docId, 'message': 'Admin updated and assigned successfully.'};
        }

        // New Admin: Check max 3 active limit per level
        final existingAdmins = await getAdmins(level: level);
        final activeCount = existingAdmins.where((a) => (a['status'] ?? 'active') != 'deleted').length;
        if (activeCount >= 3) {
          return {'success': false, 'error': 'Maximum 3 active admins allowed for $level level.'};
        }

        final payload = <String, dynamic>{
          'firstName': firstName,
          'middleName': middleName,
          'lastName': lastName,
          'fullName': fullName.isEmpty ? username : fullName,
          'email': email,
          'username': username.isEmpty ? email.split('@').first : username,
          'password': admin['password'] ?? 'admin123',
          'phone': admin['phone'] ?? '',
          'address': admin['address'] ?? '',
          'level': level,
          'role': 'admin',
          'status': 'active',
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'permissions': _defaultPermissions(level),
        };

        final ref = await db.collection('admins').add(payload);
        return {'success': true, 'id': ref.id, 'message': 'Admin assigned successfully.'};
      }
    } catch (e) {
      debugPrint('[createAdminResult error] $e');
      return {'success': false, 'error': 'Database error: $e'};
    }

    return {'success': false, 'error': 'Failed to connect to backend server or database.'};
  }

  static Future<String?> createAdmin(Map<String, dynamic> admin) async {
    final res = await createAdminResult(admin);
    if (res['success'] == true) {
      return (res['id'] ?? 'admin_created').toString();
    }
    if (res['error']?.toString().contains('Limit reached') == true ||
        res['error']?.toString().contains('Maximum 3') == true) {
      return 'limit_reached';
    }
    return null;
  }

  /// Update or auto-create an admin doc in Firebase Firestore and backend.
  static Future<bool> updateAdmin(
      String adminId, Map<String, dynamic> updates) async {
    try {
      final db = _maybeDb;
      final firstName = (updates['firstName'] ?? '').toString().trim();
      final middleName = (updates['middleName'] ?? '').toString().trim();
      final lastName = (updates['lastName'] ?? '').toString().trim();
      String fullName = (updates['fullName'] ?? '').toString().trim();
      if (fullName.isEmpty && (firstName.isNotEmpty || lastName.isNotEmpty)) {
        fullName =
            '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();
      }

      final payload = <String, dynamic>{
        ...updates,
        if (fullName.isNotEmpty) 'fullName': fullName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      payload.remove('adminId');
      payload.remove('createdAt');

      if (db != null) {
        final targetDocId = adminId.trim();

        // 1. Try finding doc by adminId if provided
        if (targetDocId.isNotEmpty) {
          final docSnap = await db.collection('admins').doc(targetDocId).get();
          if (docSnap.exists) {
            await db.collection('admins').doc(targetDocId).set(payload, SetOptions(merge: true));
            return true;
          }
        }

        // 2. Lookup by email
        final email = (updates['email'] ?? '').toString().toLowerCase().trim();
        if (email.isNotEmpty) {
          final byEmail =
              await db.collection('admins').where('email', isEqualTo: email).limit(1).get();
          if (byEmail.docs.isNotEmpty) {
            await db.collection('admins').doc(byEmail.docs.first.id).set(payload, SetOptions(merge: true));
            return true;
          }
        }

        // 3. Lookup by username
        final username = (updates['username'] ?? '').toString().toLowerCase().trim();
        if (username.isNotEmpty) {
          final byUsername =
              await db.collection('admins').where('username', isEqualTo: username).limit(1).get();
          if (byUsername.docs.isNotEmpty) {
            await db.collection('admins').doc(byUsername.docs.first.id).set(payload, SetOptions(merge: true));
            return true;
          }
        }

        // 4. Auto-create admin document if missing in Firestore console
        final newDocId = targetDocId.isNotEmpty
            ? targetDocId
            : (username.isNotEmpty
                ? username
                : 'admin_${DateTime.now().millisecondsSinceEpoch}');
        await db.collection('admins').doc(newDocId).set({
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'role': 'admin',
          ...payload,
        }, SetOptions(merge: true));
        return true;
      }
    } catch (e) {
      debugPrint('[RoleManagementService.updateAdmin error] $e');
    }

    // Backend API fallback
    try {
      final res = await ApiService.updateAdminSettings(adminId, updates);
      if (!res.containsKey('error')) return true;
    } catch (_) {}

    final resApi = await ApiService.superAdminUpdateAdmin(adminId, updates);
    return !resApi.containsKey('error');
  }

  /// Soft-delete an admin (status = deleted).
  static Future<bool> deleteAdmin(String adminId) async {
    try {
      await _db.collection('admins').doc(adminId).update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      final res = await ApiService.superAdminDeleteAdmin(adminId);
      return !res.containsKey('error');
    }
  }

  /// Suspend an admin.
  static Future<bool> suspendAdmin(String adminId,
      {String reason = ''}) async {
    try {
      await _db.collection('admins').doc(adminId).update({
        'status': 'suspended',
        'suspensionReason': reason,
        'suspendedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      final res = await ApiService.superAdminSuspendAdmin(adminId, reason: reason);
      return !res.containsKey('error');
    }
  }

  /// Reactivate a suspended admin.
  static Future<bool> activateAdmin(String adminId) async {
    try {
      await _db.collection('admins').doc(adminId).update({
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      final res = await ApiService.superAdminActivateAdmin(adminId);
      return !res.containsKey('error');
    }
  }

  // Legacy method — kept for backward compat
  static Future<bool> addAdmin(Map<String, dynamic> admin) async {
    final id = await createAdmin(admin);
    return id != null;
  }

  /// Legacy: invite a regular user (admin creates invite).
  /// Now routes to createUser; kept for backward compat with _invite_user_dialog.
  static Future<bool> inviteUser(Map<String, dynamic> user) async {
    final id = await createUser(user);
    return id != null;
  }

  // ──────────────────────────────── USERS ──────────────────────────────────

  /// Fetch all non-deleted users for a given equb level.
  static Future<List<Map<String, dynamic>>> getUsersByLevel(
      String level) async {
    final lvlLower = level.toLowerCase();
    try {
      final snap = await _db.collection('users').get();
      final users = snap.docs
          .where((d) {
            final data = d.data();
            final uLvl = (data['equbLevel'] ?? data['level'] ?? '').toString().toLowerCase();
            final status = (data['status'] ?? 'active').toString();
            return uLvl == lvlLower && status != 'deleted';
          })
          .map((d) => <String, dynamic>{...d.data(), 'userId': d.id, 'id': d.id})
          .toList();

      if (users.isNotEmpty) return users;

      // Fallback to API if empty
      final list = await ApiService.adminGetUsers(level: level);
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('[getUsersByLevel error] $e');
      final list = await ApiService.adminGetUsers(level: level);
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
  }

  /// Check uniqueId uniqueness (one-to-one mapping).
  static Future<bool> isUniqueIdTaken(String uniqueId,
      {String? excludeUserId}) async {
    if (uniqueId.trim().isEmpty) return false;
    try {
      final snap = await _db
          .collection('users')
          .where('uniqueId', isEqualTo: uniqueId.trim())
          .get();
      final activeDocs = snap.docs
          .where((d) => (d.data()['status'] ?? 'active') != 'deleted');
      if (activeDocs.isEmpty) return false;
      if (excludeUserId != null) {
        return activeDocs.any((d) => d.id != excludeUserId);
      }
      return true;
    } catch (e) {
      debugPrint('[isUniqueIdTaken error] $e');
      return false;
    }
  }

  /// Find a non-deleted user (equb member) by email, uniqueId, phone, or name.
  static Future<Map<String, dynamic>?> findUser(String input) async {
    final search = input.trim().toLowerCase();
    if (search.isEmpty) return null;

    try {
      final db = _maybeDb;
      if (db != null) {
        var q = await db
            .collection('users')
            .where('email', isEqualTo: search)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty && (q.docs.first.data()['status'] ?? 'active') != 'deleted') {
          return {'userId': q.docs.first.id, 'id': q.docs.first.id, ...q.docs.first.data()};
        }

        q = await db
            .collection('users')
            .where('uniqueId', isEqualTo: input.trim())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty && (q.docs.first.data()['status'] ?? 'active') != 'deleted') {
          return {'userId': q.docs.first.id, 'id': q.docs.first.id, ...q.docs.first.data()};
        }

        final all = await db.collection('users').get();
        for (final doc in all.docs) {
          final data = doc.data();
          if (data['status'] == 'deleted') continue;
          final uEmail = (data['email'] ?? '').toString().toLowerCase();
          final uUnique = (data['uniqueId'] ?? '').toString().toLowerCase();
          final uPhone = (data['phoneNumber'] ?? '').toString().toLowerCase();
          final uName = (data['fullName'] ?? '').toString().toLowerCase();
          final uFirst = (data['firstName'] ?? '').toString().toLowerCase();

          if (uEmail == search ||
              uUnique == search ||
              uPhone == search ||
              uName == search ||
              uFirst == search) {
            return {'userId': doc.id, 'id': doc.id, ...data};
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Create a new user (equb member) under an admin / level.
  /// Automatically updates existing user doc if email already exists (Upsert).
  static Future<Map<String, dynamic>> createUserResult(Map<String, dynamic> user) async {
    final email = (user['email'] ?? '').toString().trim().toLowerCase();
    String uniqueId = (user['uniqueId'] ?? '').toString().trim();
    if (uniqueId.isEmpty) {
      uniqueId = 'EQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
    }

    if (email.isEmpty) {
      return {'success': false, 'error': 'Email address is required.'};
    }

    // 1. Try Backend REST API first
    try {
      final apiRes = await ApiService.adminCreateUser(user);
      if (!apiRes.containsKey('error') && (apiRes['userId'] != null || apiRes['id'] != null)) {
        final id = (apiRes['userId'] ?? apiRes['id']).toString();
        return {'success': true, 'id': id, 'message': apiRes['message'] ?? 'User assigned successfully.'};
      }
      if (apiRes.containsKey('error') && !apiRes['error'].toString().contains('Cannot reach server')) {
        return {'success': false, 'error': apiRes['error'].toString()};
      }
    } catch (_) {}

    // 2. Firestore direct SDK fallback
    try {
      final db = _maybeDb;
      if (db != null) {
        final firstName = (user['firstName'] ?? '').toString().trim();
        final middleName = (user['middleName'] ?? '').toString().trim();
        final lastName = (user['lastName'] ?? '').toString().trim();
        final fullName =
            '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();

        // Check if user with email already exists
        final byEmail = await db
            .collection('users')
            .where('email', isEqualTo: email)
            .get();
        final activeEmailDocs = byEmail.docs
            .where((d) => (d.data()['status'] ?? 'active') != 'deleted');

        if (activeEmailDocs.isNotEmpty) {
          // User already exists — UPDATE & re-assign to level
          final docId = activeEmailDocs.first.id;
          final existingData = activeEmailDocs.first.data();

          if (uniqueId.isNotEmpty && uniqueId != (existingData['uniqueId'] ?? '')) {
            final taken = await isUniqueIdTaken(uniqueId, excludeUserId: docId);
            if (taken) {
              return {'success': false, 'error': 'Unique ID "$uniqueId" is already registered to another active member.'};
            }
          }

          final payload = <String, dynamic>{
            'firstName': firstName,
            'middleName': middleName,
            'lastName': lastName,
            'fullName': fullName.isEmpty ? email : fullName,
            'email': email,
            'phoneNumber': user['phoneNumber'] ?? '',
            'uniqueId': uniqueId,
            'equbLevel': user['equbLevel'] ?? 'low',
            'adminId': user['adminId'] ?? '',
            'status': 'active',
            'updatedAt': DateTime.now().toIso8601String(),
          };
          await db.collection('users').doc(docId).set(payload, SetOptions(merge: true));
          return {'success': true, 'id': docId, 'message': 'User updated and assigned to level.'};
        }

        // New User: Unique ID check
        final taken = await isUniqueIdTaken(uniqueId);
        if (taken) {
          return {'success': false, 'error': 'Unique ID "$uniqueId" is already registered to another active member.'};
        }

        final payload = <String, dynamic>{
          'firstName': firstName,
          'middleName': middleName,
          'lastName': lastName,
          'fullName': fullName.isEmpty ? 'Equb Member' : fullName,
          'email': email,
          'phoneNumber': user['phoneNumber'] ?? '',
          'uniqueId': uniqueId,
          'equbLevel': user['equbLevel'] ?? 'low',
          'adminId': user['adminId'] ?? '',
          'role': 'user',
          'status': 'active',
          'hasWon': false,
          'participationHistory': [],
          'balance': 0,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };

        final ref = await db.collection('users').add(payload);
        return {'success': true, 'id': ref.id, 'message': 'User registered successfully.'};
      }
    } catch (e) {
      debugPrint('[createUserResult error] $e');
      return {'success': false, 'error': 'Database error: $e'};
    }

    return {'success': false, 'error': 'Failed to connect to backend server or database.'};
  }

  static Future<String?> createUser(Map<String, dynamic> user) async {
    final res = await createUserResult(user);
    if (res['success'] == true) {
      return (res['id'] ?? 'user_created').toString();
    }
    return null;
  }

  /// Update an existing user doc.
  static Future<bool> updateUser(
      String userId, Map<String, dynamic> updates) async {
    try {
      final firstName = (updates['firstName'] ?? '').toString().trim();
      final middleName = (updates['middleName'] ?? '').toString().trim();
      final lastName = (updates['lastName'] ?? '').toString().trim();
      final fullName =
          '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();

      final payload = <String, dynamic>{
        ...updates,
        'fullName': fullName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      payload.remove('userId');
      payload.remove('createdAt');
      payload.remove('role');

      await _db.collection('users').doc(userId).update(payload);
      return true;
    } catch (_) {
      final res = await ApiService.adminUpdateUser(userId, updates);
      return !res.containsKey('error');
    }
  }

  /// Soft-delete a user.
  static Future<bool> deleteUser(String userId) async {
    try {
      await _db.collection('users').doc(userId).update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      final res = await ApiService.adminDeleteUser(userId);
      return !res.containsKey('error');
    }
  }

  /// Suspend a user.
  static Future<bool> suspendUser(String userId) async {
    try {
      await _db.collection('users').doc(userId).update({
        'status': 'suspended',
        'suspendedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      final res = await ApiService.adminSuspendUser(userId);
      return !res.containsKey('error');
    }
  }

  /// Reactivate a user.
  static Future<bool> activateUser(String userId) async {
    try {
      await _db.collection('users').doc(userId).update({
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      final res = await ApiService.adminActivateUser(userId);
      return !res.containsKey('error');
    }
  }

  // ──────────────────────────────── DRAW HISTORY ───────────────────────────

  /// Save a draw result to the draws collection.
  static Future<void> saveDrawResult({
    required String equbLevel,
    required String adminId,
    required String winnerId,
    required String winnerName,
    required String winnerUniqueId,
    required int drawNumber,
    required List<String> participantIds,
  }) async {
    try {
      await _db.collection('draws').add({
        'equbLevel': equbLevel,
        'adminId': adminId,
        'winnerId': winnerId,
        'winnerName': winnerName,
        'winnerUniqueId': winnerUniqueId,
        'drawNumber': drawNumber,
        'participants': participantIds,
        'totalParticipants': participantIds.length,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'completed',
      });
      await _db.collection('users').doc(winnerId).update({
        'hasWon': true,
        'lastWinDate': FieldValue.serverTimestamp(),
        'participationHistory': FieldValue.arrayUnion([
          {
            'drawNumber': drawNumber,
            'date': DateTime.now().toIso8601String(),
            'level': equbLevel,
          }
        ]),
      });
    } catch (_) {
      await ApiService.adminRunDraw(equbLevel);
    }
  }

  /// Get draw history strictly isolated for a given level with deduplication.
  static Future<List<Map<String, dynamic>>> getDrawHistory(
      String level) async {
    final targetLevel = level.toLowerCase().replaceAll('equb_', '').trim();
    final List<Map<String, dynamic>> rawList = [];
    final Set<String> seenKeys = {};

    try {
      final snap = await _db.collection('draws').get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final docLevel = (data['equbLevel'] ?? data['level'] ?? '').toString().toLowerCase().replaceAll('equb_', '').trim();
        if (docLevel == targetLevel) {
          rawList.add({...data, 'drawId': doc.id});
        }
      }
    } catch (e) {
      debugPrint('[getDrawHistory error] $e');
    }

    if (rawList.isEmpty) {
      // Fallback 1: ApiService backend API
      try {
        final list = await ApiService.adminGetDrawHistory(targetLevel);
        for (final item in list) {
          final m = Map<String, dynamic>.from(item as Map);
          final docLevel = (m['equbLevel'] ?? m['level'] ?? targetLevel).toString().toLowerCase().replaceAll('equb_', '').trim();
          if (docLevel == targetLevel) {
            rawList.add(m);
          }
        }
      } catch (_) {}
    }

    if (rawList.isEmpty) {
      // Fallback 2: Retrieve winners directly from users belonging strictly to this level
      try {
        final usersSnap = await _db.collection('users').get();
        int drawCounter = 1;
        for (final doc in usersSnap.docs) {
          final u = doc.data();
          final uLevel = (u['equbLevel'] ?? u['assignedLevel'] ?? '').toString().toLowerCase().replaceAll('equb_', '').trim();
          final isWinner = u['hasWon'] == true || u['status'] == 'winner';
          if (uLevel == targetLevel && isWinner) {
            rawList.add({
              'drawId': 'user_win_${doc.id}',
              'equbLevel': targetLevel,
              'winnerId': doc.id,
              'winnerName': u['fullName'] ?? u['firstName'] ?? 'Winner Participant',
              'winnerUniqueId': u['uniqueId'] ?? u['userId'] ?? doc.id,
              'drawNumber': drawCounter++,
              'createdAt': u['lastWinDate'] ?? u['updatedAt'] ?? u['createdAt'] ?? DateTime.now().toIso8601String(),
              'status': 'completed',
            });
          }
        }
      } catch (_) {}
    }

    // Deduplicate and sort by createdAt descending
    final List<Map<String, dynamic>> cleanList = [];
    for (final item in rawList) {
      final winnerId = (item['winnerUniqueId'] ?? item['winnerId'] ?? item['drawId'] ?? '').toString();
      final drawNum = item['drawNumber'] ?? 1;
      final key = '${winnerId}_$drawNum';
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        cleanList.add(item);
      }
    }

    cleanList.sort((a, b) {
      final aTime = a['createdAt']?.toString() ?? '';
      final bTime = b['createdAt']?.toString() ?? '';
      return bTime.compareTo(aTime);
    });

    return cleanList;
  }

  /// Get draw history for all levels combined (used for Home screen overview).
  static Future<List<Map<String, dynamic>>> getAllDrawHistory() async {
    final List<Map<String, dynamic>> result = [];
    for (final lvl in ['low', 'medium', 'high']) {
      final list = await getDrawHistory(lvl);
      result.addAll(list);
    }
    result.sort((a, b) {
      final aTime = a['createdAt']?.toString() ?? '';
      final bTime = b['createdAt']?.toString() ?? '';
      return bTime.compareTo(aTime);
    });
    return result;
  }

  // ──────────────────────────────── HELPERS ────────────────────────────────

  static Map<String, dynamic> _defaultPermissions(String level) {
    final base = {
      'canAddUsers': true,
      'canEditUsers': true,
      'canDeleteUsers': true,
      'canViewUsers': true,
      'canManageEqubs': true,
      'canRunAlgorithms': true,
      'canManagePayments': true,
      'canViewReports': true,
      'canSendNotifications': true,
      'canViewAnalytics': true,
      'canExportData': false,
      'canManageAdmins': false,
    };
    if (level == 'medium' || level == 'high') {
      base['canExportData'] = true;
    }
    return base;
  }

  /// Find admin (used during login) by email or username — checks admins collection.
  static Future<Map<String, dynamic>?> findAdmin(String identifier) async {
    final input = identifier.trim().toLowerCase();
    try {
      final byEmail = await _db
          .collection('admins')
          .where('email', isEqualTo: input)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty && (byEmail.docs.first.data()['status'] ?? 'active') != 'deleted') {
        return {...byEmail.docs.first.data(), 'adminId': byEmail.docs.first.id};
      }
      final byUsername = await _db
          .collection('admins')
          .where('username', isEqualTo: input)
          .limit(1)
          .get();
      if (byUsername.docs.isNotEmpty && (byUsername.docs.first.data()['status'] ?? 'active') != 'deleted') {
        return {...byUsername.docs.first.data(), 'adminId': byUsername.docs.first.id};
      }
    } catch (_) {}
    return null;
  }
}
