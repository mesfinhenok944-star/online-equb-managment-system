import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ApiService
// All calls go to the Node.js/Express backend on localhost:8080 / 10.0.2.2:8080.
// Firebase is used by the backend; the Flutter app calls the REST API.
// ─────────────────────────────────────────────────────────────────────────────

class ApiService {
  // ── Server URL ─────────────────────────────────────────────────────────
  // Priority:
  //   1. OVERRIDE — set at runtime when user configures server IP
  //   2. Android emulator — 10.0.2.2 maps to host machine localhost
  //   3. Real device / desktop — uses the LAN IP stored in prefs, or
  //      falls back to localhost (which only works if on same machine)
  static String? _overrideBaseUrl;

  static String get _base {
    if (_overrideBaseUrl != null && _overrideBaseUrl!.isNotEmpty) {
      return _overrideBaseUrl!;
    }
    if (kIsWeb) return 'http://localhost:8080/api/v1';
    try {
      if (Platform.isAndroid) {
        // Real device: try the stored server IP first
        // The emulator check is deferred to runtime via _cachedBase
        return _cachedBase ?? 'http://10.0.2.2:8080/api/v1';
      }
    } catch (_) {}
    return 'http://localhost:8080/api/v1';
  }

  static String? _cachedBase;

  /// Call once at app start to detect the correct server URL.
  /// On a real Android device, the backend must be reachable via its
  /// LAN IP (e.g. 192.168.1.x) not the emulator shortcut 10.0.2.2.
  static Future<void> detectServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('server_base_url');
      if (stored != null && stored.isNotEmpty) {
        _cachedBase = stored;
        return;
      }
    } catch (_) {}
    // Default fallback — emulator uses 10.0.2.2, real phone needs LAN IP
    try {
      if (!kIsWeb && Platform.isAndroid) {
        _cachedBase = 'http://10.0.2.2:8080/api/v1';
      }
    } catch (_) {}
  }

  /// Persist a custom server base URL (e.g. http://192.168.1.134:8080/api/v1)
  /// so the app uses it on all future requests.
  static Future<void> setServerUrl(String url) async {
    _overrideBaseUrl = url.trimRight().replaceAll(RegExp(r'/+$'), '');
    if (!_overrideBaseUrl!.endsWith('/api/v1')) {
      _overrideBaseUrl = '$_overrideBaseUrl/api/v1';
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_base_url', _overrideBaseUrl!);
    } catch (_) {}
  }

  static Future<void> clearServerUrl() async {
    _overrideBaseUrl = null;
    _cachedBase = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('server_base_url');
    } catch (_) {}
  }

  static final _client = http.Client();

  /// Returns the current effective base URL (for display purposes)
  static String get currentBaseUrl => _base;

  // ── Token helpers ─────────────────────────────────────────────────────────

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('firebase_token') ??
        prefs.getString('token');
  }

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final t = await _getToken();
      if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  // Safe JSON decode — returns {} on parse failure instead of throwing.
  static Map<String, dynamic> _decode(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) return body;
      return {'data': body};
    } catch (_) {
      return {'error': 'Invalid response from server', 'raw': res.body};
    }
  }

  static List<dynamic> _decodeList(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is List) return body;
      if (body is Map && body['data'] is List) return body['data'] as List;
      return [];
    } catch (_) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ══════════════════════════════════════════════════════════════════════════

  /// Login — returns { token, user } or { error }.
  static Future<Map<String, dynamic>> login(
      String emailOrUsername, String password) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/auth/login'),
        headers: await _headers(auth: false),
        body: jsonEncode({'email': emailOrUsername, 'password': password}),
      );
      return _decode(res);
    } catch (e) {
      return {'error': 'Cannot reach server. Is the backend running?'};
    }
  }

  /// Register a new regular user.
  static Future<Map<String, dynamic>> register(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/auth/register'),
        headers: await _headers(auth: false),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': 'Registration failed: $e'};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUPER ADMIN
  // ══════════════════════════════════════════════════════════════════════════

  /// List all admins, optionally filtered by level.
  static Future<List<dynamic>> superAdminGetAdmins({String? level, String? status}) async {
    try {
      final params = <String, String>{};
      if (level != null && level != 'all') params['level'] = level;
      if (status != null && status != 'all') params['status'] = status;
      final uri = Uri.parse('$_base/super-admin/admins').replace(queryParameters: params);
      final res = await _client.get(uri, headers: await _headers());
      return _decodeList(res);
    } catch (_) {
      return [];
    }
  }

  /// Create / assign a new admin.
  static Future<Map<String, dynamic>> superAdminCreateAdmin(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/super-admin/admins'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': 'Failed to create admin: $e'};
    }
  }

  /// Get a single admin by id.
  static Future<Map<String, dynamic>> superAdminGetAdmin(String adminId) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/super-admin/admins/$adminId'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Update an admin.
  static Future<Map<String, dynamic>> superAdminUpdateAdmin(
      String adminId, Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/super-admin/admins/$adminId'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Delete (soft) an admin.
  static Future<Map<String, dynamic>> superAdminDeleteAdmin(String adminId) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/super-admin/admins/$adminId'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Suspend an admin.
  static Future<Map<String, dynamic>> superAdminSuspendAdmin(
      String adminId, {String reason = ''}) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/super-admin/admins/$adminId/suspend'),
        headers: await _headers(),
        body: jsonEncode({'reason': reason}),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Activate a suspended admin.
  static Future<Map<String, dynamic>> superAdminActivateAdmin(String adminId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/super-admin/admins/$adminId/activate'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Get system-wide stats.
  static Future<Map<String, dynamic>> superAdminGetStats() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/super-admin/stats'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADMIN — Dashboard & User CRUD
  // ══════════════════════════════════════════════════════════════════════════

  /// Get dashboard stats for all 3 levels.
  static Future<Map<String, dynamic>> adminGetDashboard() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/dashboard'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (_) {
      return _fallbackDashboard();
    }
  }

  /// Get stats for a single level.
  static Future<Map<String, dynamic>> adminGetLevelDashboard(String level) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/dashboard/$level'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (_) {
      return {};
    }
  }

  /// Admin self-update profile settings.
  static Future<Map<String, dynamic>> updateAdminSettings(
      String adminId, Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/settings'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// List users, optionally filtered by level.
  static Future<List<dynamic>> adminGetUsers({String? level}) async {
    try {
      final params = level != null ? '?level=$level' : '';
      final res = await _client.get(
        Uri.parse('$_base/admin/users$params'),
        headers: await _headers(),
      );
      return _decodeList(res);
    } catch (_) {
      return [];
    }
  }

  /// Alias used by older code.
  static Future<List<dynamic>> adminGetAllUsers() => adminGetUsers();

  /// Create a new user (member).
  static Future<Map<String, dynamic>> adminCreateUser(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/admin/users'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Update a user.
  static Future<Map<String, dynamic>> adminUpdateUser(
      String userId, Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Delete a user (soft).
  static Future<Map<String, dynamic>> adminDeleteUser(String userId) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/admin/users/$userId'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Verify a user.
  static Future<Map<String, dynamic>> adminVerifyUser(String userId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId/verify'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Suspend a user.
  static Future<Map<String, dynamic>> adminSuspendUser(String userId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId/suspend'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Activate a user.
  static Future<Map<String, dynamic>> adminActivateUser(String userId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId/activate'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Assign an existing user to an equb level.
  static Future<Map<String, dynamic>> adminRegisterToLevel(
      String userId, String level) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/admin/dashboard/register'),
        headers: await _headers(),
        body: jsonEncode({'userId': userId, 'level': level}),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Remove a participant.
  static Future<Map<String, dynamic>> adminRemoveParticipant(
      String participantId) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/admin/dashboard/remove'),
        headers: await _headers(),
        body: jsonEncode({'participantId': participantId}),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Run draw for a level.
  static Future<Map<String, dynamic>> adminRunDraw(String level) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/admin/draw/$level'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Get draw history for a level.
  static Future<List<dynamic>> adminGetDrawHistory(String level) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/draw/$level/history'),
        headers: await _headers(),
      );
      return _decodeList(res);
    } catch (_) {
      return [];
    }
  }

  /// Delete a draw history record.
  static Future<Map<String, dynamic>> deleteDrawHistory(String drawId, String level) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/admin/draw/$level/$drawId'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Get analytics summary.
  static Future<Map<String, dynamic>> adminGetAnalytics() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/analytics'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EQUBS
  // ══════════════════════════════════════════════════════════════════════════

  static final List<Map<String, dynamic>> _customEqubs = [];

  static Future<Map<String, dynamic>> createEqubLevel(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/equbs'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      final decoded = _decode(res);
      if (decoded['id'] != null || decoded['equbId'] != null) {
        _customEqubs.add(decoded);
        return decoded;
      }
    } catch (_) {}

    // In-memory fallback
    final key = (data['level'] ?? data['name'].toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')).toString();
    final item = <String, dynamic>{
      'equbId': 'equb_$key',
      'id': 'equb_$key',
      'name': data['name'] ?? 'Custom Level',
      'level': key,
      'price': double.tryParse(data['price']?.toString() ?? '5000') ?? 5000.0,
      'netPrize': double.tryParse(data['netPrize']?.toString() ?? '450000') ?? 450000.0,
      'adminFee': 25000.0,
      'currentParticipants': 0,
      'maxParticipants': int.tryParse(data['maxParticipants']?.toString() ?? '50') ?? 50,
      'status': 'active',
      'cycle': data['cycle'] ?? 'Weekly',
      'description': data['description'] ?? '${data['name']} — ${data['price']} ETB/cycle',
    };
    _customEqubs.add(item);
    return item;
  }

  static Future<List<dynamic>> getEqubs() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/equbs/'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final list = _decodeList(res);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return [..._fallbackEqubs(), ..._customEqubs];
  }

  static Future<Map<String, dynamic>> getEqub(String id) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/equbs/$id'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) return _decode(res);
    } catch (_) {}
    return {};
  }

  static Future<Map<String, dynamic>> joinEqub(
      String equbId, String paymentMethod) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/equbs/$equbId/join'),
        headers: await _headers(),
        body: jsonEncode({'paymentMethod': paymentMethod}),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> getEqubStats(String id) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/equbs/$id/stats'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) return _decode(res);
    } catch (_) {}
    return {'currentParticipants': 0, 'totalCollected': 0.0};
  }

  static Future<List<dynamic>> getEqubDraws(String id) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/equbs/$id/draws'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) return _decodeList(res);
    } catch (_) {}
    return [];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAYMENTS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> submitEqubPayment(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/payments/submit'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Future<List<dynamic>> getPaymentsByLevel(String level) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/payments/level/$level'),
        headers: await _headers(),
      );
      return _decodeList(res);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> verifyPayment(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/payments/verify'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> initiatePayment(
      Map<String, dynamic> data) async {
    return submitEqubPayment(data);
  }

  static Future<List<dynamic>> getPaymentHistory({String? userId}) async {
    try {
      final params = userId != null ? '?userId=$userId' : '';
      final res = await _client.get(
        Uri.parse('$_base/payments/history$params'),
        headers: await _headers(),
      );
      return _decodeList(res);
    } catch (_) {
      return [];
    }
  }

  static Future<List<dynamic>> adminGetPendingPayments() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/payments/pending'),
        headers: await _headers(),
      );
      return _decodeList(res);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> adminVerifyPayment(
      String transactionId) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/payments/verify'),
        headers: await _headers(),
        body: jsonEncode({'transactionId': transactionId}),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // USER PROFILE
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/users/profile'),
        headers: await _headers(),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/users/profile'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Future<List<dynamic>> getNotifications() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/users/notifications'),
        headers: await _headers(),
      );
      return _decodeList(res);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> submitKyc(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/users/kyc'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Fallback data (used when backend is unreachable)
  // ══════════════════════════════════════════════════════════════════════════

  static List<dynamic> _fallbackEqubs() => [
        {
          'equbId': 'equb_low', 'id': 'equb_low',
          'name': 'ዝቅተኛ · Low Level EQUB', 'level': 'low',
          'price': 5000.0, 'netPrize': 465000.0, 'adminFee': 35000.0,
          'currentParticipants': 0, 'maxParticipants': 100, 'status': 'active',
          'description': 'Low level EQUB for small business owners.',
        },
        {
          'equbId': 'equb_medium', 'id': 'equb_medium',
          'name': 'መካከለኛ · Medium Level EQUB', 'level': 'medium',
          'price': 10000.0, 'netPrize': 465000.0, 'adminFee': 35000.0,
          'currentParticipants': 0, 'maxParticipants': 50, 'status': 'active',
          'description': 'Medium level EQUB for established business owners.',
        },
        {
          'equbId': 'equb_high', 'id': 'equb_high',
          'name': 'ከፍተኛ · High Level EQUB', 'level': 'high',
          'price': 20000.0, 'netPrize': 360000.0, 'adminFee': 40000.0,
          'currentParticipants': 0, 'maxParticipants': 20, 'status': 'active',
          'description': 'High level EQUB for large investors.',
        },
      ];

  static Map<String, dynamic> _fallbackDashboard() => {
        for (final level in ['low', 'medium', 'high'])
          level: {
            'equbId': 'equb_$level', 'level': level,
            'currentParticipants': 0, 'maxParticipants': level == 'high' ? 20 : level == 'medium' ? 50 : 100,
            'eligibleCount': 0, 'drawsHeld': 0,
            'totalCollected': 0.0, 'status': 'active',
            'participants': [], 'draws': [],
          }
      };
}
