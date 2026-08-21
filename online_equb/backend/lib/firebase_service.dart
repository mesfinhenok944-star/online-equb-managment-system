import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FirebaseService
// Wraps the Firebase Firestore REST API and Firebase Auth REST API.
// No native Admin SDK required — works on any Dart server.
// ─────────────────────────────────────────────────────────────────────────────

class FirebaseService {
  static final _client = http.Client();

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Convert a Firestore REST document map to a plain Dart map.
  static Map<String, dynamic> _fromFirestore(
      Map<String, dynamic> doc, String docId) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};
    final result = <String, dynamic>{'id': docId};
    fields.forEach((key, value) {
      result[key] = _parseValue(value as Map<String, dynamic>);
    });
    return result;
  }

  static dynamic _parseValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue'].toString()) ?? 0;
    }
    if (value.containsKey('doubleValue')) return (value['doubleValue'] as num).toDouble();
    if (value.containsKey('booleanValue')) return value['booleanValue'] as bool;
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    if (value.containsKey('arrayValue')) {
      final values = (value['arrayValue']['values'] as List<dynamic>?) ?? [];
      return values.map((v) => _parseValue(v as Map<String, dynamic>)).toList();
    }
    if (value.containsKey('mapValue')) {
      return _fromFirestoreFields(
          value['mapValue']['fields'] as Map<String, dynamic>? ?? {});
    }
    return null;
  }

  static Map<String, dynamic> _fromFirestoreFields(
      Map<String, dynamic> fields) {
    final result = <String, dynamic>{};
    fields.forEach((k, v) => result[k] = _parseValue(v as Map<String, dynamic>));
    return result;
  }

  /// Convert a plain Dart value to a Firestore REST field value.
  static Map<String, dynamic> _toFirestoreValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double) return {'doubleValue': value};
    if (value is String) return {'stringValue': value};
    if (value is List) {
      return {
        'arrayValue': {
          'values': value.map(_toFirestoreValue).toList(),
        }
      };
    }
    if (value is Map) {
      return {
        'mapValue': {
          'fields': value.map(
              (k, v) => MapEntry(k.toString(), _toFirestoreValue(v))),
        }
      };
    }
    return {'stringValue': value.toString()};
  }

  /// Convert a plain Dart map to Firestore REST fields map.
  static Map<String, dynamic> _toFirestoreFields(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k, _toFirestoreValue(v)));
  }

  static String _docPath(String collection, String docId) =>
      '${Config.firestoreBase}/$collection/$docId';

  static String _colPath(String collection) =>
      '${Config.firestoreBase}/$collection';

  // ── Firestore CRUD ─────────────────────────────────────────────────────────

  /// Get all documents from a collection.
  static Future<List<Map<String, dynamic>>> getCollection(
      String collection) async {
    try {
      final url = Uri.parse('${_colPath(collection)}?key=${Config.webApiKey}');
      final res = await _client.get(url);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final docs = (body['documents'] as List<dynamic>?) ?? [];
      return docs.map((d) {
        final doc = d as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        return _fromFirestore(doc, docId);
      }).toList();
    } catch (e) {
      print('[Firestore] getCollection($collection) error: $e');
      return [];
    }
  }

  /// Get a single document.
  static Future<Map<String, dynamic>?> getDocument(
      String collection, String docId) async {
    try {
      final url = Uri.parse(
          '${_docPath(collection, docId)}?key=${Config.webApiKey}');
      final res = await _client.get(url);
      if (res.statusCode != 200) return null;
      final doc = jsonDecode(res.body) as Map<String, dynamic>;
      return _fromFirestore(doc, docId);
    } catch (e) {
      print('[Firestore] getDocument($collection/$docId) error: $e');
      return null;
    }
  }

  /// Query a collection by a single field value.
  static Future<List<Map<String, dynamic>>> queryCollection(
      String collection, String field, dynamic value) async {
    try {
      final url = Uri.parse(
          '${Config.firestoreBase}:runQuery?key=${Config.webApiKey}');
      final body = jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': collection}
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': field},
              'op': 'EQUAL',
              'value': _toFirestoreValue(value),
            }
          }
        }
      });
      final res = await _client.post(url,
          headers: {'Content-Type': 'application/json'}, body: body);
      if (res.statusCode != 200) return [];
      final results = jsonDecode(res.body) as List<dynamic>;
      return results
          .where((r) => (r as Map<String, dynamic>).containsKey('document'))
          .map((r) {
        final doc = (r as Map<String, dynamic>)['document']
            as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        return _fromFirestore(doc, docId);
      }).toList();
    } catch (e) {
      print('[Firestore] queryCollection($collection,$field) error: $e');
      return [];
    }
  }

  /// Create a new document (Firestore auto-generates the ID).
  static Future<String?> createDocument(
      String collection, Map<String, dynamic> data) async {
    try {
      final url = Uri.parse(
          '${_colPath(collection)}?key=${Config.webApiKey}');
      final body =
          jsonEncode({'fields': _toFirestoreFields(data)});
      final res = await _client.post(url,
          headers: {'Content-Type': 'application/json'}, body: body);
      if (res.statusCode != 200) return null;
      final doc = jsonDecode(res.body) as Map<String, dynamic>;
      final name = doc['name'] as String;
      return name.split('/').last;
    } catch (e) {
      print('[Firestore] createDocument($collection) error: $e');
      return null;
    }
  }

  /// Set a document with a specific ID (creates or overwrites).
  static Future<bool> setDocument(
      String collection, String docId, Map<String, dynamic> data) async {
    try {
      final url = Uri.parse(
          '${_docPath(collection, docId)}?key=${Config.webApiKey}');
      final body =
          jsonEncode({'fields': _toFirestoreFields(data)});
      final res = await _client.patch(url,
          headers: {'Content-Type': 'application/json'}, body: body);
      return res.statusCode == 200;
    } catch (e) {
      print('[Firestore] setDocument($collection/$docId) error: $e');
      return false;
    }
  }

  /// Update specific fields of a document (merge/patch).
  static Future<bool> updateDocument(
      String collection, String docId, Map<String, dynamic> data) async {
    try {
      final fieldMask = data.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
      final url = Uri.parse(
          '${_docPath(collection, docId)}?key=${Config.webApiKey}&$fieldMask');
      final body =
          jsonEncode({'fields': _toFirestoreFields(data)});
      final res = await _client.patch(url,
          headers: {'Content-Type': 'application/json'}, body: body);
      return res.statusCode == 200;
    } catch (e) {
      print('[Firestore] updateDocument($collection/$docId) error: $e');
      return false;
    }
  }

  /// Delete a document.
  static Future<bool> deleteDocument(
      String collection, String docId) async {
    try {
      final url = Uri.parse(
          '${_docPath(collection, docId)}?key=${Config.webApiKey}');
      final res = await _client.delete(url);
      return res.statusCode == 200;
    } catch (e) {
      print('[Firestore] deleteDocument($collection/$docId) error: $e');
      return false;
    }
  }

  // ── Firebase Auth REST ─────────────────────────────────────────────────────

  /// Sign up a new user with email + password.
  static Future<Map<String, dynamic>?> createAuthUser(
      String email, String password) async {
    try {
      final url = Uri.parse(
          '${Config.authBase}/accounts:signUp?key=${Config.webApiKey}');
      final res = await _client.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[FirebaseAuth] createAuthUser error: $e');
      return null;
    }
  }

  /// Sign in with email + password, returns idToken or null.
  static Future<Map<String, dynamic>?> signInWithPassword(
      String email, String password) async {
    try {
      final url = Uri.parse(
          '${Config.authBase}/accounts:signInWithPassword?key=${Config.webApiKey}');
      final res = await _client.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[FirebaseAuth] signInWithPassword error: $e');
      return null;
    }
  }
}
