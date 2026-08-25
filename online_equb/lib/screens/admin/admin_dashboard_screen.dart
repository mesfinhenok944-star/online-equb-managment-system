import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import 'level_dashboard_screen.dart';

/// Admin hub — loads the level dashboard for the currently-logged-in admin.
///
/// Each admin sees ONLY their own assigned equb level:
///   • Low admin     → sees only low level members, payments, history
///   • Medium admin  → sees only medium level members, payments, history
///   • High admin    → sees only high level members, payments, history
///
/// Multiple admins assigned to the same level share the same data
/// (this is by design — they co-manage the same equb pool).
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _errorMsg;
  Map<String, dynamic>? _adminProfile;
  Map<String, List<Map<String, dynamic>>> _usersByLevel = {};
  bool _isAmharic = false;

  String t(String en, String am) => _isAmharic ? am : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final authUser = auth.user ?? {};

      // ── Resolve admin Firestore document ──────────────────────────────────
      String adminDocId = (authUser['adminId'] ?? authUser['id'] ?? '').toString().trim();
      Map<String, dynamic>? profile;

      // 1. Try by Firestore doc ID (fastest — set during login)
      if (adminDocId.isNotEmpty && !adminDocId.startsWith('user_') &&
          !adminDocId.startsWith('offline_')) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('admins')
              .doc(adminDocId)
              .get()
              .timeout(const Duration(seconds: 6));
          if (doc.exists) {
            profile = {...doc.data()!, 'adminId': doc.id, 'id': doc.id};
          }
        } catch (_) {}
      }

      // 2. Try by email (when adminDocId not set or stale)
      if (profile == null) {
        final email = (authUser['email'] ?? '').toString().trim().toLowerCase();
        if (email.isNotEmpty) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection('admins')
                .where('email', isEqualTo: email)
                .where('status', isEqualTo: 'active')
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 6));
            if (snap.docs.isNotEmpty) {
              adminDocId = snap.docs.first.id;
              profile = {...snap.docs.first.data(), 'adminId': adminDocId, 'id': adminDocId};
              // Patch adminId into auth so future loads are instant
              auth.refreshUser({...authUser, 'adminId': adminDocId, 'id': adminDocId});
            }
          } catch (_) {}
        }
      }

      // 3. Try by username
      if (profile == null) {
        final username = (authUser['username'] ?? '').toString().trim().toLowerCase();
        if (username.isNotEmpty) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection('admins')
                .where('username', isEqualTo: username)
                .where('status', isEqualTo: 'active')
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 6));
            if (snap.docs.isNotEmpty) {
              adminDocId = snap.docs.first.id;
              profile = {...snap.docs.first.data(), 'adminId': adminDocId, 'id': adminDocId};
              auth.refreshUser({...authUser, 'adminId': adminDocId, 'id': adminDocId});
            }
          } catch (_) {}
        }
      }

      // 4. Use authUser directly if Firestore not available (offline)
      if (profile == null && authUser.isNotEmpty) {
        profile = Map<String, dynamic>.from(authUser);
        if (adminDocId.isEmpty) {
          adminDocId = (authUser['uid'] ?? authUser['userId'] ?? '').toString();
        }
      }

      // 5. If still nothing — show error
      if (profile == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorMsg = t(
              'Admin profile not found.\nPlease contact your Super Admin.',
              'የአስተዳዳሪ መገለጫ አልተገኘም።\nሱፐር አስተዳዳሪዎን ያናግሩ።',
            );
          });
        }
        return;
      }

      // ── Determine the admin's assigned level ──────────────────────────────
      final level = (profile['level'] ??
              profile['assignedLevel'] ??
              profile['equbLevel'] ??
              authUser['level'] ??
              authUser['equbLevel'] ??
              'low')
          .toString()
          .toLowerCase()
          .replaceAll('equb_', '')
          .trim();

      // ── Load data ONLY for this admin's level (level isolation) ───────────
      final users  = await RoleManagementService.getUsersByLevel(level);
      final history = await RoleManagementService.getDrawHistory(level);

      if (!mounted) return;
      setState(() {
        _adminProfile = {
          ...profile!,
          'adminId': adminDocId,
          'id': adminDocId,
          'level': level,
          'equbLevel': level,
          'drawHistory': history,
          'role': 'admin',
        };
        _usersByLevel = {level: users};
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminDashboard._load] error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = t(
            'Failed to load dashboard: $e',
            'ዳሽቦርድ መጫን አልተቻለም። ዳግም ሞክር።',
          );
        });
      }
    }
  }

  String get _assignedLevel =>
      (_adminProfile?['level'] ?? _adminProfile?['equbLevel'] ?? 'low')
          .toString()
          .toLowerCase();

  Color get _levelColor {
    switch (_assignedLevel) {
      case 'medium': return AppColors.medium;
      case 'high':   return AppColors.high;
      default:       return AppColors.low;
    }
  }

  String get _levelLabel {
    if (_isAmharic) {
      switch (_assignedLevel) {
        case 'medium': return 'መካከለኛ';
        case 'high':   return 'ከፍተኛ';
        default:       return 'ዝቅተኛ';
      }
    }
    switch (_assignedLevel) {
      case 'medium': return 'Medium';
      case 'high':   return 'High';
      default:       return 'Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(t('Loading Dashboard…', 'ዳሽቦርድ በመጫን ላይ…')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Text(_isAmharic ? 'EN' : 'አማ',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              onPressed: () => setState(() => _isAmharic = !_isAmharic),
            ),
          ],
        ),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(t('Loading your admin dashboard…', 'ዳሽቦርድ በመጫን ላይ…'),
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(t('Connecting to Firestore…', 'ከ Firestore ጋር በማገናኘት ላይ…'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ),
      );
    }

    // Error state
    if (_errorMsg != null || _adminProfile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(t('Admin Dashboard', 'አስተዳዳሪ ዳሽቦርድ')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Text(_isAmharic ? 'EN' : 'አማ',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              onPressed: () => setState(() => _isAmharic = !_isAmharic),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.admin_panel_settings_rounded,
                  size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              Text(
                _errorMsg ?? t('Admin profile not found.', 'የአስተዳዳሪ መገለጫ አልተገኘም።'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t('Retry / Refresh', 'ዳግም ሞክር')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 48),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  final auth = context.read<AuthProvider>();
                  await auth.logout();
                  if (mounted) context.go('/login');
                },
                child: Text(t('Logout and try again', 'ይውጡ እና ዳግም ሞክሩ'),
                    style: const TextStyle(color: AppColors.error)),
              ),
            ]),
          ),
        ),
      );
    }

    // Dashboard loaded
    final resolvedAdminId =
        (_adminProfile!['adminId'] ?? _adminProfile!['id'] ?? '').toString();

    return LevelDashboardScreen(
      level: _assignedLevel,
      adminId: resolvedAdminId,
      data: _adminProfile!,
      allUsers: _usersByLevel[_assignedLevel] ?? [],
      onRefresh: _load,
      isAmharic: _isAmharic,
    );
  }
}
