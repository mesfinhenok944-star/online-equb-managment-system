import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FirestoreDirectService
//
// Uses a service-account JWT to get an OAuth2 token, then queries Firestore
// REST API directly — bypasses Firestore security rules completely.
// Works on real Android phone over WiFi or mobile data, no server needed.
// ─────────────────────────────────────────────────────────────────────────────
class FirestoreDirectService {
  // ignore: constant_identifier_names
  static const _P = 'online-equb-managment-system';
  // ignore: constant_identifier_names
  static const _E = 'firebase-adminsdk-fbsvc@online-equb-managment-system.iam.gserviceaccount.com';

  // Service account private key — embedded so phone needs no server
  // ignore: constant_identifier_names
  static const _K =
      '-----BEGIN PRIVATE KEY-----\n'
      'MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCqE82la5EOIIH+\n'
      'S2yEauNFs81DYgmNChOe1HKAFkBBASB+lN0rAGiORGBFSQz/WjzuW25zXZcD/hcL\n'
      'q/caEsiukcmqNAFGJKFtxDafZZ9n/l1Eg+vIbGqOxTLjmJQGJKIQQ7PywVS2i4yX\n'
      'r1cC9kJrNDCNvB4aaipY9u65NccntFADLmMUR4SEH1wgpimP3ULAjV6E9GnojJN2\n'
      'NkN+izbVXMiPyPTbsITIFdwcoWNpJLK8ypLWxTTE4RNEu5pF+uHmVWgQcHpiWrFw\n'
      'K7Ojagg7+AI150mOWdUVsEQA5AdQvoegjZrKzyjGYNOCQen+nwQrjXzfansUMUZk\n'
      'egK0yYNhAgMBAAECggEADyTXRVj4IA1l9coqffn0hbLWXp8eoZfZmmVpUp1omEEs\n'
      '7wh7TwZoyO4uskyoYx5aWZD7mzskpL7dt3TW+lPc2apyjfy2dlPxqc/0WyoV0RE1\n'
      'pdGnT3/T1yWY++oMmCVv5snYfo+XZu+zE5iRw1pBHMGXZy9ucMSuQ6CtLgGrW44N\n'
      '/uMiyK+l2NLaZEsL7k1NH+6jW1YtG9iuRnqvdOSawzozyikZ2Sa4mUHifHSdxW4s\n'
      'hu2Q6KT/hfbWY1wUZ2Jd1lSSaWrNxfw71qWbLJixi4/3T4r9FIi//nkgUs1dsUeJ\n'
      'EPJhi+ZDIKi7u0kc+ARyFssqX6GcUb3PB71TlFF4JwKBgQDRdtvNU2IotR7ZtGdr\n'
      'pfmm058wnF4pFpc9SnXZt7p93Luy9bG55qapfO3Nt7UIhv0wFKV5ysZCVomyz6lT\n'
      'g+EnHXLJAnfM8aIZg5O5N498MXMdP0b5syZFX+cX767n6vtVg++TmJRJM3Yd1cVp\n'
      '8u0aHTU7Z4O3IsiFV6Rz9J3egwKBgQDP3NbSY4t3/vbkgikaud0kPU8/6wUt7vF+\n'
      'IQFdW6766hDtwKghb6Do9bi0eAu7z5P6uRMNf/2foQ97NYGKJKnJfofSqtxlMlak\n'
      'CZJkiFSsXJONZk38TlJ88jXu8DWa/kO3zfvSO8eryhxUrXrugM7ip05mU90HT5z3\n'
      '/pU7JrDxSwKBgGSezjOyDIM1jl5SNSQXFPg4zE3Tr7/ZJEnDDR3LDoELmfb746ZD\n'
      '0Ge2pZ2e1A4GmnWQVXVOHTMc0wTckKCXx368vLkmwFno8U+ET2A3+mtUbdHs5bFp\n'
      'h8bnrOFouAKcdKO9v0aNkx4e5GysliqxEYjr4vhoX3OH9/9l/I/fQD71AoGAE6U5\n'
      'oHTMD7FHQF2U6PO8FNq+jLn3qVm19UfFSz+JECnjI7Vbrp1QRfRDWrsl0MBTqhSn\n'
      '2lTIcbfVML3j2lyQt3x/9cc0QVQ6oBJPhbTk2818HJcYs8nrPefedRC64EU7vTl4\n'
      'nWwM+Q2HE/G5dqUx6HYLkNxIPZKmsUGcdRS5EHUCgYB+dRS8enx1nP29BXEOjuKL\n'
      'vfdQSRwFICB0w/VgzBByrj0MB53yUU7TMmDQ5H7DcXjKWPjzEeeFzajhw+kEflBD\n'
      'r8K+Msq/tSmEC0VJy29AW2YBW2espDihaR260xQylRKYKTvlgdzrA/AEoi+f5181\n'
      'Cmc2e2x1XVGugC4VmhZEzA==\n'
      '-----END PRIVATE KEY-----\n';

  static String? _cachedToken;
  static DateTime? _tokenExpiry;

  // ── Get / refresh OAuth2 token via service account JWT ───────────────────
  static Future<String?> _getToken() async {
    try {
      if (_cachedToken != null &&
          _tokenExpiry != null &&
          DateTime.now().isBefore(_tokenExpiry!)) {
        return _cachedToken;
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final jwt = JWT({
        'iss'  : _E,
        'scope': 'https://www.googleapis.com/auth/datastore',
        'aud'  : 'https://oauth2.googleapis.com/token',
        'iat'  : now,
        'exp'  : now + 3600,
      });
      final signed = jwt.sign(RSAPrivateKey(_K), algorithm: JWTAlgorithm.RS256);

      final resp = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer'
              '&assertion=$signed',
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _cachedToken = data['access_token'] as String?;
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
        debugPrint('[FirestoreDirect] ✅ token obtained');
        return _cachedToken;
      }
      debugPrint('[FirestoreDirect] token error ${resp.statusCode}');
    } catch (e) {
      debugPrint('[FirestoreDirect] _getToken error: $e');
    }
    return null;
  }

  // ── Firestore value parser ────────────────────────────────────────────────
  static dynamic _val(dynamic v) {
    if (v is! Map) return v;
    final m = Map<String, dynamic>.from(v as Map);
    if (m.containsKey('stringValue'))    return m['stringValue'];
    if (m.containsKey('integerValue'))   return int.tryParse(m['integerValue'].toString()) ?? m['integerValue'];
    if (m.containsKey('doubleValue'))    return m['doubleValue'];
    if (m.containsKey('booleanValue'))   return m['booleanValue'];
    if (m.containsKey('nullValue'))      return null;
    if (m.containsKey('timestampValue')) return m['timestampValue'];
    if (m.containsKey('arrayValue')) {
      final vals = (m['arrayValue']['values'] as List? ?? []);
      return vals.map(_val).toList();
    }
    if (m.containsKey('mapValue')) {
      return _fields(Map<String, dynamic>.from(m['mapValue']['fields'] as Map? ?? {}));
    }
    return v.toString();
  }

  static Map<String, dynamic> _fields(Map<String, dynamic> f) =>
      f.map((k, v) => MapEntry(k, _val(v)));

  static Map<String, dynamic> _doc(Map<String, dynamic> doc) {
    final id     = (doc['name'] as String).split('/').last;
    final parsed = _fields(Map<String, dynamic>.from(doc['fields'] as Map? ?? {}));
    return {...parsed, 'id': id, 'userId': id, 'adminId': id};
  }

  // ── Query collection by equbLevel or level field ──────────────────────────
  static Future<List<Map<String, dynamic>>> _queryLevel(
      String collection, String level) async {
    final token = await _getToken();
    if (token == null) return [];

    final url  = 'https://firestore.googleapis.com/v1/projects/$_P'
                 '/databases/(default)/documents:runQuery';
    final hdrs = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

    final results = <Map<String, dynamic>>[];
    final seen    = <String>{};

    // Try both equbLevel and level fields (deduplicate by doc ID)
    for (final field in ['equbLevel', 'level']) {
      try {
        final body = jsonEncode({
          'structuredQuery': {
            'from': [{'collectionId': collection}],
            'where': {
              'fieldFilter': {
                'field': {'fieldPath': field},
                'op'   : 'EQUAL',
                'value': {'stringValue': level},
              }
            }
          }
        });
        final resp = await http.post(Uri.parse(url), headers: hdrs, body: body)
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200) {
          final rows = jsonDecode(resp.body) as List;
          for (final row in rows) {
            final docNode = (row as Map<String, dynamic>)['document'];
            if (docNode == null) continue;
            final parsed = _doc(Map<String, dynamic>.from(docNode as Map));
            // Filter deleted client-side
            if ((parsed['status'] ?? 'active').toString() == 'deleted') continue;
            final id = (parsed['id'] ?? '').toString();
            if (id.isNotEmpty && !seen.contains(id)) {
              seen.add(id);
              results.add(parsed);
            }
          }
        }
      } catch (e) {
        debugPrint('[FirestoreDirect] _queryLevel $field error: $e');
      }
    }
    return results;
  }

  // ── Get all docs from a collection (for admins list) ─────────────────────
  static Future<List<Map<String, dynamic>>> _getAll(String collection) async {
    final token = await _getToken();
    if (token == null) return [];
    try {
      final url  = 'https://firestore.googleapis.com/v1/projects/$_P'
                   '/databases/(default)/documents/$collection?pageSize=100';
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final docs = (data['documents'] as List? ?? []);
      return docs
          .map((d) => _doc(Map<String, dynamic>.from(d as Map)))
          .where((m) => (m['status'] ?? 'active').toString() != 'deleted')
          .toList();
    } catch (e) {
      debugPrint('[FirestoreDirect] _getAll $collection error: $e');
      return [];
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getUsersByLevel(String level) async {
    final lvl = level.toLowerCase().replaceAll('equb_', '').trim();
    final list = await _queryLevel('users', lvl);
    debugPrint('[FirestoreDirect] getUsersByLevel $lvl → ${list.length}');
    return list;
  }

  static Future<List<Map<String, dynamic>>> getDrawHistory(String level) async {
    final lvl  = level.toLowerCase().replaceAll('equb_', '').trim();
    final list = await _queryLevel('draws', lvl);
    for (final item in list) { item['drawId'] = item['id']; }
    list.sort((a, b) =>
        (b['drawNumber']?.toString() ?? '0').padLeft(6, '0')
        .compareTo((a['drawNumber']?.toString() ?? '0').padLeft(6, '0')));
    debugPrint('[FirestoreDirect] getDrawHistory $lvl → ${list.length}');
    return list;
  }

  static Future<List<Map<String, dynamic>>> getPaymentsByLevel(String level) async {
    final lvl  = level.toLowerCase().replaceAll('equb_', '').trim();
    final list = await _queryLevel('payments', lvl);
    for (final item in list) { item['paymentId'] = item['id']; }
    list.sort((a, b) =>
        (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));
    debugPrint('[FirestoreDirect] getPaymentsByLevel $lvl → ${list.length}');
    return list;
  }

  // ── Public token accessor (for external callers like PaymentScreen) ────────
  static Future<String?> getAdminToken() => _getToken();

  // ── Fetch a single document by full REST URL ──────────────────────────────
  static Future<Map<String, dynamic>?> getDocument(String url, String token) async {
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[FirestoreDirect] getDocument error: $e');
    }
    return null;
  }

  // ── Parse Firestore fields map into plain Dart map ────────────────────────
  static Map<String, dynamic> parseDocFields(Map<String, dynamic> fields) =>
      _fields(fields);

  static Future<List<Map<String, dynamic>>> getAdmins({String? level}) async {
    final all = await _getAll('admins');
    if (level == null) return all;
    final lvl = level.toLowerCase();
    return all.where((a) {
      final aLvl = (a['level'] ?? a['equbLevel'] ?? '').toString().toLowerCase();
      return aLvl == lvl;
    }).toList();
  }
}
