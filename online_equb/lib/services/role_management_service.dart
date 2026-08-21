import 'dart:convert';
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
  static Future<List<Map<String, dynamic>>> getAdmins(
      {String? level}) async {
    try {
      Query<Map<String, dynamic>> q =
          _db.collection('admins').where('status', isNotEqualTo: 'deleted');
      if (level != null && level != 'all') {
        q = q.where('level', isEqualTo: level);
      }
      final snap = await q.orderBy('createdAt', descending: true).get();
      return snap.docs
          .map((d) => <String, dynamic>{...d.data(), 'adminId': d.id})
          .toList();
    } catch (_) {
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
      return <String, dynamic>{...doc.data()!, 'adminId': doc.id};
    } catch (_) {
      final res = await ApiService.superAdminGetAdmin(adminId);
      if (res.containsKey('error')) return null;
      return res;
    }
  }

  /// Create a new admin document.
  static Future<String?> createAdmin(Map<String, dynamic> admin) async {
    final email = (admin['email'] ?? '').toString().trim().toLowerCase();
    final username = (admin['username'] ?? '').toString().trim().toLowerCase();
    if (email.isEmpty) return null;

    try {
      final byEmail = await _db
          .collection('admins')
          .where('email', isEqualTo: email)
          .where('status', isNotEqualTo: 'deleted')
          .get();
      if (byEmail.docs.isNotEmpty) return null;

      if (username.isNotEmpty) {
        final byUsername = await _db
            .collection('admins')
            .where('username', isEqualTo: username)
            .where('status', isNotEqualTo: 'deleted')
            .get();
        if (byUsername.docs.isNotEmpty) return null;
      }

      final firstName = (admin['firstName'] ?? '').toString().trim();
      final middleName = (admin['middleName'] ?? '').toString().trim();
      final lastName = (admin['lastName'] ?? '').toString().trim();
      final fullName =
          '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();

      final payload = <String, dynamic>{
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'fullName': fullName,
        'email': email,
        'username': username.isEmpty ? email.split('@').first : username,
        'password': admin['password'] ?? '',
        'phone': admin['phone'] ?? '',
        'address': admin['address'] ?? '',
        'level': admin['level'] ?? 'low',
        'role': 'admin',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'permissions': _defaultPermissions(admin['level'] ?? 'low'),
      };

      final ref = await _db.collection('admins').add(payload);
      return ref.id;
    } catch (_) {
      final res = await ApiService.superAdminCreateAdmin(admin);
      if (res.containsKey('error')) return null;
      return (res['adminId'] ?? res['id'] ?? 'admin_created').toString();
    }
  }

  /// Update an existing admin doc.
  static Future<bool> updateAdmin(
      String adminId, Map<String, dynamic> updates) async {
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
      payload.remove('adminId');
      payload.remove('createdAt');
      payload.remove('role');

      await _db.collection('admins').doc(adminId).update(payload);
      return true;
    } catch (_) {
      final res = await ApiService.superAdminUpdateAdmin(adminId, updates);
      return !res.containsKey('error');
    }
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
    try {
      final snap = await _db
          .collection('users')
          .where('equbLevel', isEqualTo: level)
          .where('status', isNotEqualTo: 'deleted')
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs
          .map((d) => <String, dynamic>{...d.data(), 'userId': d.id})
          .toList();
    } catch (_) {
      final list = await ApiService.adminGetUsers(level: level);
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
  }

  /// Check uniqueId uniqueness (one-to-one mapping).
  static Future<bool> isUniqueIdTaken(String uniqueId,
      {String? excludeUserId}) async {
    try {
      final snap = await _db
          .collection('users')
          .where('uniqueId', isEqualTo: uniqueId.trim())
          .where('status', isNotEqualTo: 'deleted')
          .get();
      if (snap.docs.isEmpty) return false;
      if (excludeUserId != null) {
        return snap.docs.any((d) => d.id != excludeUserId);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Create a new user (equb member) under an admin / level.
  static Future<String?> createUser(Map<String, dynamic> user) async {
    final email = (user['email'] ?? '').toString().trim().toLowerCase();
    final uniqueId = (user['uniqueId'] ?? '').toString().trim();

    try {
      if (email.isNotEmpty) {
        final byEmail = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .where('status', isNotEqualTo: 'deleted')
            .get();
        if (byEmail.docs.isNotEmpty) return null;
      }

      if (uniqueId.isNotEmpty) {
        final taken = await isUniqueIdTaken(uniqueId);
        if (taken) return null;
      }

      final firstName = (user['firstName'] ?? '').toString().trim();
      final middleName = (user['middleName'] ?? '').toString().trim();
      final lastName = (user['lastName'] ?? '').toString().trim();
      final fullName =
          '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();

      final payload = <String, dynamic>{
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'fullName': fullName,
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
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final ref = await _db.collection('users').add(payload);
      return ref.id;
    } catch (_) {
      final res = await ApiService.adminCreateUser(user);
      if (res.containsKey('error')) return null;
      return (res['userId'] ?? res['id'] ?? 'user_created').toString();
    }
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

  /// Get draw history for a level.
  static Future<List<Map<String, dynamic>>> getDrawHistory(
      String level) async {
    try {
      final snap = await _db
          .collection('draws')
          .where('equbLevel', isEqualTo: level)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs
          .map((d) => <String, dynamic>{...d.data(), 'drawId': d.id})
          .toList();
    } catch (_) {
      final list = await ApiService.adminGetDrawHistory(level);
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
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
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        return {...byEmail.docs.first.data(), 'adminId': byEmail.docs.first.id};
      }
      final byUsername = await _db
          .collection('admins')
          .where('username', isEqualTo: input)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (byUsername.docs.isNotEmpty) {
        return {
          ...byUsername.docs.first.data(),
          'adminId': byUsername.docs.first.id
        };
      }
    } catch (_) {}
    return null;
  }
}
