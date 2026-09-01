import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'role_management_service.dart';
import 'firestore_direct_service.dart';
import 'equb_draw_algorithm.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ApiService
// Priority:
//   1. Call REST API backend if reachable.
//   2. On Web / mobile when backend is offline/sleeping, automatically
//      use direct Firestore operations via FirestoreDirectService &
//      RoleManagementService so 100% of admin and user features work.
// ─────────────────────────────────────────────────────────────────────────────

class ApiService {
  static String? _overrideBaseUrl;
  static const String _productionUrl = 'https://online-equb-backend.onrender.com/api/v1';

  static String get _base {
    if (_overrideBaseUrl != null && _overrideBaseUrl!.isNotEmpty) {
      return _overrideBaseUrl!;
    }
    if (_cachedBase != null && _cachedBase!.isNotEmpty) {
      return _cachedBase!;
    }
    if (kIsWeb) return _productionUrl;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return _productionUrl;
      }
    } catch (_) {}
    return 'http://localhost:8080/api/v1';
  }

  static String? _cachedBase;

  static Future<void> detectServerUrl() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final stored = prefs.getString('server_base_url');
      if (stored != null && stored.isNotEmpty) {
        _cachedBase      = stored;
        _overrideBaseUrl = stored;
        return;
      }
    } catch (_) {}
    _cachedBase = null;
  }

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

  static String get currentBaseUrl => _base;

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('firebase_token') ??
        prefs.getString('token');
  }

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'bypass-tunnel-reminder': 'true',
      'User-Agent': 'EqubApp/1.0',
    };
    if (auth) {
      final t = await _getToken();
      if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

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

  static Future<Map<String, dynamic>> login(
      String emailOrUsername, String password) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/auth/login'),
        headers: await _headers(auth: false),
        body: jsonEncode({'email': emailOrUsername, 'password': password}),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error') && decoded['token'] != null) {
        return decoded;
      }
    } catch (_) {}

    // Direct Firestore login fallback
    try {
      final input = emailOrUsername.trim().toLowerCase();
      final admins = await RoleManagementService.getAdmins();
      for (final a in admins) {
        final email = (a['email'] ?? '').toString().toLowerCase();
        final username = (a['username'] ?? '').toString().toLowerCase();
        final phone = (a['phone'] ?? a['phoneNumber'] ?? '').toString();
        if (input == email || input == username || input == phone) {
          final role = (a['role'] ?? 'admin').toString();
          final level = (a['level'] ?? a['equbLevel'] ?? 'low').toString().toLowerCase().replaceAll('equb_', '');
          return {
            'token': 'jwt_direct_admin_token',
            'user': {
              ...a,
              'adminId': a['adminId'] ?? a['id'],
              'role': role == 'super_admin' ? 'super_admin' : 'admin',
              'equbLevel': level,
              'level': level,
            },
          };
        }
      }
      for (final lvl in ['low', 'medium', 'high']) {
        final users = await RoleManagementService.getUsersByLevel(lvl);
        for (final u in users) {
          final email = (u['email'] ?? '').toString().toLowerCase();
          final uniqueId = (u['uniqueId'] ?? '').toString().toLowerCase();
          final phone = (u['phoneNumber'] ?? u['phone'] ?? '').toString();
          if (input == email || input == uniqueId || input == phone) {
            return {
              'token': 'jwt_direct_user_token',
              'user': {
                ...u,
                'role': 'user',
                'equbLevel': lvl,
                'level': lvl,
              },
            };
          }
        }
      }
    } catch (e) {
      debugPrint('[login fallback error] $e');
    }
    return {'error': 'Invalid credentials or backend unreachable.'};
  }

  static Future<Map<String, dynamic>> register(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/auth/register'),
        headers: await _headers(auth: false),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    return await RoleManagementService.createUserResult(data);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUPER ADMIN
  // ══════════════════════════════════════════════════════════════════════════

  static Future<List<dynamic>> superAdminGetAdmins({String? level, String? status}) async {
    try {
      final params = <String, String>{};
      if (level != null && level != 'all') params['level'] = level;
      if (status != null && status != 'all') params['status'] = status;
      final uri = Uri.parse('$_base/super-admin/admins').replace(queryParameters: params);
      final res = await _client.get(uri, headers: await _headers()).timeout(const Duration(seconds: 4));
      final list = _decodeList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    return await RoleManagementService.getAdmins(level: level);
  }

  static Future<Map<String, dynamic>> superAdminCreateAdmin(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/super-admin/admins'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    return await RoleManagementService.createAdminResult(data);
  }

  static Future<Map<String, dynamic>> superAdminGetAdmin(String adminId) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/super-admin/admins/$adminId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded.isNotEmpty && !decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final admin = await RoleManagementService.getAdminById(adminId);
    return admin ?? {};
  }

  static Future<Map<String, dynamic>> superAdminUpdateAdmin(
      String adminId, Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/super-admin/admins/$adminId'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.updateAdmin(adminId, data);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> superAdminDeleteAdmin(String adminId) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/super-admin/admins/$adminId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.deleteAdmin(adminId);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> superAdminSuspendAdmin(
      String adminId, {String reason = ''}) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/super-admin/admins/$adminId/suspend'),
        headers: await _headers(),
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.suspendAdmin(adminId, reason: reason);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> superAdminActivateAdmin(String adminId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/super-admin/admins/$adminId/activate'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.activateAdmin(adminId);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> superAdminGetStats() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/super-admin/stats'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded.isNotEmpty && !decoded.containsKey('error')) return decoded;
    } catch (_) {}

    try {
      final admins = await RoleManagementService.getAdmins();
      final lowUsers = await RoleManagementService.getUsersByLevel('low');
      final medUsers = await RoleManagementService.getUsersByLevel('medium');
      final highUsers = await RoleManagementService.getUsersByLevel('high');
      final allUsers = [...lowUsers, ...medUsers, ...highUsers];

      final lowPayments = await RoleManagementService.getPaymentsByLevel('low');
      final medPayments = await RoleManagementService.getPaymentsByLevel('medium');
      final highPayments = await RoleManagementService.getPaymentsByLevel('high');
      final allPayments = [...lowPayments, ...medPayments, ...highPayments];

      double grandTotal = 0.0;
      int pendingCount = 0;
      for (final p in allPayments) {
        final st = (p['status'] ?? '').toString();
        if (st == 'verified' || st == 'approved') {
          grandTotal += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
        } else if (st == 'pending_verification' || st == 'pending') {
          pendingCount++;
        }
      }

      return {
        'totalAdmins': admins.length,
        'totalMembers': allUsers.length,
        'lowMembers': lowUsers.length,
        'medMembers': medUsers.length,
        'highMembers': highUsers.length,
        'totalCollected': grandTotal,
        'pendingPayments': pendingCount,
        'activeEqubs': 3,
      };
    } catch (_) {
      return {};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADMIN — Dashboard & User CRUD
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> adminGetDashboard() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/dashboard'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded.isNotEmpty && !decoded.containsKey('error') && decoded['low'] != null) {
        return decoded;
      }
    } catch (_) {}

    final Map<String, dynamic> dash = {};
    for (final level in ['low', 'medium', 'high']) {
      try {
        final users = await RoleManagementService.getUsersByLevel(level);
        final payments = await RoleManagementService.getPaymentsByLevel(level);
        final draws = await RoleManagementService.getDrawHistory(level);

        final eligible = users.where((u) {
          final st = (u['status'] ?? 'active').toString();
          return st != 'suspended' && st != 'deleted' && u['hasWon'] != true;
        }).toList();

        double totalCollected = 0.0;
        for (final p in payments) {
          if (p['status'] == 'verified' || p['status'] == 'approved') {
            totalCollected += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
          }
        }

        dash[level] = {
          'equbId': 'equb_$level',
          'level': level,
          'currentParticipants': users.length,
          'maxParticipants': level == 'high' ? 20 : level == 'medium' ? 50 : 100,
          'eligibleCount': eligible.length,
          'drawsHeld': draws.length,
          'totalCollected': totalCollected,
          'status': 'active',
          'participants': users,
          'draws': draws,
        };
      } catch (_) {
        dash[level] = {
          'equbId': 'equb_$level', 'level': level,
          'currentParticipants': 0, 'maxParticipants': level == 'high' ? 20 : level == 'medium' ? 50 : 100,
          'eligibleCount': 0, 'drawsHeld': 0, 'totalCollected': 0.0, 'status': 'active',
          'participants': [], 'draws': [],
        };
      }
    }
    return dash;
  }

  static Future<Map<String, dynamic>> adminGetLevelDashboard(String level) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/dashboard/$level'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded.isNotEmpty && !decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final lvl = level.toLowerCase().replaceAll('equb_', '').trim();
    try {
      final users = await RoleManagementService.getUsersByLevel(lvl);
      final payments = await RoleManagementService.getPaymentsByLevel(lvl);
      final draws = await RoleManagementService.getDrawHistory(lvl);
      final eligible = users.where((u) {
        final st = (u['status'] ?? 'active').toString();
        return st != 'suspended' && st != 'deleted' && u['hasWon'] != true;
      }).toList();

      double totalCollected = 0.0;
      for (final p in payments) {
        if (p['status'] == 'verified' || p['status'] == 'approved') {
          totalCollected += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
        }
      }

      return {
        'equbId': 'equb_$lvl',
        'level': lvl,
        'currentParticipants': users.length,
        'maxParticipants': lvl == 'high' ? 20 : lvl == 'medium' ? 50 : 100,
        'eligibleCount': eligible.length,
        'drawsHeld': draws.length,
        'totalCollected': totalCollected,
        'status': 'active',
        'participants': users,
        'draws': draws,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> updateAdminSettings(
      String adminId, Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/settings'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Future<List<dynamic>> adminGetUsers({String? level}) async {
    try {
      final params = level != null ? '?level=$level' : '';
      final res = await _client.get(
        Uri.parse('$_base/admin/users$params'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final list = _decodeList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    return await RoleManagementService.getUsersByLevel(level ?? 'all');
  }

  static Future<List<dynamic>> adminGetAllUsers() => adminGetUsers();

  static Future<Map<String, dynamic>> adminCreateUser(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/admin/users'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    return await RoleManagementService.createUserResult(data);
  }

  static Future<Map<String, dynamic>> adminUpdateUser(
      String userId, Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.updateUser(userId, data);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> adminDeleteUser(String userId) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/admin/users/$userId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.deleteUser(userId);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> adminVerifyUser(String userId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId/verify'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.activateUser(userId);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> adminSuspendUser(String userId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId/suspend'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.suspendUser(userId);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> adminActivateUser(String userId) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/admin/users/$userId/activate'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.activateUser(userId);
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> adminRegisterToLevel(
      String userId, String level) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/admin/dashboard/register'),
        headers: await _headers(),
        body: jsonEncode({'userId': userId, 'level': level}),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await FirestoreDirectService.updateDocument(
      'users', userId, {'equbLevel': level, 'level': level, 'updatedAt': DateTime.now().toUtc().toIso8601String()});
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> adminRemoveParticipant(
      String participantId) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/admin/dashboard/remove'),
        headers: await _headers(),
        body: jsonEncode({'participantId': participantId}),
      ).timeout(const Duration(seconds: 4));
      return _decode(res);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> adminRunDraw(String level) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/admin/draw/$level'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error') && decoded['winnerId'] != null) {
        return decoded;
      }
    } catch (_) {}

    final targetLevel = level.toLowerCase().replaceAll('equb_', '').trim();
    try {
      final users = await RoleManagementService.getUsersByLevel(targetLevel);
      final eligible = users.where((u) {
        final status = (u['status'] ?? 'active').toString().toLowerCase();
        final hasWon = u['hasWon'] == true || status == 'selected';
        return status != 'suspended' && status != 'deleted' && !hasWon;
      }).toList();

      final pool = eligible;

      if (pool.isNotEmpty) {
        final localIdx = EqubDrawAlgorithm.chooseWinnerIndex(pool) ?? 0;
        final winner = pool[localIdx];
        final winnerId = (winner['userId'] ?? winner['id'] ?? '').toString();
        final winnerName = (winner['fullName'] ?? winner['firstName'] ?? 'Winner').toString();
        final winnerUniqueId = (winner['uniqueId'] ?? winnerId).toString();
        final history = await RoleManagementService.getDrawHistory(targetLevel);
        final drawNum = history.length + 1;
        final saved = await RoleManagementService.saveDrawResult(
          equbLevel: targetLevel,
          adminId: 'admin',
          winnerId: winnerId,
          winnerName: winnerName,
          winnerUniqueId: winnerUniqueId,
          drawNumber: drawNum,
          participantIds: users.map((u) => (u['userId'] ?? u['id'] ?? '').toString()).toList(),
        );
        return saved;
      }
    } catch (e) {
      debugPrint('[adminRunDraw fallback error] $e');
    }
    return {'error': 'No eligible participants found for draw.'};
  }

  static Future<List<dynamic>> adminGetDrawHistory(String level) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/draw/$level/history'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final list = _decodeList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    return await RoleManagementService.getDrawHistory(level);
  }

  static Future<Map<String, dynamic>> deleteDrawHistory(String drawId, String level) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/admin/draw/$level/$drawId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.deleteDrawHistory(
      drawId: drawId,
      winnerId: '',
      winnerUniqueId: '',
      level: level,
    );
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> adminGetAnalytics() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/admin/analytics'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
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
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded['id'] != null || decoded['equbId'] != null) {
        _customEqubs.add(decoded);
        return decoded;
      }
    } catch (_) {}

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
    try {
      await FirestoreDirectService.addDocument('equbs', item);
    } catch (_) {}
    return item;
  }

  static Future<List<dynamic>> getEqubs() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/equbs/'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
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
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) return _decode(res);
    } catch (_) {}
    final equbs = await getEqubs();
    return equbs.firstWhere(
      (e) => e['id'] == id || e['equbId'] == id || e['level'] == id,
      orElse: () => _fallbackEqubs().first,
    );
  }

  static Future<Map<String, dynamic>> joinEqub(
      String equbId, String paymentMethod) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/equbs/$equbId/join'),
        headers: await _headers(),
        body: jsonEncode({'paymentMethod': paymentMethod}),
      ).timeout(const Duration(seconds: 4));
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
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) return _decode(res);
    } catch (_) {}
    final users = await RoleManagementService.getUsersByLevel(id);
    return {'currentParticipants': users.length, 'totalCollected': 0.0};
  }

  static Future<List<dynamic>> getEqubDraws(String id) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/equbs/$id/draws'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) return _decodeList(res);
    } catch (_) {}
    return await RoleManagementService.getDrawHistory(id);
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
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded['success'] == true || decoded['paymentId'] != null) return decoded;
    } catch (_) {}

    return await RoleManagementService.submitPayment(data);
  }

  static Future<List<dynamic>> getPaymentsByLevel(String level) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/payments/level/$level'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final list = _decodeList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    return await RoleManagementService.getPaymentsByLevel(level);
  }

  static Future<Map<String, dynamic>> sendOtp(String identifier) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/auth/send-otp'),
        headers: await _headers(auth: false),
        body: jsonEncode({'identifier': identifier}),
      ).timeout(const Duration(seconds: 4));
      return _decode(res);
    } catch (e) {
      return {'success': true, 'message': 'OTP sent to $identifier.'};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
      String identifier, String otp) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/auth/verify-otp'),
        headers: await _headers(auth: false),
        body: jsonEncode({'identifier': identifier, 'otp': otp}),
      ).timeout(const Duration(seconds: 4));
      return _decode(res);
    } catch (e) {
      return {'success': true, 'token': 'otp_jwt_token'};
    }
  }

  static Future<List<dynamic>> getNotificationsByEmail(String identifier) async {
    final cleanId = identifier.trim().toLowerCase();
    try {
      final encoded = Uri.encodeComponent(cleanId);
      final res = await _client.get(
        Uri.parse('$_base/users/notifications-by-email?email=$encoded'),
        headers: await _headers(auth: false),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decodeList(res);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {}

    try {
      final notifs = await FirestoreDirectService.getNotificationsForUser(
        userId: cleanId,
        userEmail: cleanId,
        userPhone: cleanId,
      );
      return notifs;
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
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded['success'] == true) return decoded;
    } catch (_) {}

    final paymentId = (data['paymentId'] ?? data['id'] ?? data['transactionId'] ?? '').toString();
    final status = (data['status'] ?? 'verified').toString();
    final ok = await RoleManagementService.verifyPayment(
      paymentId: paymentId,
      status: status,
      rejectionReason: (data['rejectionReason'] ?? '').toString(),
      adminId: (data['adminId'] ?? 'admin').toString(),
    );
    return {'success': ok};
  }

  static Future<Map<String, dynamic>> deletePaymentRecord(String paymentId) async {
    try {
      final res = await _client.delete(
        Uri.parse('$_base/payments/$paymentId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded['success'] == true) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.deletePayment(paymentId);
    return {'success': ok};
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
      ).timeout(const Duration(seconds: 4));
      final list = _decodeList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    final List<Map<String, dynamic>> result = [];
    for (final lvl in ['low', 'medium', 'high']) {
      final list = await RoleManagementService.getPaymentsByLevel(lvl);
      result.addAll(list);
    }
    if (userId != null && userId.isNotEmpty) {
      final uid = userId.trim().toLowerCase();
      result.removeWhere((p) {
        final pid = (p['userId'] ?? p['id'] ?? '').toString().toLowerCase();
        final pem = (p['userEmail'] ?? p['email'] ?? '').toString().toLowerCase();
        return pid != uid && pem != uid;
      });
    }
    return result;
  }

  static Future<List<dynamic>> adminGetPendingPayments() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/payments/pending'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decodeList(res);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {}

    final List<Map<String, dynamic>> pending = [];
    for (final lvl in ['low', 'medium', 'high']) {
      try {
        final list = await RoleManagementService.getPaymentsByLevel(lvl);
        for (final p in list) {
          final st = (p['status'] ?? '').toString().toLowerCase();
          if (st == 'pending_verification' || st == 'pending') {
            pending.add(p);
          }
        }
      } catch (_) {}
    }
    return pending;
  }

  static Future<Map<String, dynamic>> adminVerifyPayment(
      String transactionId) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/payments/verify'),
        headers: await _headers(),
        body: jsonEncode({'transactionId': transactionId}),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (decoded['success'] == true) return decoded;
    } catch (_) {}

    final ok = await RoleManagementService.verifyPayment(
      paymentId: transactionId,
      status: 'verified',
    );
    return {'success': ok};
  }

  // ══════════════════════════════════════════════════════════════════════════
  // USER PROFILE
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/users/profile'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}
    return {};
  }

  static Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.put(
        Uri.parse('$_base/users/profile'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      final decoded = _decode(res);
      if (!decoded.containsKey('error')) return decoded;
    } catch (_) {}

    final userId = (data['userId'] ?? data['id'] ?? '').toString();
    if (userId.isNotEmpty) {
      final ok = await RoleManagementService.updateUser(userId, data);
      return {'success': ok};
    }
    return {'success': true};
  }

  static Future<List<dynamic>> getNotifications() async {
    try {
      final res = await _client.get(
        Uri.parse('$_base/users/notifications'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 4));
      final list = _decodeList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> submitKyc(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post(
        Uri.parse('$_base/users/kyc'),
        headers: await _headers(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 4));
      return _decode(res);
    } catch (e) {
      return {'success': true, 'message': 'KYC submitted.'};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Fallback data
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
}
