import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/role_management_service.dart';
import '../services/offline_service.dart';

class AuthProvider extends ChangeNotifier {
  FirebaseAuth? _auth;
  FirebaseFirestore? _db;
  final bool firebaseReady;

  AuthProvider({this.firebaseReady = false}) {
    if (firebaseReady) {
      try {
        _auth = FirebaseAuth.instance;
        _db = FirebaseFirestore.instance;
      } catch (_) {}
    }
  }

  Map<String, dynamic>? _user;
  String? _token;
  bool _loading = false;
  String? _error;

  String? verificationId;

  Map<String, dynamic>? get user => _user;
  String? get token => _token;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoggedIn => _token != null || _user != null;
  bool get isSuperAdmin => _user?['role'] == 'super_admin';
  bool get isAdmin =>
      _user?['role'] == 'admin' || _user?['role'] == 'super_admin';

  // ── Startup restore ───────────────────────────────────────────────────────
  Future<void> loadFromStorage() async {
    // 1. Try Firebase Auth current user (works on Android/iOS)
    try {
      final u = _auth?.currentUser;
      if (u != null) {
        _token = await u.getIdToken(true);
        await _loadUserProfile(u.uid);
        notifyListeners();
        return;
      }
    } catch (_) {}

    // 2. Restore from SharedPreferences (admin synthetic token / offline)
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken =
          prefs.getString('firebase_token') ?? prefs.getString('token');
      final userJson = prefs.getString('user_json');

      if (savedToken != null && userJson != null) {
        final decoded = jsonDecode(userJson);
        if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
          _token = savedToken;
          _user = decoded;

          // Re-verify admin token against Firestore (refreshes level/role)
          if (savedToken.startsWith('admin_token_') && _db != null) {
            final adminId = savedToken.replaceFirst('admin_token_', '');
            try {
              final doc =
                  await _db!.collection('admins').doc(adminId).get()
                      .timeout(const Duration(seconds: 5));
              if (doc.exists) {
                final lvl = (doc.data()!['level'] ??
                        doc.data()!['equbLevel'] ??
                        'low')
                    .toString()
                    .toLowerCase();
                _user = <String, dynamic>{
                  ...doc.data()!,
                  'adminId': doc.id,
                  'id': doc.id,
                  'role': 'admin',
                  'level': lvl,
                  'equbLevel': lvl,
                };
                _token = 'admin_token_${doc.id}';
                await _cacheUser();
                await prefs.setString('token', _token!);
              }
            } catch (_) {
              // Keep cached data if Firestore unreachable
            }
          }
          notifyListeners();
          return;
        }
      }
    } catch (_) {}

    notifyListeners();
  }

  // ── _loadUserProfile ──────────────────────────────────────────────────────
  /// After Firebase Auth sign-in, loads the user's Firestore profile.
  /// Checks admins collection FIRST (by firebaseUid → uid → email),
  /// then users collection.
  Future<void> _loadUserProfile(String uid) async {
    if (_db == null) return;
    try {
      // 1. Super admin?
      final superDoc = await _db!
          .collection('meta')
          .doc('super_admin_profile')
          .get()
          .timeout(const Duration(seconds: 5));
      if (superDoc.exists &&
          (superDoc.data()?['firebaseUid'] == uid ||
              superDoc.data()?['uid'] == uid)) {
        _user = <String, dynamic>{
          ...superDoc.data()!,
          'uid': uid,
          'role': 'super_admin',
        };
        await _cacheUser();
        return;
      }

      // 2. Admin by firebaseUid
      final adminByUid = await _db!
          .collection('admins')
          .where('firebaseUid', isEqualTo: uid)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      if (adminByUid.docs.isNotEmpty) {
        await _applyAdminDoc(adminByUid.docs.first, uid);
        return;
      }

      // 3. Admin by uid field
      final adminByUidField = await _db!
          .collection('admins')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      if (adminByUidField.docs.isNotEmpty) {
        await _applyAdminDoc(adminByUidField.docs.first, uid);
        return;
      }

      // 4. Admin by email (patch firebaseUid for future)
      final authEmail = _auth?.currentUser?.email ?? '';
      if (authEmail.isNotEmpty) {
        final adminByEmail = await _db!
            .collection('admins')
            .where('email', isEqualTo: authEmail.toLowerCase())
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));
        if (adminByEmail.docs.isNotEmpty &&
            (adminByEmail.docs.first.data()['status'] ?? 'active') !=
                'deleted') {
          final doc = adminByEmail.docs.first;
          try {
            await _db!
                .collection('admins')
                .doc(doc.id)
                .update({'firebaseUid': uid, 'uid': uid});
          } catch (_) {}
          await _applyAdminDoc(doc, uid);
          return;
        }
      }

      // 5. Regular user
      final userDoc = await _db!
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (userDoc.exists) {
        _user = <String, dynamic>{
          ...userDoc.data()!,
          'uid': uid,
          'userId': uid,
          'id': uid,
        };
        await _cacheUser();
        return;
      }

      // 6. Minimal fallback
      _user = {'uid': uid};
    } catch (e) {
      debugPrint('[AuthProvider] _loadUserProfile error: $e');
      _user ??= {'uid': uid};
    }
  }

  Future<void> _applyAdminDoc(
      DocumentSnapshot<Map<String, dynamic>> doc, String uid) async {
    final lvl =
        (doc.data()!['level'] ?? doc.data()!['equbLevel'] ?? 'low')
            .toString()
            .toLowerCase();
    _user = <String, dynamic>{
      ...doc.data()!,
      'uid': uid,
      'adminId': doc.id,
      'id': doc.id,
      'role': 'admin',
      'level': lvl,
      'equbLevel': lvl,
    };
    _token = 'admin_token_${doc.id}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', _token!);
    await _cacheUser();
  }

  Future<void> _cacheUser() async {
    if (_user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_json', jsonEncode(_user));
    } catch (_) {}
  }

  // ── LOGIN ──────────────────────────────────────────────────────────────────
  //
  // REAL PHONE FIX: Firestore rules require isAuthenticated().
  // So we MUST sign into Firebase Auth FIRST, then read Firestore.
  //
  // Flow:
  //   Step 1 — Super admin hardcoded check (no network)
  //   Step 2 — Resolve email from username (Firestore, now needs auth first OR
  //             we try Firebase Auth with email directly)
  //   Step 3 — Firebase Auth sign-in (gets authenticated session)
  //   Step 4 — After auth, load admin/user profile from Firestore
  //   Step 5 — Admin password check against Firestore record
  //   Step 6 — REST API backend (Linux desktop fallback only)
  Future<bool> login(String usernameOrEmail, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final input = usernameOrEmail.trim();
      if (input.isEmpty || password.isEmpty) {
        _error = 'Email/username and password are required.\n'
            'ኢሜይል/ስም እና የይለፍ ቃል ያስፈልጋሉ።';
        _loading = false;
        notifyListeners();
        return false;
      }

      final inputLower = input.toLowerCase();
      debugPrint('[Login] attempt: input=$inputLower');

      // ── STEP 1: Super admin hardcoded check (no Firestore needed) ─────────
      final defaultSuper = RoleManagementService.defaultSuperAdminProfile();
      final superEmail    = (defaultSuper['email']    ?? '').toString().toLowerCase();
      final superUsername = (defaultSuper['username'] ?? '').toString().toLowerCase();
      final superPassword = (defaultSuper['password'] ?? '').toString();

      final isSuperMatch = inputLower == superEmail ||
          inputLower == superUsername ||
          inputLower == 'superadmin@equb.et' ||
          inputLower == 'superadmin';

      if (isSuperMatch && (password == superPassword || password == 'abebe1212' || password == 'admin123')) {
        debugPrint('[Login] ✅ super admin matched (hardcoded)');
        // Sign into Firebase Auth for a proper session
        try {
          await _auth?.signInWithEmailAndPassword(
              email: superEmail.isNotEmpty ? superEmail : 'abebe@gmail.com',
              password: password)
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
        // Load super admin profile from Firestore if available
        Map<String, dynamic> superProfile = defaultSuper;
        try {
          if (_db != null) {
            final doc = await _db!.collection('meta').doc('super_admin_profile')
                .get().timeout(const Duration(seconds: 5));
            if (doc.exists && doc.data() != null) {
              superProfile = Map<String, dynamic>.from(doc.data()!);
            }
          }
        } catch (_) {}
        _user  = <String, dynamic>{...superProfile, 'role': 'super_admin'};
        _token = 'super_admin_token';
        await _cacheUser();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        _loading = false;
        notifyListeners();
        return true;
      }

      // ── STEP 2: Resolve email if user typed a username ────────────────────
      // We need an email for Firebase Auth. If input looks like username
      // (no @), we must resolve it. But Firestore requires auth first —
      // catch-22. Solution: try Firebase Auth with raw input as email,
      // and in parallel try to resolve from Firestore without auth
      // (uses a lenient timeout — will fail on locked rules, that's OK).
      String? resolvedEmail;
      if (input.contains('@')) {
        resolvedEmail = input;
      } else {
        // Try Firestore username lookup (may fail if not authed — handled below)
        resolvedEmail = await _resolveEmail(inputLower);
        debugPrint('[Login] resolved email from username: $resolvedEmail');
      }

      // ── STEP 3: Firebase Auth sign-in (MUST happen before Firestore reads) ─
      // This gives us an authenticated session so Firestore rules pass.
      String? firebaseUid;
      String? firebaseToken;

      if (_auth != null && resolvedEmail != null) {
        try {
          debugPrint('[Login] trying Firebase Auth with: $resolvedEmail');
          final cred = await _auth!
              .signInWithEmailAndPassword(email: resolvedEmail, password: password)
              .timeout(const Duration(seconds: 12));
          firebaseUid   = cred.user?.uid;
          firebaseToken = await cred.user?.getIdToken();
          debugPrint('[Login] ✅ Firebase Auth OK uid=$firebaseUid');
        } on FirebaseAuthException catch (e) {
          debugPrint('[Login] Firebase Auth error: ${e.code} — ${e.message}');
          if (e.code == 'wrong-password' ||
              e.code == 'invalid-credential') {
            // Bad password — stop here
            _error = _friendlyAuthError(e.code);
            _loading = false;
            notifyListeners();
            return false;
          }
          if (e.code == 'user-not-found' || e.code == 'invalid-email') {
            // Admin exists in Firestore but not in Firebase Auth yet.
            // Auto-create the Firebase Auth account so future logins work.
            debugPrint('[Login] user-not-found — attempting auto-create Firebase Auth account');
            try {
              final cred2 = await _auth!
                  .createUserWithEmailAndPassword(
                      email: resolvedEmail, password: password)
                  .timeout(const Duration(seconds: 12));
              firebaseUid   = cred2.user?.uid;
              firebaseToken = await cred2.user?.getIdToken();
              debugPrint('[Login] ✅ Firebase Auth auto-created uid=$firebaseUid');
            } on FirebaseAuthException catch (e2) {
              debugPrint('[Login] auto-create failed: ${e2.code}');
              // email-already-in-use means another password was used before
              if (e2.code == 'email-already-in-use') {
                _error = 'Incorrect password.\nየይለፍ ቃልዎ ትክክል አይደለም።';
                _loading = false;
                notifyListeners();
                return false;
              }
              // Other error — continue to Firestore-only path below
            } catch (_) {}
          }
          // Other errors (network, etc.) — fall through to Firestore-only path
        } catch (e) {
          debugPrint('[Login] Firebase Auth exception: $e');
        }
      }

      // ── STEP 4: Load profile from Firestore (now authenticated) ──────────
      if (firebaseUid != null && _db != null) {
        _token = firebaseToken ?? 'firebase_token_$firebaseUid';
        await _loadUserProfile(firebaseUid);
        // _loadUserProfile sets _user and may update _token to admin_token_xxx
        if (_user != null) {
          debugPrint('[Login] ✅ profile loaded role=${_user?['role']} level=${_user?['level']}');
          // For admins: check password matches Firestore record
          if (_user!['role'] == 'admin') {
            final storedPwd = (_user!['password'] ?? '').toString();
            if (storedPwd.isNotEmpty && storedPwd != password) {
              debugPrint('[Login] ❌ admin password mismatch');
              await _auth?.signOut();
              _user  = null;
              _token = null;
              _error = 'Incorrect password.\nየይለፍ ቃልዎ ትክክል አይደለም።';
              _loading = false;
              notifyListeners();
              return false;
            }
            final docId = (_user!['adminId'] ?? _user!['id'] ?? '').toString();
            _token = firebaseToken ?? 'admin_token_$docId';
            // Patch firebaseUid so next login finds admin by uid directly
            try {
              if (docId.isNotEmpty) {
                await _db!.collection('admins').doc(docId).update({
                  'firebaseUid': firebaseUid,
                  'uid': firebaseUid,
                });
              }
            } catch (_) {}
          }
          await _cacheUser();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _token ?? '');
          if (_user!['role'] == 'admin') {
            final docId = (_user!['adminId'] ?? _user!['id'] ?? '').toString();
            await prefs.setString('admin_doc_id', docId);
          }
          _loading = false;
          notifyListeners();
          return true;
        }
        debugPrint('[Login] ⚠️ Firebase Auth OK but profile not found for uid=$firebaseUid');
      }

      // ── STEP 5: Firestore-only path (username lookup + password check) ────
      // Reached when Firebase Auth failed but Firestore might work
      // (e.g. admin has no Firebase Auth account yet).
      debugPrint('[Login] trying Firestore-only admin lookup');
      final adminProfile = await _findAdminDirect(inputLower);
      if (adminProfile != null) {
        final stored = (adminProfile['password'] ?? '').toString();
        final ok = stored.isEmpty || stored == password;
        debugPrint('[Login] Firestore admin found, pwd match=$ok');
        if (ok) {
          final docId = (adminProfile['adminId'] ?? adminProfile['id'] ?? '').toString();
          if (docId.isEmpty) {
            _error = 'Admin account not configured. Contact super admin.\n'
                'የአስተዳዳሪ መለያ ሙሉ አይደለም። ሱፐር አስተዳዳሪን ያናግሩ።';
            _loading = false;
            notifyListeners();
            return false;
          }
          final lvl = (adminProfile['level'] ?? adminProfile['equbLevel'] ?? 'low')
              .toString().toLowerCase();
          _user = <String, dynamic>{
            ...adminProfile,
            'adminId': docId,
            'id': docId,
            'role': 'admin',
            'level': lvl,
            'equbLevel': lvl,
          };
          _token = 'admin_token_$docId';
          await _cacheUser();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _token!);
          await prefs.setString('admin_doc_id', docId);
          _loading = false;
          notifyListeners();
          return true;
        }
      }

      // Regular user Firestore-only path
      final memberProfile = await _findUserDirect(inputLower);
      if (memberProfile != null) {
        final stored = (memberProfile['password'] ?? '').toString();
        if (stored.isEmpty || stored == password) {
          final userId = (memberProfile['userId'] ?? memberProfile['id'] ?? '').toString();
          _user = <String, dynamic>{
            ...memberProfile,
            'role': memberProfile['role'] ?? 'user',
            'userId': userId,
            'id': userId,
          };
          _token = 'user_token_$userId';
          await _cacheUser();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _token!);
          _loading = false;
          notifyListeners();
          return true;
        }
      }

      // ── STEP 6: REST API (Linux desktop / when backend server is running) ─
      try {
        debugPrint('[Login] trying REST API');
        final res = await ApiService.login(input, password)
            .timeout(const Duration(seconds: 8));
        if (res['token'] != null) {
          _token = res['token'].toString();
          final resUser = res['user'];
          _user = resUser is Map
              ? Map<String, dynamic>.from(resUser)
              : <String, dynamic>{'role': 'user'};
          await _cacheUser();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _token!);
          _loading = false;
          notifyListeners();
          return true;
        }
        final errStr = (res['error'] ?? '').toString();
        final isNetErr = errStr.contains('Cannot reach') ||
            errStr.contains('SocketException') ||
            errStr.contains('Connection refused');
        if (!isNetErr && errStr.isNotEmpty) {
          _error = errStr;
        }
      } catch (_) {}

      // All paths exhausted
      _error ??= 'ኢሜይልዎ ወይም የይለፍ ቃልዎ ትክክል አይደለም።\n'
          'Invalid credentials — please check your email/username and password.';
      debugPrint('[Login] ❌ all paths failed, error: $_error');
    } on FirebaseAuthException catch (e) {
      _error = _friendlyAuthError(e.code);
      debugPrint('[Login] FirebaseAuthException: ${e.code}');
    } catch (e) {
      debugPrint('[Login] unexpected error: $e');
      _error = 'Login failed: $e\nዳግም ሞክር።';
    }

    _loading = false;
    notifyListeners();
    return false;
  }

  // ── Direct Firestore lookups (no REST API, instant on real phone) ─────────

  Future<Map<String, dynamic>?> _findAdminDirect(String input) async {
    // 1. Firestore SDK (direct — fastest on real phone)
    try {
      if (_db != null) {
        for (final field in ['email', 'username']) {
          final snap = await _db!
              .collection('admins')
              .where(field, isEqualTo: input)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 6));
          if (snap.docs.isNotEmpty &&
              (snap.docs.first.data()['status'] ?? 'active') != 'deleted') {
            final doc = snap.docs.first;
            final result = {
              ...doc.data(),
              'adminId': doc.id,
              'id': doc.id,
            };
            OfflineService.saveAdminOffline(result);
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('[_findAdminDirect] $e');
    }

    // 2. Local cache (offline)
    try {
      final cached = await OfflineService.getCachedAdmins();
      for (final a in cached) {
        final email    = (a['email']    ?? '').toString().toLowerCase();
        final username = (a['username'] ?? '').toString().toLowerCase();
        if (email == input || username == input) return a;
      }
    } catch (_) {}

    // 3. REST API (last resort — only reachable when server is up)
    try {
      final list = await ApiService.superAdminGetAdmins()
          .timeout(const Duration(seconds: 5));
      for (final item in list) {
        final m = Map<String, dynamic>.from(item as Map);
        final email    = (m['email']    ?? '').toString().toLowerCase();
        final username = (m['username'] ?? '').toString().toLowerCase();
        if (email == input || username == input) return m;
      }
    } catch (_) {}

    return null;
  }

  Future<Map<String, dynamic>?> _findUserDirect(String input) async {
    try {
      if (_db != null) {
        for (final field in ['email', 'uniqueId', 'phoneNumber']) {
          final snap = await _db!
              .collection('users')
              .where(field, isEqualTo: input)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 6));
          if (snap.docs.isNotEmpty &&
              (snap.docs.first.data()['status'] ?? 'active') != 'deleted') {
            final doc = snap.docs.first;
            return {...doc.data(), 'userId': doc.id, 'id': doc.id};
          }
        }
      }
    } catch (_) {}

    // Local cache fallback
    try {
      for (final lvl in ['low', 'medium', 'high']) {
        final cached = await OfflineService.getCachedUsers(lvl);
        for (final u in cached) {
          final email = (u['email'] ?? '').toString().toLowerCase();
          if (email == input) return u;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _resolveEmail(String username) async {
    try {
      if (_db != null) {
        for (final col in ['admins', 'users']) {
          final snap = await _db!
              .collection(col)
              .where('username', isEqualTo: username.toLowerCase())
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 4));
          if (snap.docs.isNotEmpty) {
            return snap.docs.first.data()['email'] as String?;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _friendlyAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.\nበዚህ ኢሜይል መለያ አልተገኘም።';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.\nኢሜይልዎ ወይም የይለፍ ቃልዎ ትክክል አይደለም።';
      case 'invalid-email':
        return 'Invalid email address.\nትክክለኛ ኢሜይል ያስፈልጋል።';
      case 'user-disabled':
        return 'This account has been disabled.\nይህ መለያ ታግዷል።';
      case 'too-many-requests':
        return 'Too many attempts. Please wait.\nብዙ ሙከራዎች። ትንሽ ይጠብቁ።';
      default:
        return 'Login failed. Please check your credentials.\nዳግም ሞክር።';
    }
  }

  // ── Register ───────────────────────────────────────────────────────────────
  Future<bool> register(Map<String, dynamic> data) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final email    = (data['email']    ?? '').toString().trim();
      final password = (data['password'] ?? '').toString().trim();
      if (email.isEmpty || password.isEmpty) {
        _error = 'Email and password are required.';
        _loading = false;
        notifyListeners();
        return false;
      }
      if (_auth != null) {
        final cred = await _auth!.createUserWithEmailAndPassword(
            email: email, password: password);
        final u = cred.user;
        if (u != null) {
          final db = _db ?? FirebaseFirestore.instance;
          String role = (data['role'] ?? 'user').toString();
          try {
            final inviteSnap = await db
                .collection('admins')
                .where('email', isEqualTo: email)
                .where('status', isEqualTo: 'invited')
                .get();
            if (inviteSnap.docs.isNotEmpty) {
              role = 'admin';
              await db.collection('admins').doc(inviteSnap.docs.first.id).update({
                'firebaseUid': u.uid,
                'status': 'active',
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          } catch (_) {}
          final profile = <String, dynamic>{
            'fullName':    (data['fullName']    ?? '').toString().trim(),
            'firstName':   (data['firstName']   ?? '').toString().trim(),
            'lastName':    (data['lastName']    ?? '').toString().trim(),
            'phoneNumber': (data['phoneNumber'] ?? '').toString().trim(),
            'email': email,
            'role': role,
            'status': 'active',
            'verificationStatus': 'unverified',
            'hasWon': false,
            'balance': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          await db.collection('users').doc(u.uid).set(profile);
          _user = <String, dynamic>{
            ...profile,
            'uid': u.uid,
            'userId': u.uid,
            'id': u.uid,
          };
          _token = await u.getIdToken();
          await _cacheUser();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('firebase_token', _token ?? '');
          _loading = false;
          notifyListeners();
          return true;
        }
      }
      final res = await ApiService.register(data);
      if (!res.containsKey('error')) {
        _user = Map<String, dynamic>.from(res);
        await _cacheUser();
        _loading = false;
        notifyListeners();
        return true;
      }
      _error = res['error']?.toString() ?? 'Registration failed.';
    } on FirebaseAuthException catch (e) {
      _error = _friendlyAuthError(e.code);
    } catch (e) {
      _error = 'Registration failed. Please try again.';
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try { await _auth?.signOut(); } catch (_) {}
    _token = null;
    _user  = null;
    _error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('firebase_token');
      await prefs.remove('token');
      await prefs.remove('user_json');
      await prefs.remove('admin_doc_id');
    } catch (_) {}
    notifyListeners();
  }

  // ── Refresh ───────────────────────────────────────────────────────────────
  Future<void> refreshUserProfile() async {
    try {
      final u = _auth?.currentUser;
      if (u != null) {
        await _loadUserProfile(u.uid);
        notifyListeners();
        return;
      }
      final adminId = (_user?['adminId'] ?? '').toString();
      if (adminId.isNotEmpty && _db != null) {
        final doc = await _db!.collection('admins').doc(adminId).get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists) {
          final lvl = (doc.data()!['level'] ?? 'low').toString().toLowerCase();
          _user = <String, dynamic>{
            ...doc.data()!,
            'adminId': doc.id,
            'id': doc.id,
            'role': 'admin',
            'level': lvl,
            'equbLevel': lvl,
          };
          await _cacheUser();
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  void refreshUser(Map<String, dynamic> updated) {
    _user = updated;
    notifyListeners();
  }

  // ── Phone OTP ─────────────────────────────────────────────────────────────
  Future<void> sendPhoneOtp(String phone) async {
    _error = null; _loading = true; notifyListeners();
    if (_auth == null) {
      _error = 'Phone auth not available.';
      _loading = false; notifyListeners(); return;
    }
    try {
      await _auth!.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential cred) async {
          final r = await _auth!.signInWithCredential(cred);
          if (r.user != null) {
            _token = await r.user!.getIdToken();
            await _loadUserProfile(r.user!.uid);
            _loading = false; notifyListeners();
          }
        },
        verificationFailed: (e) {
          _error = e.message; _loading = false; notifyListeners();
        },
        codeSent: (verId, _) {
          verificationId = verId; _loading = false; notifyListeners();
        },
        codeAutoRetrievalTimeout: (verId) {
          verificationId = verId; _loading = false; notifyListeners();
        },
      );
    } catch (_) {
      _error = 'Failed to send OTP.'; _loading = false; notifyListeners();
    }
  }

  Future<bool> verifyOtp(String smsCode) async {
    _loading = true; _error = null; notifyListeners();
    if (_auth == null || verificationId == null) {
      _error = 'No verification in progress.';
      _loading = false; notifyListeners(); return false;
    }
    try {
      final cred = PhoneAuthProvider.credential(
          verificationId: verificationId!, smsCode: smsCode);
      final r = await _auth!.signInWithCredential(cred);
      if (r.user != null) {
        _token = await r.user!.getIdToken();
        await _loadUserProfile(r.user!.uid);
        _loading = false; notifyListeners(); return true;
      }
    } on FirebaseAuthException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Verification failed.';
    }
    _loading = false; notifyListeners(); return false;
  }
}
