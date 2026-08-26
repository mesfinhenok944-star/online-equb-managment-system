import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'offline_service.dart';
import 'firestore_direct_service.dart';

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

    // 1. FirestoreDirectService -- service account JWT, bypasses rules
    try {
      final list = await FirestoreDirectService.getAdmins(level: level);
      for (final m in list) {
        final id = (m['adminId'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty && !seenIds.contains(id)) {
          results.add(m); seenIds.add(id);
        }
      }
      if (results.isNotEmpty) {
        debugPrint('[getAdmins] FirestoreDirect→${results.length}');
        OfflineService.cacheAdmins(results);
        return results;
      }
    } catch (e) { debugPrint('[getAdmins] FirestoreDirect error: $e'); }

    // 2. Firestore SDK (works if rules are open)
    try {
      final db = _maybeDb;
      if (db != null) {
        final snap = await db.collection('admins').get()
            .timeout(const Duration(seconds: 8));
        for (final doc in snap.docs) {
          final data = doc.data();
          if ((data['status'] ?? 'active') == 'deleted') continue;
          final aLvl = (data['level'] ?? data['equbLevel'] ?? 'low')
              .toString().toLowerCase().replaceAll('equb_', '');
          if (level == null || level == 'all' || aLvl == level!.toLowerCase()) {
            final item = <String, dynamic>{...data, 'adminId': doc.id, 'id': doc.id};
            if (!seenIds.contains(doc.id)) { results.add(item); seenIds.add(doc.id); }
          }
        }
        if (results.isNotEmpty) {
          OfflineService.cacheAdmins(results);
          return results;
        }
      }
    } catch (e) { debugPrint('[getAdmins] Firestore error: $e'); }

    // 3. REST API backend
    try {
      final list = await ApiService.superAdminGetAdmins(level: level);
      for (final item in list) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['adminId'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty && !seenIds.contains(id)) { results.add(m); seenIds.add(id); }
      }
      if (results.isNotEmpty) {
        OfflineService.cacheAdmins(results);
        return results;
      }
    } catch (_) {}

    // 4. Offline cache
    try {
      final cached = await OfflineService.getCachedAdmins();
      for (final a in cached) {
        final id = (a['adminId'] ?? a['id'] ?? '').toString();
        final aLvl = (a['level'] ?? a['equbLevel'] ?? 'low').toString().toLowerCase();
        if ((level == null || level == 'all' || aLvl == level!.toLowerCase()) &&
            !seenIds.contains(id)) { results.add(a); seenIds.add(id); }
      }
    } catch (_) {}

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

    // 1. FirestoreDirectService — service account JWT, bypasses rules, no server needed
    try {
      final list = await FirestoreDirectService.getUsersByLevel(lvlLower);
      for (final m in list) {
        final id = (m['userId'] ?? m['id'] ?? '').toString();
        if ((m['status'] ?? 'active').toString() == 'deleted' || id.isEmpty || seenIds.contains(id)) continue;
        results.add(m);
        seenIds.add(id);
      }
      if (results.isNotEmpty) {
        debugPrint('[getUsersByLevel] FirestoreDirect→${results.length} for $lvlLower');
        await OfflineService.cacheUsers(lvlLower, results);
        return results;
      }
    } catch (e) { debugPrint('[getUsersByLevel] FirestoreDirect error: $e'); }

    // 2. REST API backend (server running + tunnel up)
    try {
      final list = await ApiService.adminGetUsers(level: lvlLower)
          .timeout(const Duration(seconds: 8));
      for (final item in list) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['userId'] ?? m['id'] ?? '').toString();
        if ((m['status'] ?? 'active').toString() == 'deleted' || id.isEmpty || seenIds.contains(id)) continue;
        results.add(m);
        seenIds.add(id);
      }
      if (results.isNotEmpty) {
        debugPrint('[getUsersByLevel] REST→${results.length} for $lvlLower');
        await OfflineService.cacheUsers(lvlLower, results);
        return results;
      }
    } catch (e) { debugPrint('[getUsersByLevel] REST error: $e'); }

    // 3. Firestore SDK (works when rules are open)
    try {
      final db = _maybeDb;
      if (db != null) {
        for (final field in ['equbLevel', 'level']) {
          final snap = await db.collection('users')
              .where(field, isEqualTo: lvlLower)
              .get().timeout(const Duration(seconds: 8));
          for (final d in snap.docs) {
            if (seenIds.contains(d.id)) continue;
            final data = d.data();
            if ((data['status'] ?? 'active').toString() == 'deleted') continue;
            results.add({...data, 'userId': d.id, 'id': d.id});
            seenIds.add(d.id);
          }
          if (results.isNotEmpty) break;
        }
        if (results.isNotEmpty) {
          debugPrint('[getUsersByLevel] Firestore→${results.length} for $lvlLower');
          await OfflineService.cacheUsers(lvlLower, results);
          return results;
        }
      }
    } catch (e) { debugPrint('[getUsersByLevel] Firestore error: $e'); }

    // 4. Offline cache (last resort)
    try {
      final cached = await OfflineService.getCachedUsers(lvlLower);
      for (final u in cached) {
        final id = (u['userId'] ?? u['id'] ?? '').toString();
        if ((u['status'] ?? 'active').toString() == 'deleted' || id.isEmpty || seenIds.contains(id)) continue;
        results.add(u); seenIds.add(id);
      }
      debugPrint('[getUsersByLevel] cache→${results.length} for $lvlLower');
    } catch (_) {}
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

    // ── 0. FirestoreDirectService — service account JWT, bypasses rules ───────
    // PRIMARY on real Android phone (no server, works on any network)
    try {
      final now2 = _nowIso();
      // Check for existing user with same email
      if (email.isNotEmpty) {
        final existing = await FirestoreDirectService.getUsersByLevel(equbLevel);
        final dup = existing.where((u) =>
            (u['email'] ?? '').toString().toLowerCase() == email).toList();
        if (dup.isNotEmpty) {
          final docId = (dup.first['userId'] ?? dup.first['id'] ?? '').toString();
          if (docId.isNotEmpty) {
            final ok = await FirestoreDirectService.updateDocument('users', docId, {
              ...userData,
              'updatedAt': now2,
            });
            if (ok) {
              await OfflineService.saveUserOffline(equbLevel, {...userData, 'userId': docId, 'id': docId});
              return {'success': true, 'id': docId, 'message': 'User updated. ተጠቃሚ ተሻሽሏል።'};
            }
          }
        }
      }
      // Check uniqueId uniqueness
      if (uniqueId.isNotEmpty) {
        final taken = await isUniqueIdTaken(uniqueId);
        if (taken) return {'success': false, 'error': 'Unique ID "$uniqueId" is already registered. / ልዩ መታወቂያ ቀድሞ ተምዝግቧል።'};
      }
      // Add new user
      final newId = await FirestoreDirectService.addDocument('users', {...userData, 'createdAt': now2});
      if (newId != null) {
        final cacheData = {...userData, 'userId': newId, 'id': newId};
        await OfflineService.saveUserOffline(equbLevel, cacheData);
        debugPrint('[createUser] FirestoreDirect ✅ $newId');
        return {'success': true, 'id': newId, 'message': 'User registered. ተጠቃሚ ተመዝግቧል።'};
      }
    } catch (e) { debugPrint('[createUser] FirestoreDirect error: $e'); }

    // ── 1. Firestore SDK (PRIMARY on real Android/iOS — direct cloud write) ─
    // ── 1. Firestore SDK (PRIMARY on real Android/iOS — direct cloud write) ─
    // ── 0. FirestoreDirectService — service account JWT, bypasses rules ───────
    // PRIMARY on real Android phone (no server, works on any network)
    try {
      final now2 = _nowIso();
      // Check for existing user with same email
      if (email.isNotEmpty) {
        final existing = await FirestoreDirectService.getUsersByLevel(equbLevel);
        final dup = existing.where((u) =>
            (u['email'] ?? '').toString().toLowerCase() == email).toList();
        if (dup.isNotEmpty) {
          final docId = (dup.first['userId'] ?? dup.first['id'] ?? '').toString();
          if (docId.isNotEmpty) {
            final ok = await FirestoreDirectService.updateDocument('users', docId, {
              ...userData,
              'updatedAt': now2,
            });
            if (ok) {
              await OfflineService.saveUserOffline(equbLevel, {...userData, 'userId': docId, 'id': docId});
              return {'success': true, 'id': docId, 'message': 'User updated. ተጠቃሚ ተሻሽሏል።'};
            }
          }
        }
      }
      // Check uniqueId uniqueness
      if (uniqueId.isNotEmpty) {
        final taken = await isUniqueIdTaken(uniqueId);
        if (taken) return {'success': false, 'error': 'Unique ID "$uniqueId" is already registered. / ልዩ መታወቂያ ቀድሞ ተምዝግቧል።'};
      }
      // Add new user
      final newId = await FirestoreDirectService.addDocument('users', {...userData, 'createdAt': now2});
      if (newId != null) {
        final cacheData = {...userData, 'userId': newId, 'id': newId};
        await OfflineService.saveUserOffline(equbLevel, cacheData);
        debugPrint('[createUser] FirestoreDirect ✅ $newId');
        return {'success': true, 'id': newId, 'message': 'User registered. ተጠቃሚ ተመዝግቧል።'};
      }
    } catch (e) { debugPrint('[createUser] FirestoreDirect error: $e'); }

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
    if (userId.isEmpty) return false;
    final firstName  = (updates['firstName']  ?? '').toString().trim();
    final middleName = (updates['middleName'] ?? '').toString().trim();
    final lastName   = (updates['lastName']   ?? '').toString().trim();
    final fullName = '$firstName $middleName $lastName'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lvl = (updates['equbLevel'] ?? updates['level'] ?? 'low').toString().toLowerCase();
    final payload = <String, dynamic>{
      ...updates,
      if (fullName.isNotEmpty) 'fullName': fullName,
      'updatedAt': _nowIso(),
    };
    payload.remove('userId'); payload.remove('createdAt');

    // 1. FirestoreDirectService — JWT bypasses rules
    try {
      final ok = await FirestoreDirectService.updateDocument('users', userId, payload);
      if (ok) {
        await OfflineService.saveUserOffline(lvl, {...payload, 'userId': userId, 'id': userId});
        debugPrint('[updateUser] FirestoreDirect OK');
        return true;
      }
    } catch (e) { debugPrint('[updateUser] FirestoreDirect: $e'); }

    // 2. REST API
    try {
      final res = await ApiService.adminUpdateUser(userId, payload);
      if (!res.containsKey('error')) {
        await OfflineService.saveUserOffline(lvl, {...payload, 'userId': userId, 'id': userId});
        return true;
      }
    } catch (_) {}

    // 3. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('users').doc(userId).set({...payload, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        return true;
      }
    } catch (_) {}

    // 4. Cache only
    await OfflineService.saveUserOffline(lvl, {...payload, 'userId': userId, 'id': userId});
    return true;
  }

  static Future<bool> deleteUser(String userIdOrEmail) async {
    final target = userIdOrEmail.trim();
    if (target.isEmpty) return false;
    bool deleted = false;
    final now = _nowIso();

    // 1. FirestoreDirectService — JWT bypasses rules (PRIMARY on phone)
    try {
      // Try direct doc ID first
      final ok = await FirestoreDirectService.updateDocument('users', target,
          {'status': 'deleted', 'deletedAt': now, 'updatedAt': now});
      if (ok) { deleted = true; debugPrint('[deleteUser] FirestoreDirect OK (by id)'); }
      
      if (!deleted) {
        // Search by email / uniqueId across levels
        for (final lvl in ['low', 'medium', 'high']) {
          final users = await FirestoreDirectService.getUsersByLevel(lvl);
          for (final u in users) {
            final uId     = (u['userId'] ?? u['id'] ?? '').toString();
            final uEmail  = (u['email']    ?? '').toString().toLowerCase();
            final uUnique = (u['uniqueId'] ?? '').toString();
            if (uId == target || uEmail == target.toLowerCase() || uUnique == target) {
              if (uId.isNotEmpty) {
                await FirestoreDirectService.updateDocument('users', uId,
                    {'status': 'deleted', 'deletedAt': now, 'updatedAt': now});
                deleted = true;
                debugPrint('[deleteUser] FirestoreDirect OK (found by search)');
              }
            }
          }
        }
      }
    } catch (e) { debugPrint('[deleteUser] FirestoreDirect: $e'); }

    // 2. REST API
    if (!deleted) {
      try {
        final res = await ApiService.adminDeleteUser(target);
        if (!res.containsKey('error')) deleted = true;
      } catch (_) {}
    }

    // 3. Firestore SDK
    if (!deleted) {
      try {
        final db = _maybeDb;
        if (db != null) {
          await db.collection('users').doc(target).update({'status': 'deleted', 'deletedAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
          deleted = true;
        }
      } catch (_) {}
    }

    // 4. Remove from local cache
    for (final lvl in ['low', 'medium', 'high']) {
      try {
        final users = await OfflineService.getCachedUsers(lvl);
        users.removeWhere((u) {
          final id = (u['userId'] ?? u['id'] ?? '').toString();
          final em = (u['email'] ?? '').toString().toLowerCase();
          final un = (u['uniqueId'] ?? '').toString();
          return id == target || em == target.toLowerCase() || un == target;
        });
        await OfflineService.cacheUsers(lvl, users);
      } catch (_) {}
    }

    return deleted;
  }

  static Future<bool> suspendUser(String userId) async {
    if (userId.isEmpty) return false;
    final now = _nowIso();
    
    // 1. FirestoreDirectService
    try {
      final ok = await FirestoreDirectService.updateDocument('users', userId,
          {'status': 'suspended', 'suspendedAt': now, 'updatedAt': now});
      if (ok) { debugPrint('[suspendUser] FirestoreDirect OK'); return true; }
    } catch (e) { debugPrint('[suspendUser] FirestoreDirect: $e'); }

    // 2. REST API
    try { await ApiService.adminSuspendUser(userId); return true; } catch (_) {}

    // 3. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('users').doc(userId).set({'status': 'suspended', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> activateUser(String userId) async {
    if (userId.isEmpty) return false;
    final now = _nowIso();

    // 1. FirestoreDirectService
    try {
      final ok = await FirestoreDirectService.updateDocument('users', userId,
          {'status': 'active', 'updatedAt': now});
      if (ok) { debugPrint('[activateUser] FirestoreDirect OK'); return true; }
    } catch (e) { debugPrint('[activateUser] FirestoreDirect: $e'); }

    // 2. REST API
    try { await ApiService.adminActivateUser(userId); return true; } catch (_) {}

    // 3. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        await db.collection('users').doc(userId).set({'status': 'active', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        return true;
      }
    } catch (_) {}
    return false;
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
      'equbLevel':         equbLevel,
      'level':             equbLevel,
      'adminId':           adminId,
      'winnerId':          winnerId,
      'winnerName':        winnerName,
      'winnerUniqueId':    winnerUniqueId,
      'drawNumber':        drawNumber,
      'totalParticipants': participantIds.length,
      'createdAt':         nowIso,
      'status':            'completed',
    };
    String? firestoreDocId;

    // ── 1. FirestoreDirectService — service account JWT, bypasses rules ─────
    // PRIMARY: This is the only path that reliably works on real Android phone.
    try {
      // Save draw record to draws collection
      firestoreDocId = await FirestoreDirectService.addDocument('draws', {
        ...drawData,
        'participants': participantIds.join(','),
      });
      debugPrint('[saveDrawResult] FirestoreDirect draw: $firestoreDocId');

      // Mark winner hasWon=true, status=selected in users collection
      if (winnerId.isNotEmpty) {
        final ok = await FirestoreDirectService.updateDocument(
          'users', winnerId,
          {
            'hasWon':      true,
            'status':      'selected',
            'lastWinDate': nowIso,
            'updatedAt':   nowIso,
          },
        );
        debugPrint('[saveDrawResult] FirestoreDirect winner marked hasWon=true: $ok');
      }
    } catch (e) {
      debugPrint('[saveDrawResult] FirestoreDirect error: $e');
    }

    // ── 2. Firestore SDK fallback (when rules are open / emulator) ───────────
    if (firestoreDocId == null) {
      try {
        final db = _maybeDb;
        if (db != null) {
          final ref = await db.collection('draws').add({
            ...drawData,
            'participants': participantIds,
            'createdAtTimestamp': FieldValue.serverTimestamp(),
          });
          firestoreDocId = ref.id;
          if (winnerId.isNotEmpty) {
            await db.collection('users').doc(winnerId).set({
              'hasWon': true,
              'status': 'selected',
              'lastWinDate': nowIso,
              'updatedAt': nowIso,
            }, SetOptions(merge: true));
          }
          debugPrint('[saveDrawResult] Firestore SDK draw: $firestoreDocId');
        }
      } catch (e) { debugPrint('[saveDrawResult SDK] $e'); }
    }

    // ── 3. REST API — fire-and-forget background sync ────────────────────────
    Future.microtask(() async {
      try {
        if (winnerId.isNotEmpty) {
          await ApiService.adminUpdateUser(winnerId, {
            'hasWon': true, 'status': 'selected',
            'lastWinDate': nowIso, 'updatedAt': nowIso,
          });
        }
      } catch (_) {}
    });

    return <String, dynamic>{
      ...drawData,
      'drawId': firestoreDocId ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  static Future<List<Map<String, dynamic>>> getDrawHistory(
      String level) async {
    final targetLevel = level.toLowerCase().replaceAll('equb_', '').trim();
    final List<Map<String, dynamic>> rawList = [];
    final Set<String> seenKeys = {};

    // 1. FirestoreDirectService — service account JWT, bypasses rules
    try {
      final list = await FirestoreDirectService.getDrawHistory(targetLevel);
      rawList.addAll(list);
      if (rawList.isNotEmpty) {
        debugPrint('[getDrawHistory] FirestoreDirect→${rawList.length} for $targetLevel');
      }
    } catch (e) { debugPrint('[getDrawHistory] FirestoreDirect error: $e'); }

    // 2. REST API backend
    if (rawList.isEmpty) {
      try {
        final list = await ApiService.adminGetDrawHistory(targetLevel)
            .timeout(const Duration(seconds: 8));
        rawList.addAll(list.map((e) => Map<String, dynamic>.from(e as Map)));
        debugPrint('[getDrawHistory] REST→${rawList.length} for $targetLevel');
      } catch (e) { debugPrint('[getDrawHistory] REST error: $e'); }
    }

    // 3. Firestore SDK (open rules)
    if (rawList.isEmpty) {
      try {
        final db = _maybeDb;
        if (db != null) {
          for (final field in ['equbLevel', 'level']) {
            final snap = await db.collection('draws')
                .where(field, isEqualTo: targetLevel)
                .get().timeout(const Duration(seconds: 8));
            for (final doc in snap.docs) rawList.add({...doc.data(), 'drawId': doc.id});
            if (rawList.isNotEmpty) break;
          }
        }
      } catch (e) { debugPrint('[getDrawHistory] Firestore error: $e'); }
    }

    // 4. Reconstruct from users with hasWon=true
    if (rawList.isEmpty) {
      try {
        final users = await getUsersByLevel(targetLevel);
        int ctr = 1;
        for (final u in users) {
          if (u['hasWon'] == true || u['status'] == 'selected') {
            rawList.add({
              'drawId': 'user_win_${u['userId'] ?? u['id']}',
              'equbLevel': targetLevel, 'level': targetLevel,
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
    final List<Map<String, dynamic>> clean = [];
    for (final item in rawList) {
      final key = '${item['winnerUniqueId'] ?? item['winnerId'] ?? ''}_${item['drawNumber'] ?? 0}';
      if (!seenKeys.contains(key)) { seenKeys.add(key); clean.add(item); }
    }
    clean.sort((a, b) =>
        (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));
    return clean;
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
    final now = _nowIso();
    final payload = <String, dynamic>{
      ...data,
      'status': 'pending_verification',
      'level': (data['equbLevel'] ?? data['level'] ?? 'low').toString().toLowerCase().replaceAll('equb_',''),
      'equbLevel': (data['equbLevel'] ?? data['level'] ?? 'low').toString().toLowerCase().replaceAll('equb_',''),
      'createdAt': now,
      'updatedAt': now,
    };

    // 1. REST API (backend uses Admin SDK, most reliable)
    try {
      final res = await ApiService.submitEqubPayment(payload);
      if (res['success'] == true || res['paymentId'] != null) {
        debugPrint('[submitPayment] REST ✅');
        return res;
      }
    } catch (e) { debugPrint('[submitPayment] REST error: $e'); }

    // 2. Firestore SDK (direct write)
    try {
      final db = _maybeDb;
      if (db != null) {
        final ref = await db.collection('payments').add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('[submitPayment] Firestore SDK ✅ ${ref.id}');
        return {'success': true, 'paymentId': ref.id, 'message': 'Payment submitted.'};
      }
    } catch (e) { debugPrint('[submitPayment SDK] $e'); }

    // 3. Offline queue
    await OfflineService.queueOfflinePayment(payload);
    return {'success': true, 'paymentId': 'offline_${DateTime.now().millisecondsSinceEpoch}',
            'message': 'Payment saved offline — will sync when connected.'};
  }

  static Future<List<Map<String, dynamic>>> getPaymentsByLevel(
      String level) async {
    final targetLevel = level.toLowerCase().replaceAll('equb_', '').trim();

    // 1. FirestoreDirectService — service account JWT, bypasses rules
    try {
      final list = await FirestoreDirectService.getPaymentsByLevel(targetLevel);
      if (list.isNotEmpty) {
        list.sort((a, b) => (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));
        await OfflineService.cachePayments(targetLevel, list);
        debugPrint('[getPaymentsByLevel] FirestoreDirect→${list.length} for $targetLevel');
        return list;
      }
    } catch (e) { debugPrint('[getPaymentsByLevel] FirestoreDirect error: $e'); }

    // 2. REST API backend
    try {
      final apiRes = await ApiService.getPaymentsByLevel(targetLevel)
          .timeout(const Duration(seconds: 8));
      if (apiRes.isNotEmpty) {
        final list = apiRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        list.sort((a, b) => (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));
        await OfflineService.cachePayments(targetLevel, list);
        debugPrint('[getPaymentsByLevel] REST→${list.length} for $targetLevel');
        return list;
      }
    } catch (e) { debugPrint('[getPaymentsByLevel] REST error: $e'); }

    // 3. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final List<Map<String, dynamic>> list = [];
        final Set<String> seen = {};
        for (final field in ['equbLevel', 'level']) {
          final snap = await db.collection('payments')
              .where(field, isEqualTo: targetLevel)
              .get().timeout(const Duration(seconds: 8));
          for (final d in snap.docs) {
            if (seen.contains(d.id)) continue;
            seen.add(d.id);
            list.add({'paymentId': d.id, 'id': d.id, ...d.data()});
          }
        }
        if (list.isNotEmpty) {
          list.sort((a, b) => (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));
          await OfflineService.cachePayments(targetLevel, list);
          return list;
        }
      }
    } catch (e) { debugPrint('[getPaymentsByLevel] Firestore error: $e'); }

    return await OfflineService.getCachedPayments(targetLevel);
  }

  static Future<bool> verifyPayment({
    required String paymentId,
    required String status,
    String rejectionReason = '',
    String adminId = 'admin',
    String level = 'low',
  }) async {
    final now = _nowIso();
    final updates = <String, dynamic>{
      'status': status == 'verified' ? 'verified' : 'rejected',
      'rejectionReason': rejectionReason,
      'verifiedByAdminId': adminId,
      'verifiedAt': now,
      'updatedAt': now,
    };

    // 1. FirestoreDirectService — JWT bypasses rules
    try {
      final token = await FirestoreDirectService.getAdminToken();
      if (token != null) {
        final url = 'https://firestore.googleapis.com/v1/projects/'
            'online-equb-managment-system/databases/(default)/documents/'
            'payments/$paymentId';
        // Build PATCH body
        final fields = <String, dynamic>{};
        updates.forEach((k, v) {
          if (v is String) fields[k] = {'stringValue': v};
          else if (v is bool) fields[k] = {'booleanValue': v};
          else if (v is int) fields[k] = {'integerValue': v.toString()};
        });
        final body = jsonEncode({'fields': fields});
        final resp = await (await _httpClientPatch(url, token, body));
        if (resp == 200) {
          debugPrint('[verifyPayment] FirestoreDirect ✅ $status');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[verifyPayment] FirestoreDirect error: $e');
    }

    // 2. REST API
    try {
      final res = await ApiService.verifyPayment({
        'paymentId': paymentId,
        'status': status,
        'rejectionReason': rejectionReason,
        'adminId': adminId,
      });
      if (res['success'] == true) return true;
    } catch (_) {}

    // 3. Firestore SDK
    try {
      final db = _maybeDb;
      if (db != null) {
        final docRef = db.collection('payments').doc(paymentId);
        final snap = await docRef.get();
        if (snap.exists) {
          await docRef.update({
            'status': status == 'verified' ? 'verified' : 'rejected',
            'rejectionReason': rejectionReason,
            'verifiedByAdminId': adminId,
            'verifiedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return true;
        }
      }
    } catch (_) {}

    // 4. Offline queue
    await OfflineService.queueOfflineVerification(
      paymentId: paymentId,
      status: status,
      rejectionReason: rejectionReason,
      adminId: adminId,
      level: level,
    );
    return true;
  }

  // HTTP PATCH helper using dart:io HttpClient
  static Future<int> _httpClientPatch(String url, String token, String body) async {
    try {
      final uri = Uri.parse(url + '?updateMask.fieldPaths=status'
          '&updateMask.fieldPaths=rejectionReason'
          '&updateMask.fieldPaths=verifiedByAdminId'
          '&updateMask.fieldPaths=verifiedAt'
          '&updateMask.fieldPaths=updatedAt');
      final client = HttpClient();
      final req = await client.patchUrl(uri);
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('Content-Type', 'application/json');
      req.write(body);
      final resp = await req.close();
      client.close();
      return resp.statusCode;
    } catch (_) {
      return 500;
    }
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
