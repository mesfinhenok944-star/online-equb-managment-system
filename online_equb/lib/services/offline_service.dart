import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Offline & Caching Service for Online Equb
/// Provides local caching for users, payments, and draw history per level,
/// queues offline payment submissions and admin approvals/rejections,
/// and automatically synchronizes when connectivity is restored.
class OfflineService {
  static const String _queuedPaymentsKey = 'offline_payments_queue_v1';
  static const String _queuedVerificationsKey = 'offline_verifications_queue_v1';
  static const String _prefixUsers = 'cached_users_level_';
  static const String _prefixPayments = 'cached_payments_level_';
  static const String _prefixDrawHistory = 'cached_history_level_';

  static bool _isOnline = true;
  static bool get isOnline => _isOnline;

  static final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();
  static Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  /// Initialize Firestore offline persistence and start background sync listener
  static Future<void> init() async {
    try {
      if (!kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      }
    } catch (e) {
      debugPrint('[OfflineService] Firestore persistence config info: $e');
    }

    // Check connectivity once and start periodic check
    await checkConnectivity();
    Timer.periodic(const Duration(seconds: 15), (_) => checkConnectivity());
  }

  /// Perform active internet connectivity check
  static Future<bool> checkConnectivity() async {
    bool previous = _isOnline;
    try {
      if (kIsWeb) {
        _isOnline = true;
      } else {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      }
    } catch (_) {
      _isOnline = false;
    }

    if (previous != _isOnline) {
      _connectivityController.add(_isOnline);
      if (_isOnline) {
        debugPrint('[OfflineService] Internet restored. Syncing offline queue...');
        syncOfflineQueues();
      }
    }
    return _isOnline;
  }

  // ──────────────────────────────── CACHING METHODS ─────────────────────────

  /// Cache list of members for a specific Equb level
  static Future<void> cacheUsers(String level, List<Map<String, dynamic>> users) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefixUsers${level.toLowerCase().trim()}';
      await prefs.setString(key, jsonEncode(users));
    } catch (e) {
      debugPrint('[OfflineService] cacheUsers error: $e');
    }
  }

  static const String _keyAdmins = 'cached_admins_list_v1';

  /// Cache list of admins locally for full offline access
  static Future<void> cacheAdmins(List<Map<String, dynamic>> admins) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAdmins, jsonEncode(admins));
    } catch (e) {
      debugPrint('[OfflineService] cacheAdmins error: $e');
    }
  }

  /// Retrieve cached list of admins
  static Future<List<Map<String, dynamic>>> getCachedAdmins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyAdmins);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[OfflineService] getCachedAdmins error: $e');
    }
    return [];
  }

  /// Save or update an admin in local offline cache
  static Future<void> saveAdminOffline(Map<String, dynamic> adminData) async {
    try {
      final list = await getCachedAdmins();
      final email = (adminData['email'] ?? '').toString().trim().toLowerCase();
      final username = (adminData['username'] ?? '').toString().trim().toLowerCase();
      final adminId = (adminData['adminId'] ?? adminData['id'] ?? 'admin_${DateTime.now().millisecondsSinceEpoch}').toString();

      final newItem = <String, dynamic>{
        'adminId': adminId,
        'id': adminId,
        'email': email,
        'username': username,
        'firstName': adminData['firstName'] ?? '',
        'middleName': adminData['middleName'] ?? '',
        'lastName': adminData['lastName'] ?? '',
        'fullName': adminData['fullName'] ?? '$username Admin',
        'level': (adminData['level'] ?? adminData['equbLevel'] ?? 'low').toString().toLowerCase(),
        'equbLevel': (adminData['level'] ?? adminData['equbLevel'] ?? 'low').toString().toLowerCase(),
        'role': 'admin',
        'status': 'active',
        'password': adminData['password'] ?? 'admin123',
        'phone': adminData['phone'] ?? '',
        'address': adminData['address'] ?? '',
        'updatedAt': DateTime.now().toIso8601String(),
      };

      list.removeWhere((a) {
        final aEmail = (a['email'] ?? '').toString().trim().toLowerCase();
        final aUser = (a['username'] ?? '').toString().trim().toLowerCase();
        final aId = (a['adminId'] ?? a['id'] ?? '').toString();
        return (email.isNotEmpty && aEmail == email) ||
            (username.isNotEmpty && aUser == username) ||
            aId == adminId;
      });

      list.add(newItem);
      await cacheAdmins(list);
    } catch (e) {
      debugPrint('[OfflineService] saveAdminOffline error: $e');
    }
  }

  /// Save or update a member in local offline cache for a level
  static Future<void> saveUserOffline(String level, Map<String, dynamic> userData) async {
    try {
      final lvl = level.toLowerCase().replaceAll('equb_', '').trim();
      final users = await getCachedUsers(lvl);
      final email = (userData['email'] ?? '').toString().trim().toLowerCase();
      final uniqueId = (userData['uniqueId'] ?? '').toString().trim();
      final userId = (userData['userId'] ?? userData['id'] ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();

      final firstName = (userData['firstName'] ?? '').toString().trim();
      final middleName = (userData['middleName'] ?? '').toString().trim();
      final lastName = (userData['lastName'] ?? '').toString().trim();
      final fullName = (userData['fullName'] ?? '$firstName $middleName $lastName').toString().trim();

      final newItem = <String, dynamic>{
        'userId': userId,
        'id': userId,
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'fullName': fullName.isEmpty ? email : fullName,
        'email': email,
        'phoneNumber': userData['phoneNumber'] ?? userData['phone'] ?? '',
        'uniqueId': uniqueId,
        'equbLevel': lvl,
        'level': lvl,
        'adminId': userData['adminId'] ?? '',
        'role': 'user',
        'status': userData['status'] ?? 'active',
        'hasWon': userData['hasWon'] ?? false,
        'participationHistory': userData['participationHistory'] ?? [],
        'balance': userData['balance'] ?? 0,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      users.removeWhere((u) {
        final uEmail = (u['email'] ?? '').toString().trim().toLowerCase();
        final uUnique = (u['uniqueId'] ?? '').toString().trim();
        final uId = (u['userId'] ?? u['id'] ?? '').toString();
        return (email.isNotEmpty && uEmail == email) ||
            (uniqueId.isNotEmpty && uUnique == uniqueId) ||
            uId == userId;
      });

      users.add(newItem);
      await cacheUsers(lvl, users);
    } catch (e) {
      debugPrint('[OfflineService] saveUserOffline error: $e');
    }
  }

  /// Retrieve cached list of members for a level
  static Future<List<Map<String, dynamic>>> getCachedUsers(String level) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefixUsers${level.toLowerCase().trim()}';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[OfflineService] getCachedUsers error: $e');
    }
    return [];
  }

  /// Cache list of payments for a level
  static Future<void> cachePayments(String level, List<Map<String, dynamic>> payments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefixPayments${level.toLowerCase().trim()}';
      await prefs.setString(key, jsonEncode(payments));
    } catch (e) {
      debugPrint('[OfflineService] cachePayments error: $e');
    }
  }

  /// Retrieve cached payments for a level
  static Future<List<Map<String, dynamic>>> getCachedPayments(String level) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefixPayments${level.toLowerCase().trim()}';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[OfflineService] getCachedPayments error: $e');
    }
    return [];
  }

  /// Cache draw history for a level
  static Future<void> cacheDrawHistory(String level, List<Map<String, dynamic>> history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefixDrawHistory${level.toLowerCase().trim()}';
      await prefs.setString(key, jsonEncode(history));
    } catch (e) {
      debugPrint('[OfflineService] cacheDrawHistory error: $e');
    }
  }

  /// Retrieve cached draw history for a level
  static Future<List<Map<String, dynamic>>> getCachedDrawHistory(String level) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefixDrawHistory${level.toLowerCase().trim()}';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[OfflineService] getCachedDrawHistory error: $e');
    }
    return [];
  }

  // ──────────────────────────────── OFFLINE QUEUE ────────────────────────────

  /// Queue a payment submission when device is offline
  static Future<void> queueOfflinePayment(Map<String, dynamic> paymentData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queuedPaymentsKey);
      List<Map<String, dynamic>> queue = [];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          queue = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }

      final offlineItem = Map<String, dynamic>.from(paymentData);
      offlineItem['paymentId'] = 'offline_${DateTime.now().millisecondsSinceEpoch}';
      offlineItem['status'] = 'pending_verification';
      offlineItem['isOfflineQueued'] = true;
      offlineItem['queuedAt'] = DateTime.now().toIso8601String();

      queue.add(offlineItem);
      await prefs.setString(_queuedPaymentsKey, jsonEncode(queue));

      // Also add to level cached payments list so user/admin immediately sees it
      final level = (paymentData['equbLevel'] ?? 'low').toString().toLowerCase();
      final cached = await getCachedPayments(level);
      cached.insert(0, offlineItem);
      await cachePayments(level, cached);
    } catch (e) {
      debugPrint('[OfflineService] queueOfflinePayment error: $e');
    }
  }

  /// Queue an admin verification (Approve/Reject) when device is offline
  static Future<void> queueOfflineVerification({
    required String paymentId,
    required String status,
    String rejectionReason = '',
    String adminId = 'admin',
    String level = 'low',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queuedVerificationsKey);
      List<Map<String, dynamic>> queue = [];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          queue = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }

      queue.add({
        'paymentId': paymentId,
        'status': status,
        'rejectionReason': rejectionReason,
        'adminId': adminId,
        'queuedAt': DateTime.now().toIso8601String(),
      });

      await prefs.setString(_queuedVerificationsKey, jsonEncode(queue));

      // Update local cached payments for this level immediately
      final cached = await getCachedPayments(level);
      for (final p in cached) {
        if ((p['paymentId'] ?? p['id']) == paymentId) {
          p['status'] = status;
          p['rejectionReason'] = rejectionReason;
          p['verifiedByAdminId'] = adminId;
          p['verifiedAt'] = DateTime.now().toIso8601String();
        }
      }
      await cachePayments(level, cached);
    } catch (e) {
      debugPrint('[OfflineService] queueOfflineVerification error: $e');
    }
  }

  /// Flush and synchronize all pending offline payments & verifications with backend
  static Future<void> syncOfflineQueues() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Sync pending payments queue via REST API → Firestore SDK fallback
      final rawPayments = prefs.getString(_queuedPaymentsKey);
      if (rawPayments != null && rawPayments.isNotEmpty) {
        final decoded = jsonDecode(rawPayments);
        if (decoded is List && decoded.isNotEmpty) {
          final List<Map<String, dynamic>> remaining = [];
          for (final item in decoded) {
            final payData = Map<String, dynamic>.from(item as Map);
            try {
              final clean = Map<String, dynamic>.from(payData);
              clean.remove('isOfflineQueued');
              clean.remove('queuedAt');
              if (clean['paymentId']?.toString().startsWith('offline_') == true) {
                clean.remove('paymentId');
              }
              // Try REST API first (backend has live Firestore)
              bool synced = false;
              try {
                final res = await http.Client().post(
                  Uri.parse('http://localhost:8080/api/v1/payments/submit'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(clean),
                );
                if (res.statusCode == 200 || res.statusCode == 201) synced = true;
              } catch (_) {}
              // Fallback: Firestore SDK
              if (!synced) {
                try {
                  final db = FirebaseFirestore.instance;
                  await db.collection('payments').add({
                    ...clean,
                    'status': 'pending_verification',
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  synced = true;
                } catch (_) {}
              }
              if (!synced) remaining.add(payData);
            } catch (e) {
              debugPrint('[OfflineService] Failed sync item, re-queuing: $e');
              remaining.add(payData);
            }
          }
          await prefs.setString(_queuedPaymentsKey, jsonEncode(remaining));
        }
      }

      // 2. Sync pending verifications queue via REST API → Firestore SDK fallback
      final rawVerifications = prefs.getString(_queuedVerificationsKey);
      if (rawVerifications != null && rawVerifications.isNotEmpty) {
        final decoded = jsonDecode(rawVerifications);
        if (decoded is List && decoded.isNotEmpty) {
          final List<Map<String, dynamic>> remainingV = [];
          for (final item in decoded) {
            final vData = Map<String, dynamic>.from(item as Map);
            final pId = (vData['paymentId'] ?? '').toString();
            if (pId.isEmpty || pId.startsWith('offline_')) continue;

            bool synced = false;
            // Try REST API first
            try {
              final res = await http.Client().post(
                Uri.parse('http://localhost:8080/api/v1/payments/verify'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(vData),
              );
              if (res.statusCode == 200 || res.statusCode == 201) synced = true;
            } catch (_) {}
            // Fallback: Firestore SDK
            if (!synced) {
              try {
                final db = FirebaseFirestore.instance;
                await db.collection('payments').doc(pId).update({
                  'status': vData['status'],
                  'rejectionReason': vData['rejectionReason'] ?? '',
                  'verifiedByAdminId': vData['adminId'] ?? 'admin',
                  'verifiedAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                synced = true;
              } catch (e) {
                debugPrint('[OfflineService] Failed verification sync, re-queuing: $e');
              }
            }
            if (!synced) remainingV.add(vData);
          }
          await prefs.setString(_queuedVerificationsKey, jsonEncode(remainingV));
        }
      }
    } catch (e) {
      debugPrint('[OfflineService] syncOfflineQueues error: $e');
    }
  }
}
