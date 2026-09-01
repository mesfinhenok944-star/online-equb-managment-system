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
  static const _P = 'online-equb-managment-sy-b5517';
  // ignore: constant_identifier_names
  static const _E = 'firebase-adminsdk-fbsvc@online-equb-managment-sy-b5517.iam.gserviceaccount.com';

  // Service account private key — embedded so phone needs no server
  // ignore: constant_identifier_names
  static const _K =
      '-----BEGIN PRIVATE KEY-----\n'
      'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCsg3cPlW36SxJK\n'
      'rbMBkcbpSCZGxifKhsYA2z5IKtAW6qUf5uiZvSImJzTK8TCQ6qYh095vJ2OkcwiG\n'
      'doC7+VJmZysGrnA8XWN2WqJL7GrXdeqwwS1Vkx3mfTYSLBEPCKVV2pWTiNZX7yqd\n'
      '+0hMSgm2bcguP0R/c7obtBDSX+wNKi3zQpdl22I26xR1vnTtjXPTHnHqJTh/gd1p\n'
      'GzgW1xoD6bwvp+5WDHXdM+y4WX9uYEo6Zq9/9z8ZZwRrtgwq8fE2hh0ghjxnxyK5\n'
      'DyEYvzwXs9lb/m8+C38tNEUXjyshob7eTevh8aFjFq8ovFc7V3eSJJA+Qo2jk4EQ\n'
      'UoCbG6JjAgMBAAECggEAF4/RGCDJp5DPS8HTnBhD+aKwD6SK1L95la5cIFEwoKCl\n'
      'sui/xhet7VYXgMxWXMSfsikUzUus8U4A0RSoWoQf+/qFRuFWVPhQWF7iocoFga4K\n'
      'Qt/viCuSvuNFGlBIeCwvIL29Bix/Uf1JbdBfPIQ0NWVjHOXpPhsZRSVf0svlGpr5\nwkupjGYprwGmK9vQG2oHIy6AD+1nER3L9sJRay6GUURR0QhtDbFEWYZBRnuidsxn\n'
      'KxpLgKj+EsArFkK91E1wQaAt7VceJ4sPoNeSVMOyfVVe0pMsmFxjW1N+ruKiNALx\n'
      'z0oiAwK3tRsHKQA1MLUUUb8L9ZvRTIxqLmn/++RLUQKBgQDZAeAWr7BbQAOQUlKg\n'
      'soryBOKM+uhZ5i9oNQJyJ8EogCkKMKcfOrkSfB4YuNlWPiGV5GT4miRVRIRlTafD\n'
      'e4k9YSdLFPYkyY3T2s5vm4dpXHnlLs63R6BkUOcJZMr7ziYDqeiruVdz80phWE2K\n'
      '61mlfYKl24ZxBCYnoHH9HIJieQKBgQDLgus+nWiZ2Zu4faBlp+MApCxqJE5uINVj\n'
      'FW3pJ6/iP4XrakaBT5j/8UUcIph4+HMod3v2eiiivSs2oPavrFABKp1wY628iUhK\n'
      'JuQyCYeU7O/9Rd5RVHTHpGvVyPrHsHVNJQKg7/tPymHgC8SB3mJKzo03rFRTESZJ\n'
      'I8ufyH5UuwKBgG5rUN3aSa80tFuEN/0CvEaHi8tWhFHyGV850ePKLLPx+m/v76mp\n'
      'VLB+LUZBEH2cobRGgcYpkKE+euudBucl/eAYhkjjApgXYq5Q4MfTaKSI5JFkLtT9\n'
      'gjRpIhYajlpwO9GTbAutBD3AprE/oD02oefeJFNGj3MEPHHfZwD2t7VpAoGBALrt\n'
      '3PCdmye91qgGVF8rb3n2UomIIbZMWFRzqYpAlvCFEphi/LHoEAv/bFBkgpKS+wvP\n'
      'fECwgkTA50F9ZjmEV9RKdWR3WmzT2F+sC2zejffADswf8g3YOo/qOdabjaYAMi6S\n'
      '8TAsXjUzGuW1SWFUiApYYSQjGS1XkkgaJf31JfzjAoGATweFLyGUMbHe/P44tf4v\n'
      '6W6OCEZgKEo6zYd/8+4wPegrRkun3wqcWGKhG60itZ8Um6epOYgyGBk0rseUmMKO\n'
      'Ntuu6rmCY9F8tFK7IMZXQCCYfZOPSVcnDjYgrxrRrog5UATeil9O2donAahJVw9h\n'
      'NOKn7PwKrqOlVLj9UGtF9K8=\n'
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

  // ── Public token accessor ────────────────────────────────────────────────
  static Future<String?> getAdminToken() => _getToken();

  // ── Fetch a single document ───────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getDocument(String url, String token) async {
    try {
      final resp = await http.get(Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) { debugPrint('[FirestoreDirect] getDocument: $e'); }
    return null;
  }

  // ── Parse Firestore fields ────────────────────────────────────────────────
  static Map<String, dynamic> parseDocFields(Map<String, dynamic> fields) =>
      _fields(fields);

  // ── Update (PATCH) a document — bypasses security rules ──────────────────
  // fieldValues: plain Dart map (String/bool/int/double/null).
  // Only the specified fields are updated (fieldMask).
  static Future<bool> updateDocument(
      String collection, String docId, Map<String, dynamic> fieldValues) async {
    try {
      final token = await _getToken();
      if (token == null) return false;

      final url = 'https://firestore.googleapis.com/v1/projects/$_P'
          '/databases/(default)/documents/$collection/$docId';

      // Build updateMask query params
      final maskParams = fieldValues.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');

      // Build Firestore fields payload
      final fields = <String, dynamic>{};
      fieldValues.forEach((k, v) {
        if (v == null)        fields[k] = {'nullValue': null};
        else if (v is bool)   fields[k] = {'booleanValue': v};
        else if (v is int)    fields[k] = {'integerValue': v.toString()};
        else if (v is double) fields[k] = {'doubleValue': v};
        else                  fields[k] = {'stringValue': v.toString()};
      });

      final resp = await http.patch(
        Uri.parse('$url?$maskParams'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'fields': fields}),
      ).timeout(const Duration(seconds: 12));

      debugPrint('[FirestoreDirect] updateDocument $collection/$docId → ${resp.statusCode}');
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[FirestoreDirect] updateDocument error: $e');
      return false;
    }
  }

  // ── Add (POST) a new document to a collection ─────────────────────────────
  // Returns the new document ID or null on failure.
  static Future<String?> addDocument(
      String collection, Map<String, dynamic> fieldValues) async {
    try {
      final token = await _getToken();
      if (token == null) return null;

      final url = 'https://firestore.googleapis.com/v1/projects/$_P'
          '/databases/(default)/documents/$collection';

      // Convert values to Firestore format
      final fields = <String, dynamic>{};
      fieldValues.forEach((k, v) {
        if (v == null)           fields[k] = {'nullValue': null};
        else if (v is bool)      fields[k] = {'booleanValue': v};
        else if (v is int)       fields[k] = {'integerValue': v.toString()};
        else if (v is double)    fields[k] = {'doubleValue': v};
        else if (v is List)      fields[k] = {'arrayValue': {'values': v.map((e) => {'stringValue': e.toString()}).toList()}};
        else                     fields[k] = {'stringValue': v.toString()};
      });

      final resp = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'fields': fields}),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final name = (data['name'] as String?) ?? '';
        final id = name.split('/').last;
        debugPrint('[FirestoreDirect] addDocument $collection → $id');
        return id;
      }
      debugPrint('[FirestoreDirect] addDocument $collection → ${resp.statusCode}');
    } catch (e) {
      debugPrint('[FirestoreDirect] addDocument error: $e');
    }
    return null;
  }

  // ── Get notifications for a user (by userId or email) ──────────────────────
    static Future<List<Map<String, dynamic>>> getNotificationsForUser({
    required String userId,
    required String userEmail,
    String userPhone = '',
  }) async {
    final results = <Map<String, dynamic>>[];
    final seen    = <String>{};

    // Normalise phone number
    String normPhone = '';
    if (userPhone.isNotEmpty) {
      normPhone = userPhone.trim().replaceAll(RegExp(r'\s+'), '');
      if (normPhone.startsWith('09') || normPhone.startsWith('07')) {
        normPhone = '+251${normPhone.substring(1)}';
      } else if (normPhone.startsWith('251') && !normPhone.startsWith('+')) {
        normPhone = '+$normPhone';
      }
    }

    for (final entry in [
      if (userId.isNotEmpty)    {'field': 'userId',    'value': userId},
      if (userEmail.isNotEmpty) {'field': 'userEmail', 'value': userEmail},
      if (normPhone.isNotEmpty) {'field': 'userPhone', 'value': normPhone},
    ]) {
      try {
        final list = await _queryByField(
            'notifications', entry['field']!, entry['value']!);
        for (final item in list) {
          final id = (item['id'] ?? '').toString();
          if (id.isNotEmpty && !seen.contains(id)) {
            seen.add(id);
            results.add(item);
          }
        }
      } catch (_) {}
    }
    return results;
  }

  // ── Query collection by a single field value ─────────────────────────────
  static Future<List<Map<String, dynamic>>> _queryByField(
      String collection, String field, String value) async {
    final token = await _getToken();
    if (token == null) return [];
    final url  = 'https://firestore.googleapis.com/v1/projects/$_P'
                 '/databases/(default)/documents:runQuery';
    final hdrs = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final body = jsonEncode({
      'structuredQuery': {
        'from': [{'collectionId': collection}],
        'where': {'fieldFilter': {
          'field': {'fieldPath': field},
          'op':    'EQUAL',
          'value': {'stringValue': value},
        }},
        'orderBy': [{'field': {'fieldPath': 'createdAt'}, 'direction': 'DESCENDING'}],
        'limit': 100,
      }
    });
    try {
      final resp = await http.post(Uri.parse(url), headers: hdrs, body: body)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final rows = jsonDecode(resp.body) as List;
        final out  = <Map<String, dynamic>>[];
        for (final row in rows) {
          final docNode = (row as Map<String, dynamic>)['document'];
          if (docNode == null) continue;
          final parsed = _doc(Map<String, dynamic>.from(docNode as Map));
          out.add(parsed);
        }
        return out;
      }
    } catch (e) { debugPrint('[FirestoreDirect] _queryByField: $e'); }
    return [];
  }

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
