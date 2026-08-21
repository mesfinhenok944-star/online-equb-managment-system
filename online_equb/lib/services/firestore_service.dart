import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference get _equbCol => _db.collection('equbs');

  /// Returns a list of equb documents as Map<String,dynamic>
  static Future<List<Map<String, dynamic>>> getEqubs() async {
    try {
      final snap = await _equbCol.orderBy('createdAt', descending: false).get();
      return snap.docs.map((d) {
        final m = d.data() as Map<String, dynamic>;
        m['id'] = d.id;
        return m;
      }).toList();
    } catch (e) {
      // propagate error to caller — caller may fallback to ApiService
      rethrow;
    }
  }

  /// Get a single equb by id
  static Future<Map<String, dynamic>?> getEqubById(String id) async {
    try {
      final doc = await _equbCol.doc(id).get();
      if (!doc.exists) return null;
      final m = doc.data() as Map<String, dynamic>;
      m['id'] = doc.id;
      return m;
    } catch (e) {
      rethrow;
    }
  }

  /// Create a new equb document. Returns generated id.
  static Future<String> createEqub(Map<String, dynamic> data) async {
    final now = DateTime.now();
    final payload = Map<String, dynamic>.from(data)
      ..putIfAbsent('createdAt', () => now.toIso8601String());
    final doc = await _equbCol.add(payload);
    return doc.id;
  }
}
