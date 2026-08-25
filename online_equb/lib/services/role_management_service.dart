import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'offline_service.dart';

/// Role Management Service — full CRUD for all equb entities.
///
/// ═══════════════════════════════════════════════════════════════
/// STORAGE PRIORITY (every read AND write uses this order):
///
///   1. REST API backend   ← PRIMARY on all platforms.
///      The Node.js backend is connected to the REAL Google Cloud
///      Firestore via the service-account key.  This is the single
///      source of truth.
///
///   2. Firebase SDK       ← Only used when backend is unreachable
///      (e.g. Android / iOS with a valid google-services.json and
///      the backend server is offline).
///
///   3. SharedPreferences  ← Offline-only last resort.  Data saved
///      here is synced back to the backend as soon as connectivity
///      is restored by OfflineService.
/// ═══════════════════════════════════════════════════════════════
class RoleManagementService {
  static const String _superProfileKey = 'super_admin_profile_v2';

  // ── Firestore SDK accessor (null when SDK not available on this platform) ─
  static FirebaseFirestore? get _maybeDb {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  // ── Helper: convert ISO string (or now) to display ───────────────────────
  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  // ── Helper: strip FieldValue / Timestamp so maps are JSON-safe ───────────
  static Map<String, dynamic> _toSerializable(Map<String, dynamic> data) {
    final now = _nowIso();
    return data.map((k, v) {
      if (v is FieldValue) return MapEntry(k, now);
      if (v is Timestamp) return MapEntry(k, v.toDate().toIso8601String());
      return MapEntry(k, v);
    });
  }

  // ════════════════════════════════════════════════════════════════
  // SUPER ADMIN
  // ════════════════════════════════════════════════════════════════

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
    // 1. REST API backend
    try {
      final res = await ApiService.superAdminGetStats();
      if (res.containsKey('superAdmin') && res['superAdmin'] is Map) {
        return Map<String, dynamic>.from(res['superAdmin'] as Map);
      }
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final doc =
            await db.collection('meta').doc('super_admin_profile').get();
        if (doc.exists && doc.data() != null) {
          return Map<String, dynamic>.from(doc.data()!);
        }
      }
    } catch (_) {}

    // 3. Local prefs
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_superProfileKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
          return {...defaultSuperAdminProfile(), ...decoded};
        }
      }
    } catch (_) {}

    final profile = defaultSuperAdminProfile();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_superProfileKey, jsonEncode(profile));
    } catch (_) {}
    return profile;
  }

  static Future<void> saveSuperAdminProfile(
      Map<String, dynamic> profile) async {
    final merged = {
      ...defaultSuperAdminProfile(),
      ...profile,
      'role': 'super_admin',
    };
    merged['fullName'] =
        '${merged['firstName'] ?? ''} ${merged['middleName'] ?? ''} ${merged['lastName'] ?? ''}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    // 1. REST API
    try {
      await ApiService.superAdminUpdateAdmin('super_admin', merged);
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        await db
            .collection('meta')
            .doc('super_admin_profile')
            .set(merged, SetOptions(merge: true));
      }
    } catch (_) {}

    // 3. Local prefs
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_superProfileKey, jsonEncode(merged));
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════
  // ADMINS
  // ════════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getAdmins(
      {String? level}) async {
    final List<Map<String, dynamic>> results = [];
    final Set<String> seenIds = {};

    // 1. REST API (primary)
    bool apiLoaded = false;
    try {
      final list = await ApiService.superAdminGetAdmins(level: level);
      for (final item in list) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['adminId'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty && !seenIds.contains(id)) {
          results.add(m);
          seenIds.add(id);
          if (m['email'] != null) seenIds.add(m['email'].toString().toLowerCase());
        }
      }
      apiLoaded = results.isNotEmpty;
    } catch (_) {}

    // 2. Firestore SDK (when API unavailable)
    if (!apiLoaded) {
      try {
        final db = _maybeDb;
        if (db != null) {
          final snap = await db.collection('admins').get();
          for (final doc in snap.docs) {
            final data = doc.data();
            if ((data['status'] ?? 'active') == 'deleted') continue;
            final aLvl = (data['level'] ?? data['equbLevel'] ?? 'low')
                .toString()
                .toLowerCase();
            if (level == null ||
                level == 'all' ||
                aLvl == level.toLowerCase()) {
              final item = <String, dynamic>{
                ...data,
                'adminId': doc.id,
                'id': doc.id,
              };
              if (!seenIds.contains(doc.id)) {
                results.add(item);
                seenIds.add(doc.id);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Local cache (offline last resort)
    if (results.isEmpty) {
      try {
        final cached = await OfflineService.getCachedAdmins();
        for (final a in cached) {
          final id = (a['adminId'] ?? a['id'] ?? '').toString();
          final aLvl = (a['level'] ?? a['equbLevel'] ?? 'low').toString().toLowerCase();
          if ((level == null || level == 'all' || aLvl == level.toLowerCase()) &&
              !seenIds.contains(id)) {
            results.add(a);
            seenIds.add(id);
          }
        }
      } catch (_) {}
    }

    OfflineService.cacheAdmins(results);
    return results;
  }

  static Future<List<Map<String, dynamic>>> getAssignedAdmins(
          {String? level}) =>
      getAdmins(level: level);

  static Future<Map<String, dynamic>?> getAdminById(String adminId) async {
    if (adminId.isEmpty) return null;

    // 1. REST API
    try {
      final res = await ApiService.superAdminGetAdmin(adminId);
      if (!res.containsKey('error') && res.isNotEmpty) return res;
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final doc = await db.collection('admins').doc(adminId).get();
        if (doc.exists) {
          return <String, dynamic>{...doc.data()!, 'adminId': doc.id, 'id': doc.id};
        }
      }
    } catch (_) {}

    // 3. Local cache
    try {
      final cached = await OfflineService.getCachedAdmins();
      for (final a in cached) {
        if ((a['adminId'] ?? a['id'] ?? '').toString() == adminId) return a;
      }
    } catch (_) {}

    return null;
  }

  static Future<Map<String, dynamic>> createAdminResult(
      Map<String, dynamic> admin) async {
    final email = (admin['email'] ?? '').toString().trim().toLowerCase();
    final username = (admin['username'] ?? '').toString().trim().toLowerCase();
    final level = (admin['level'] ?? admin['equbLevel'] ?? 'low')
        .toString()
        .toLowerCase();

    if (email.isEmpty && username.isEmpty) {
      return {'success': false, 'error': 'Email address or username is required.'};
    }

    final firstName = (admin['firstName'] ?? '').toString().trim();
    final middleName = (admin['middleName'] ?? '').toString().trim();
    final lastName = (admin['lastName'] ?? '').toString().trim();
    final fullName =
        '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();

    final adminData = <String, dynamic>{
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'fullName': fullName.isEmpty ? (username.isNotEmpty ? username : email) : fullName,
      'email': email,
      'username': username.isEmpty
          ? (email.contains('@') ? email.split('@').first : email)
          : username,
      'password': admin['password'] ?? 'admin123',
      'phone': admin['phone'] ?? '',
      'address': admin['address'] ?? '',
      'level': level,
      'equbLevel': level,
      'role': 'admin',
      'status': 'active',
      'createdAt': _nowIso(),
      'updatedAt': _nowIso(),
      'permissions': _defaultPermissions(level),
    };

    // 1. REST API (primary — writes to live Firestore via backend)
    try {
      final apiRes = await ApiService.superAdminCreateAdmin({...admin, ...adminData});
      if (!apiRes.containsKey('error')) {
        final id = (apiRes['adminId'] ?? apiRes['id'] ?? '').toString();
        if (id.isNotEmpty) {
          adminData['adminId'] = id;
          adminData['id'] = id;
          await OfflineService.saveAdminOffline(adminData);
          return {
            'success': true,
            'id': id,
            'message': apiRes['message'] ?? 'Admin assigned successfully.',
          };
        }
      }
      final errStr = (apiRes['error'] ?? '').toString();
      final isNetworkErr = errStr.contains('Cannot reach') ||
          errStr.contains('SocketException') ||
          errStr.contains('Connection refused');
      if (!isNetworkErr && apiRes.containsKey('error')) {
        return {'success': false, 'error': errStr};
      }
    } catch (_) {}

    // 2. Firestore SDK (when backend unreachable)
    try {
      final db = _maybeDb;
      if (db != null) {
        if (email.isNotEmpty) {
          final byEmail = await db
              .collection('admins')
              .where('email', isEqualTo: email)
              .get();
          final activeDocs = byEmail.docs
              .where((d) => (d.data()['status'] ?? 'active') != 'deleted');
          if (activeDocs.isNotEmpty) {
            final docId = activeDocs.first.id;
            adminData['adminId'] = docId;
            adminData['id'] = docId;
            adminData.remove('createdAt');
            adminData['updatedAt'] = FieldValue.serverTimestamp();
            await db
                .collection('admins')
                .doc(docId)
                .set(adminData, SetOptions(merge: true));
            await OfflineService.saveAdminOffline(adminData);
            return {'success': true, 'id': docId, 'message': 'Admin updated.'};
          }
        }
        final existing = await getAdmins(level: level);
        final activeCount =
            existing.where((a) => (a['status'] ?? 'active') != 'deleted').length;
        if (activeCount >= 3) {
          return {
            'success': false,
            'error': 'Maximum 3 active admins allowed for $level level.',
          };
        }
        adminData['createdAt'] = FieldValue.serverTimestamp();
        adminData['updatedAt'] = FieldValue.serverTimestamp();
        final ref = await db.collection('admins').add(adminData);
        adminData['adminId'] = ref.id;
        adminData['id'] = ref.id;
        await OfflineService.saveAdminOffline(_toSerializable(adminData));
        return {'success': true, 'id': ref.id, 'message': 'Admin assigned successfully.'};
      }
    } catch (e) {
      debugPrint('[createAdminResult SDK] $e');
    }

    // 3. Offline fallback
    final localId = 'admin_offline_${DateTime.now().millisecondsSinceEpoch}';
    adminData['adminId'] = localId;
    adminData['id'] = localId;
    await OfflineService.saveAdminOffline(adminData);
    return {
      'success': true,
      'id': localId,
      'message': 'Admin saved offline — will sync when connected.',
    };
  }

  static Future<String?> createAdmin(Map<String, dynamic> admin) async {
    final res = await createAdminResult(admin);
    if (res['success'] == true) return (res['id'] ?? '').toString();
    if (res['error']?.toString().contains('Maximum 3') == true) return 'limit_reached';
    return null;
  }

  static Future<bool> updateAdmin(
      String adminId, Map<String, dynamic> updates) async {
    final firstName = (updates['firstName'] ?? '').toString().trim();
    final middleName = (updates['middleName'] ?? '').toString().trim();
    final lastName = (updates['lastName'] ?? '').toString().trim();
    String fullName = (updates['fullName'] ?? '').toString().trim();
    if (fullName.isEmpty && (firstName.isNotEmpty || lastName.isNotEmpty)) {
      fullName = '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    final payload = <String, dynamic>{
      ...updates,
      if (fullName.isNotEmpty) 'fullName': fullName,
      'updatedAt': _nowIso(),
    };
    payload.remove('adminId');
    payload.remove('createdAt');

    // 1. REST API
    bool done = false;
    try {
      final res = await ApiService.superAdminUpdateAdmin(adminId, payload);
      if (!res.containsKey('error')) done = true;
    } catch (_) {}
    if (!done) {
      try {
        final res = await ApiService.updateAdminSettings(adminId, payload);
        if (!res.containsKey('error')) done = true;
      } catch (_) {}
    }

    // 2. Firestore SDK
    if (!done) {
      try {
        final db = _maybeDb;
        if (db != null) {
          final fsPayload = <String, dynamic>{
            ...payload,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (adminId.isNotEmpty) {
            await db
                .collection('admins')
                .doc(adminId)
                .set(fsPayload, SetOptions(merge: true));
            done = true;
          }
        }
      } catch (_) {}
    }

    return done;
  }

  static Future<bool> deleteAdmin(String adminId) async {
    bool done = false;
    try {
      final res = await ApiService.superAdminDeleteAdmin(adminId);
      if (!res.containsKey('error')) done = true;
    } catch (_) {}
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('admins').doc(adminId).update({
          'status': 'deleted',
          'deletedAt': FieldValue.serverTimestamp(),
        });
        done = true;
      }
    } catch (_) {}
    return done;
  }

  static Future<bool> suspendAdmin(String adminId, {String reason = ''}) async {
    bool done = false;
    try {
      final res = await ApiService.superAdminSuspendAdmin(adminId, reason: reason);
      if (!res.containsKey('error')) done = true;
    } catch (_) {}
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('admins').doc(adminId).update({
          'status': 'suspended',
          'suspensionReason': reason,
          'suspendedAt': FieldValue.serverTimestamp(),
        });
        done = true;
      }
    } catch (_) {}
    return done;
  }

  static Future<bool> activateAdmin(String adminId) async {
    bool done = false;
    try {
      final res = await ApiService.superAdminActivateAdmin(adminId);
      if (!res.containsKey('error')) done = true;
    } catch (_) {}
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('admins').doc(adminId).update({
          'status': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        done = true;
      }
    } catch (_) {}
    return done;
  }

  static Future<bool> addAdmin(Map<String, dynamic> admin) async {
    final id = await createAdmin(admin);
    return id != null;
  }

  static Future<bool> inviteUser(Map<String, dynamic> user) async {
    final id = await createUser(user);
    return id != null;
  }

  static Future<Map<String, dynamic>?> findAdmin(String identifier) async {
    final input = identifier.trim().toLowerCase();
    if (input.isEmpty) return null;

    // ── 1. Firestore SDK (PRIMARY — works on real Android/iOS with Firebase) ─
    // This always works on a real device because Firebase SDK connects
    // directly to Google Cloud — no local server needed.
    try {
      final db = _maybeDb;
      if (db != null) {
        // Search by email
        final byEmail = await db
            .collection('admins')
            .where('email', isEqualTo: input)
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty &&
            (byEmail.docs.first.data()['status'] ?? 'active') != 'deleted') {
          final doc = byEmail.docs.first;
          final result = {
            ...doc.data(),
            'adminId': doc.id,
            'id': doc.id,
          };
          // Cache for offline use
          OfflineService.saveAdminOffline(result);
          return result;
        }
        // Search by username
        final byUser = await db
            .collection('admins')
            .where('username', isEqualTo: input)
            .limit(1)
            .get();
        if (byUser.docs.isNotEmpty &&
            (byUser.docs.first.data()['status'] ?? 'active') != 'deleted') {
          final doc = byUser.docs.first;
          final result = {
            ...doc.data(),
            'adminId': doc.id,
            'id': doc.id,
          };
          OfflineService.saveAdminOffline(result);
          return result;
        }
      }
    } catch (e) {
      debugPrint('[findAdmin Firestore] $e');
    }

    // ── 2. REST API backend (secondary — only works when server reachable) ─
    try {
      final admins = await ApiService.superAdminGetAdmins()
          .timeout(const Duration(seconds: 5));
      for (final item in admins) {
        final m = Map<String, dynamic>.from(item as Map);
        final email    = (m['email']    ?? '').toString().toLowerCase();
        final username = (m['username'] ?? '').toString().toLowerCase();
        final id       = (m['adminId']  ?? m['id'] ?? '').toString();
        if (email == input || username == input || id == input) return m;
      }
    } catch (_) {}

    // ── 3. Local SharedPreferences cache (offline fallback) ──────────────
    try {
      final cached = await OfflineService.getCachedAdmins();
      for (final a in cached) {
        final email    = (a['email']    ?? '').toString().toLowerCase();
        final username = (a['username'] ?? '').toString().toLowerCase();
        final id       = (a['adminId']  ?? a['id'] ?? '').toString();
        if (email == input || username == input || id == input) return a;
      }
    } catch (_) {}

    return null;
  }

  // ════════════════════════════════════════════════════════════════
  // USERS (equb members)
  // ════════════════════════════════════════════════════════════════

  /// Fetch all non-deleted members for a given equb level.
  /// REST API (live Firestore via backend) → SDK → local cache.
  static Future<List<Map<String, dynamic>>> getUsersByLevel(
      String level) async {
    final lvlLower = level.toLowerCase().replaceAll('equb_', '').trim();
    final List<Map<String, dynamic>> results = [];
    final Set<String> seenIds = {};
    bool loaded = false;

    // ── 1. Firestore SDK — PRIMARY on real Android/iOS (direct cloud access)
    try {
      final db = _maybeDb;
      if (db != null) {
        // Query both field names to catch all registered users
        for (final field in ['equbLevel', 'level']) {
          final snap = await db
              .collection('users')
              .where(field, isEqualTo: lvlLower)
              .get();
          for (final d in snap.docs) {
            if (seenIds.contains(d.id)) continue;
            final data = d.data();
            if ((data['status'] ?? 'active').toString() == 'deleted') continue;
            results.add(<String, dynamic>{...data, 'userId': d.id, 'id': d.id});
            seenIds.add(d.id);
            if (data['email'] != null) seenIds.add(data['email'].toString().toLowerCase());
            if (data['uniqueId'] != null) seenIds.add(data['uniqueId'].toString());
          }
        }
        loaded = results.isNotEmpty;
      }
    } catch (e) {
      debugPrint('[getUsersByLevel Firestore] $e');
    }

    // ── 2. REST API backend (when Firestore SDK unavailable — e.g. Linux)
    if (!loaded) {
      try {
        final list = await ApiService.adminGetUsers(level: lvlLower)
            .timeout(const Duration(seconds: 6));
        for (final item in list) {
          final m = Map<String, dynamic>.from(item as Map);
          final id = (m['userId'] ?? m['id'] ?? '').toString();
          final status = (m['status'] ?? 'active').toString();
          if (status == 'deleted' || id.isEmpty || seenIds.contains(id)) continue;
          results.add(m);
          seenIds.add(id);
          if (m['email'] != null) seenIds.add(m['email'].toString().toLowerCase());
          if (m['uniqueId'] != null) seenIds.add(m['uniqueId'].toString());
        }
        loaded = results.isNotEmpty;
      } catch (_) {}
    }

    // 3. Local cache (full offline mode)
    if (!loaded || results.isEmpty) {
      try {
        final cached = await OfflineService.getCachedUsers(lvlLower);
        for (final u in cached) {
          final id = (u['userId'] ?? u['id'] ?? '').toString();
          final status = (u['status'] ?? 'active').toString();
          if (status == 'deleted' || id.isEmpty || seenIds.contains(id)) continue;
          results.add(u);
          seenIds.add(id);
        }
      } catch (_) {}
    }

    // Always refresh local cache so offline mode shows latest data
    if (loaded && results.isNotEmpty) {
      await OfflineService.cacheUsers(lvlLower, results);
    }
    return results;
  }

  static Future<bool> isUniqueIdTaken(String uniqueId,
      {String? excludeUserId}) async {
    if (uniqueId.trim().isEmpty) return false;

    // 1. REST API — check all users across levels
    try {
      for (final lvl in ['low', 'medium', 'high']) {
        final list = await ApiService.adminGetUsers(level: lvl);
        for (final item in list) {
          final m = Map<String, dynamic>.from(item as Map);
          final uUnique = (m['uniqueId'] ?? '').toString().trim();
          final uId = (m['userId'] ?? m['id'] ?? '').toString();
          final status = (m['status'] ?? 'active').toString();
          if (status == 'deleted') continue;
          if (uUnique == uniqueId.trim()) {
            if (excludeUserId != null && uId == excludeUserId) continue;
            return true;
          }
        }
      }
      return false;
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final snap = await db
            .collection('users')
            .where('uniqueId', isEqualTo: uniqueId.trim())
            .get();
        final active =
            snap.docs.where((d) => (d.data()['status'] ?? 'active') != 'deleted');
        if (active.isNotEmpty) {
          if (excludeUserId != null) return active.any((d) => d.id != excludeUserId);
          return true;
        }
      }
    } catch (_) {}

    // 3. Local cache
    for (final lvl in ['low', 'medium', 'high']) {
      final cached = await OfflineService.getCachedUsers(lvl);
      for (final u in cached) {
        final uId = (u['userId'] ?? u['id'] ?? '').toString();
        final uUnique = (u['uniqueId'] ?? '').toString().trim();
        final status = (u['status'] ?? 'active').toString();
        if (status != 'deleted' && uUnique == uniqueId.trim()) {
          if (excludeUserId != null && uId == excludeUserId) continue;
          return true;
        }
      }
    }
    return false;
  }

  static Future<Map<String, dynamic>?> findUser(String input) async {
    final search = input.trim().toLowerCase();
    if (search.isEmpty) return null;

    // 1. REST API
    try {
      for (final lvl in ['low', 'medium', 'high']) {
        final list = await ApiService.adminGetUsers(level: lvl);
        for (final item in list) {
          final m = Map<String, dynamic>.from(item as Map);
          if ((m['status'] ?? 'active') == 'deleted') continue;
          final uEmail = (m['email'] ?? '').toString().toLowerCase();
          final uUnique = (m['uniqueId'] ?? '').toString().toLowerCase();
          final uPhone = (m['phoneNumber'] ?? '').toString().toLowerCase();
          final uName = (m['fullName'] ?? '').toString().toLowerCase();
          if (uEmail == search || uUnique == search || uPhone == search ||
              uName == search) {
            return m;
          }
        }
      }
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        var q = await db
            .collection('users')
            .where('email', isEqualTo: search)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty &&
            (q.docs.first.data()['status'] ?? 'active') != 'deleted') {
          return {'userId': q.docs.first.id, 'id': q.docs.first.id, ...q.docs.first.data()};
        }
        q = await db
            .collection('users')
            .where('uniqueId', isEqualTo: input.trim())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty &&
            (q.docs.first.data()['status'] ?? 'active') != 'deleted') {
          return {'userId': q.docs.first.id, 'id': q.docs.first.id, ...q.docs.first.data()};
        }
      }
    } catch (_) {}

    // 3. Local cache
    for (final lvl in ['low', 'medium', 'high']) {
      final cached = await OfflineService.getCachedUsers(lvl);
      for (final u in cached) {
        if ((u['status'] ?? 'active') == 'deleted') continue;
        final uEmail = (u['email'] ?? '').toString().toLowerCase();
        final uUnique = (u['uniqueId'] ?? '').toString().toLowerCase();
        final uPhone = (u['phoneNumber'] ?? '').toString().toLowerCase();
        final uName = (u['fullName'] ?? '').toString().toLowerCase();
        if (uEmail == search || uUnique == search || uPhone == search ||
            uName == search) {
          return u;
        }
      }
    }
    return null;
  }

  /// Register a new equb member.  Writes to live Firestore via backend.
  static Future<Map<String, dynamic>> createUserResult(
      Map<String, dynamic> user) async {
    final email = (user['email'] ?? '').toString().trim().toLowerCase();
    String uniqueId = (user['uniqueId'] ?? '').toString().trim();
    if (uniqueId.isEmpty) {
      uniqueId = 'EQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    }
    if (email.isEmpty) {
      return {'success': false, 'error': 'Email address is required.'};
    }

    final equbLevel = (user['equbLevel'] ?? user['level'] ?? 'low')
        .toString()
        .toLowerCase()
        .replaceAll('equb_', '')
        .trim();
    final firstName = (user['firstName'] ?? '').toString().trim();
    final middleName = (user['middleName'] ?? '').toString().trim();
    final lastName = (user['lastName'] ?? '').toString().trim();
    final fullName =
        '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final adminId = (user['adminId'] ?? '').toString().trim();
    final nowIso = _nowIso();

    final userData = <String, dynamic>{
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'fullName': fullName.isEmpty ? email : fullName,
      'email': email,
      'phoneNumber': (user['phoneNumber'] ?? user['phone'] ?? '').toString(),
      'uniqueId': uniqueId,
      'nationalId': uniqueId,        // backend expects nationalId too
      'equbLevel': equbLevel,
      'level': equbLevel,
      'adminId': adminId,
      'role': 'user',
      'status': 'active',
      'hasWon': false,
      'participationHistory': <dynamic>[],
      'balance': 0,
      'createdAt': nowIso,
      'updatedAt': nowIso,
    };

    // ── 1. Firestore SDK (PRIMARY on real Android/iOS — direct cloud write) ─
    try {
      final db = _maybeDb;
      if (db != null) {
        // Check for duplicate email
        if (email.isNotEmpty) {
          final byEmail = await db
              .collection('users')
              .where('email', isEqualTo: email)
              .get();
          final activeDocs = byEmail.docs
              .where((d) => (d.data()['status'] ?? 'active') != 'deleted');
          if (activeDocs.isNotEmpty) {
            final docId = activeDocs.first.id;
            final fsData = <String, dynamic>{
              ...userData,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            fsData.remove('createdAt');
            await db.collection('users').doc(docId).set(fsData, SetOptions(merge: true));
            final cacheData = {...userData, 'userId': docId, 'id': docId};
            await OfflineService.saveUserOffline(equbLevel, cacheData);
            return {
              'success': true,
              'id': docId,
              'message': 'User updated — $equbLevel level.  ተጠቃሚ ተሻሽሏል።',
            };
          }
        }
        // Check uniqueId uniqueness
        if (uniqueId.isNotEmpty) {
          final taken = await isUniqueIdTaken(uniqueId);
          if (taken) {
            return {
              'success': false,
              'error': 'Unique ID "$uniqueId" is already registered. / ልዩ መታወቂያ ቀድሞ ተመዝግቧል።',
            };
          }
        }
        final fsData = <String, dynamic>{
          ...userData,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final ref = await db.collection('users').add(fsData);
        final cacheData = {...userData, 'userId': ref.id, 'id': ref.id};
        await OfflineService.saveUserOffline(equbLevel, cacheData);
        // Background sync to backend
        Future.microtask(() async {
          try { await ApiService.adminCreateUser({...userData, 'userId': ref.id}); } catch (_) {}
        });
        return {
          'success': true,
          'id': ref.id,
          'message': 'User registered — $equbLevel.  ተጠቃሚ ተመዝግቧል።',
        };
      }
    } catch (e) {
      debugPrint('[createUserResult Firestore] $e');
    }

    // ── 2. REST API (when Firestore SDK unavailable — e.g. Linux desktop) ─
    try {
      final apiRes = await ApiService.adminCreateUser(userData)
          .timeout(const Duration(seconds: 10));
      if (!apiRes.containsKey('error')) {
        final id = (apiRes['userId'] ?? apiRes['id'] ?? '').toString();
        if (id.isNotEmpty) {
          final cacheData = {...userData, 'userId': id, 'id': id};
          await OfflineService.saveUserOffline(equbLevel, cacheData);
          return {
            'success': true,
            'id': id,
            'message': apiRes['message'] ?? 'User registered successfully.',
          };
        }
      }
      final errStr = (apiRes['error'] ?? '').toString();
      final isNetworkErr = errStr.contains('Cannot reach') ||
          errStr.contains('SocketException') ||
          errStr.contains('Connection refused') ||
          errStr.contains('Invalid admin token');
      if (!isNetworkErr && apiRes.containsKey('error')) {
        return {'success': false, 'error': errStr};
      }
    } catch (_) {}
    // ── 3. Offline fallback ────────────────────────────────────────────
    final localId = 'user_offline_${DateTime.now().millisecondsSinceEpoch}';
    final cacheData = {...userData, 'userId': localId, 'id': localId};
    await OfflineService.saveUserOffline(equbLevel, cacheData);
    return {
      'success': true,
      'id': localId,
      'message': 'User saved offline — will sync when connected.',
    };
  }

  static Future<String?> createUser(Map<String, dynamic> user) async {
    final res = await createUserResult(user);
    if (res['success'] == true) return (res['id'] ?? '').toString();
    return null;
  }

  static Future<bool> updateUser(
      String userId, Map<String, dynamic> updates) async {
    final firstName = (updates['firstName'] ?? '').toString().trim();
    final middleName = (updates['middleName'] ?? '').toString().trim();
    final lastName = (updates['lastName'] ?? '').toString().trim();
    final fullName =
        '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lvl = (updates['equbLevel'] ?? updates['level'] ?? 'low').toString().toLowerCase();
    bool updated = false;

    // 1. REST API
    try {
      final res = await ApiService.adminUpdateUser(userId, {
        ...updates,
        if (fullName.isNotEmpty) 'fullName': fullName,
        'updatedAt': _nowIso(),
      });
      if (!res.containsKey('error')) updated = true;
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final payload = <String, dynamic>{
          ...updates,
          if (fullName.isNotEmpty) 'fullName': fullName,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        payload.remove('userId');
        payload.remove('createdAt');
        await db
            .collection('users')
            .doc(userId)
            .set(payload, SetOptions(merge: true));
        updated = true;
      }
    } catch (_) {}

    // 3. Local cache
    try {
      await OfflineService.saveUserOffline(lvl, {
        ...updates,
        'userId': userId,
        'id': userId,
        if (fullName.isNotEmpty) 'fullName': fullName,
      });
      updated = true;
    } catch (_) {}

    return updated;
  }

  static Future<bool> deleteUser(String userIdOrEmail) async {
    final target = userIdOrEmail.trim();
    if (target.isEmpty) return false;
    bool deleted = false;

    // 1. REST API
    try {
      final res = await ApiService.adminDeleteUser(target);
      if (!res.containsKey('error')) deleted = true;
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        try {
          await db.collection('users').doc(target).update({
            'status': 'deleted',
            'deletedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          deleted = true;
        } catch (_) {}
        final snap = await db.collection('users').get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final uEmail = (d['email'] ?? '').toString().toLowerCase();
          final uUnique = (d['uniqueId'] ?? '').toString();
          if (doc.id == target ||
              uEmail == target.toLowerCase() ||
              uUnique == target) {
            await db.collection('users').doc(doc.id).update({
              'status': 'deleted',
              'deletedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            deleted = true;
          }
        }
      }
    } catch (_) {}

    // 3. Local cache
    for (final lvl in ['low', 'medium', 'high']) {
      try {
        final users = await OfflineService.getCachedUsers(lvl);
        users.removeWhere((u) {
          final id = (u['userId'] ?? u['id'] ?? '').toString();
          final email = (u['email'] ?? '').toString().toLowerCase();
          final uniqueId = (u['uniqueId'] ?? '').toString();
          return id == target ||
              email == target.toLowerCase() ||
              uniqueId == target;
        });
        await OfflineService.cacheUsers(lvl, users);
        deleted = true;
      } catch (_) {}
    }
    return deleted;
  }

  static Future<bool> suspendUser(String userId) async {
    bool done = false;
    try {
      await ApiService.adminSuspendUser(userId);
      done = true;
    } catch (_) {}
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('users').doc(userId).set({
          'status': 'suspended',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        done = true;
      }
    } catch (_) {}
    return done;
  }

  static Future<bool> activateUser(String userId) async {
    bool done = false;
    try {
      await ApiService.adminActivateUser(userId);
      done = true;
    } catch (_) {}
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('users').doc(userId).set({
          'status': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        done = true;
      }
    } catch (_) {}
    return done;
  }

  // ════════════════════════════════════════════════════════════════
  // DRAW HISTORY
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> saveDrawResult({
    required String equbLevel,
    required String adminId,
    required String winnerId,
    required String winnerName,
    required String winnerUniqueId,
    required int drawNumber,
    required List<String> participantIds,
  }) async {
    final nowIso = _nowIso();
    final drawData = <String, dynamic>{
      'equbLevel': equbLevel,
      'level': equbLevel,
      'adminId': adminId,
      'winnerId': winnerId,
      'winnerName': winnerName,
      'winnerUniqueId': winnerUniqueId,
      'drawNumber': drawNumber,
      'participants': participantIds,
      'totalParticipants': participantIds.length,
      'createdAt': nowIso,
      'status': 'completed',
    };
    String? firestoreDocId;

    // 1. Firestore SDK (direct write — primary on Android/iOS)
    try {
      final db = _maybeDb;
      if (db != null) {
        final ref = await db.collection('draws').add({
          ...drawData,
          'createdAtTimestamp': FieldValue.serverTimestamp(),
        });
        firestoreDocId = ref.id;
        if (winnerId.isNotEmpty) {
          await db.collection('users').doc(winnerId).set({
            'hasWon': true,
            'status': 'selected',
            'lastWinDate': nowIso,
            'updatedAt': nowIso,
            'participationHistory': FieldValue.arrayUnion([
              {'drawNumber': drawNumber, 'date': nowIso, 'level': equbLevel}
            ]),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('[saveDrawResult SDK] $e');
    }

    // 2. REST API background sync (fire-and-forget)
    Future.microtask(() async {
      try {
        await ApiService.adminRunDraw(equbLevel);
      } catch (_) {}
    });

    // 3. Update user via REST API too so backend store is consistent
    if (winnerId.isNotEmpty) {
      Future.microtask(() async {
        try {
          await ApiService.adminUpdateUser(winnerId, {
            'hasWon': true,
            'status': 'selected',
            'lastWinDate': nowIso,
            'updatedAt': nowIso,
          });
        } catch (_) {}
      });
    }

    return <String, dynamic>{
      ...drawData,
      'drawId':
          firestoreDocId ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  static Future<List<Map<String, dynamic>>> getDrawHistory(
      String level) async {
    final targetLevel = level.toLowerCase().replaceAll('equb_', '').trim();
    final List<Map<String, dynamic>> rawList = [];
    final Set<String> seenKeys = {};

    // 1. Firestore SDK — PRIMARY (direct, fast on real phone)
    try {
      final db = _maybeDb;
      if (db != null) {
        // Try equbLevel field first
        final snap1 = await db.collection('draws')
            .where('equbLevel', isEqualTo: targetLevel).get();
        for (final doc in snap1.docs) {
          rawList.add({...doc.data(), 'drawId': doc.id});
        }
        // Also try legacy level field
        if (rawList.isEmpty) {
          final snap2 = await db.collection('draws')
              .where('level', isEqualTo: targetLevel).get();
          for (final doc in snap2.docs) {
            rawList.add({...doc.data(), 'drawId': doc.id});
          }
        }
      }
    } catch (_) {
      // Full collection scan fallback
      try {
        final db = _maybeDb;
        if (db != null) {
          final snap = await db.collection('draws').get();
          for (final doc in snap.docs) {
            final data = doc.data();
            final docLevel = (data['equbLevel'] ?? data['level'] ?? '')
                .toString().toLowerCase().replaceAll('equb_', '').trim();
            if (docLevel == targetLevel) rawList.add({...data, 'drawId': doc.id});
          }
        }
      } catch (_) {}
    }

    // 2. REST API (when Firestore SDK unavailable — Linux desktop)
    if (rawList.isEmpty) {
      try {
        final list = await ApiService.adminGetDrawHistory(targetLevel)
            .timeout(const Duration(seconds: 6));
        for (final item in list) {
          final m = Map<String, dynamic>.from(item as Map);
          final docLevel = (m['equbLevel'] ?? m['level'] ?? targetLevel)
              .toString().toLowerCase().replaceAll('equb_', '').trim();
          if (docLevel == targetLevel) rawList.add(m);
        }
      } catch (_) {}
    }

    // 3. Reconstruct from users with hasWon=true
    if (rawList.isEmpty) {
      try {
        final users = await getUsersByLevel(targetLevel);
        int ctr = 1;
        for (final u in users) {
          if (u['hasWon'] == true || u['status'] == 'winner' || u['status'] == 'selected') {
            rawList.add({
              'drawId': 'user_win_${u['userId'] ?? u['id']}',
              'equbLevel': targetLevel,
              'winnerId': (u['userId'] ?? u['id'] ?? '').toString(),
              'winnerName': u['fullName'] ?? u['firstName'] ?? 'Winner',
              'winnerUniqueId': u['uniqueId'] ?? (u['userId'] ?? u['id'] ?? '').toString(),
              'drawNumber': ctr++,
              'createdAt': u['lastWinDate'] ?? u['updatedAt'] ?? _nowIso(),
              'status': 'completed',
            });
          }
        }
      } catch (_) {}
    }

    // Deduplicate & sort
    final List<Map<String, dynamic>> cleanList = [];
    for (final item in rawList) {
      final key =
          '${(item['winnerUniqueId'] ?? item['winnerId'] ?? '')}_${item['drawNumber'] ?? 1}';
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        cleanList.add(item);
      }
    }
    cleanList.sort((a, b) => (b['createdAt']?.toString() ?? '')
        .compareTo(a['createdAt']?.toString() ?? ''));
    return cleanList;
  }

  static Future<List<Map<String, dynamic>>> getAllDrawHistory() async {
    final List<Map<String, dynamic>> result = [];
    for (final lvl in ['low', 'medium', 'high']) {
      result.addAll(await getDrawHistory(lvl));
    }
    result.sort((a, b) =>
        (b['createdAt']?.toString() ?? '')
            .compareTo(a['createdAt']?.toString() ?? ''));
    return result;
  }

  static Future<bool> deleteDrawHistory({
    required String drawId,
    required String winnerId,
    required String winnerUniqueId,
    required String level,
  }) async {
    final targetLevel = level.toLowerCase().replaceAll('equb_', '').trim();
    bool deleted = false;

    // 1. REST API
    try {
      final res = await ApiService.deleteDrawHistory(drawId, targetLevel);
      if (!res.containsKey('error')) deleted = true;
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        if (drawId.isNotEmpty && !drawId.startsWith('user_win_')) {
          await db.collection('draws').doc(drawId).delete();
          deleted = true;
        }
        if (winnerId.isNotEmpty) {
          try {
            await db.collection('users').doc(winnerId).update({
              'hasWon': false,
              'status': 'active',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }
        if (winnerUniqueId.isNotEmpty) {
          final uDocs = await db
              .collection('users')
              .where('uniqueId', isEqualTo: winnerUniqueId)
              .get();
          for (final uDoc in uDocs.docs) {
            await db.collection('users').doc(uDoc.id).update({
              'hasWon': false,
              'status': 'active',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        deleted = true;
      }
    } catch (_) {}

    // 3. Reset user via REST API too
    if (winnerId.isNotEmpty) {
      Future.microtask(() async {
        try {
          await ApiService.adminUpdateUser(winnerId, {
            'hasWon': false,
            'status': 'active',
            'updatedAt': _nowIso(),
          });
        } catch (_) {}
      });
    }

    // 4. Local cache cleanup
    try {
      final cachedHistory = await OfflineService.getCachedDrawHistory(targetLevel);
      cachedHistory.removeWhere((item) {
        final dId = (item['drawId'] ?? item['id'] ?? '').toString();
        final wId = (item['winnerId'] ?? item['winnerUniqueId'] ?? '').toString();
        final wUid = (item['winnerUniqueId'] ?? item['winnerId'] ?? '').toString();
        return dId == drawId ||
            (winnerId.isNotEmpty && wId == winnerId) ||
            (winnerUniqueId.isNotEmpty && wUid == winnerUniqueId);
      });
      await OfflineService.cacheDrawHistory(targetLevel, cachedHistory);
      final cachedUsers = await OfflineService.getCachedUsers(targetLevel);
      for (final u in cachedUsers) {
        final uId = (u['userId'] ?? u['id'] ?? '').toString();
        final uUniq = (u['uniqueId'] ?? '').toString();
        if ((winnerId.isNotEmpty && uId == winnerId) ||
            (winnerUniqueId.isNotEmpty && uUniq == winnerUniqueId)) {
          u['hasWon'] = false;
          u['status'] = 'active';
        }
      }
      await OfflineService.cacheUsers(targetLevel, cachedUsers);
    } catch (_) {}

    return deleted;
  }

  // ════════════════════════════════════════════════════════════════
  // PAYMENTS
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> submitPayment(
      Map<String, dynamic> data) async {
    // 1. REST API
    try {
      final res = await ApiService.submitEqubPayment(data);
      if (res['success'] == true || res['paymentId'] != null) return res;
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final ref = await db.collection('payments').add({
          ...data,
          'status': 'pending_verification',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return {
          'success': true,
          'paymentId': ref.id,
          'message': 'Payment submitted. Waiting for admin verification.',
        };
      }
    } catch (e) {
      debugPrint('[submitPayment SDK] $e');
    }

    // 3. Offline queue
    await OfflineService.queueOfflinePayment(data);
    return {
      'success': true,
      'paymentId': 'offline_${DateTime.now().millisecondsSinceEpoch}',
      'message': 'Payment saved offline — will sync when connected.',
    };
  }

  static Future<List<Map<String, dynamic>>> getPaymentsByLevel(
      String level) async {
    final targetLevel = level.toLowerCase().replaceAll('equb_', '').trim();

    // 1. Firestore SDK — PRIMARY (direct cloud)
    try {
      final db = _maybeDb;
      if (db != null) {
        final List<Map<String, dynamic>> list = [];
        final Set<String> seen = {};
        if (targetLevel == 'all') {
          final snap = await db.collection('payments').get();
          for (final d in snap.docs) {
            list.add(<String, dynamic>{'paymentId': d.id, 'id': d.id, ...d.data()});
          }
        } else {
          for (final field in ['equbLevel', 'level']) {
            final snap = await db.collection('payments')
                .where(field, isEqualTo: targetLevel).get();
            for (final d in snap.docs) {
              if (!seen.contains(d.id)) {
                seen.add(d.id);
                list.add(<String, dynamic>{'paymentId': d.id, 'id': d.id, ...d.data()});
              }
            }
          }
        }
        list.sort((a, b) => (b['createdAt']?.toString() ?? '')
            .compareTo(a['createdAt']?.toString() ?? ''));
        await OfflineService.cachePayments(targetLevel, list);
        return list;
      }
    } catch (_) {}

    // 2. REST API (fallback)
    try {
      final apiRes = await ApiService.getPaymentsByLevel(targetLevel)
          .timeout(const Duration(seconds: 6));
      if (apiRes.isNotEmpty) {
        final list = apiRes.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        await OfflineService.cachePayments(targetLevel, list);
        return list;
      }
    } catch (_) {}

    // 3. Cache
    return await OfflineService.getCachedPayments(targetLevel);
  }

  static Future<bool> verifyPayment({
    required String paymentId,
    required String status,
    String rejectionReason = '',
    String adminId = 'admin',
    String level = 'low',
  }) async {
    // 1. REST API
    try {
      final res = await ApiService.verifyPayment({
        'paymentId': paymentId,
        'status': status,
        'rejectionReason': rejectionReason,
        'adminId': adminId,
      });
      if (res['success'] == true) return true;
    } catch (_) {}

    // 2. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final docRef = db.collection('payments').doc(paymentId);
        final snap = await docRef.get();
        if (snap.exists) {
          await docRef.update({
            'status': status,
            'rejectionReason': rejectionReason,
            'verifiedByAdminId': adminId,
            'verifiedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return true;
        }
      }
    } catch (_) {}

    // 3. Offline queue
    await OfflineService.queueOfflineVerification(
      paymentId: paymentId,
      status: status,
      rejectionReason: rejectionReason,
      adminId: adminId,
      level: level,
    );
    return true;
  }

  // ════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════

  static Map<String, dynamic> _defaultPermissions(String level) => {
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
        'canExportData': level == 'medium' || level == 'high',
        'canManageAdmins': false,
      };
}
