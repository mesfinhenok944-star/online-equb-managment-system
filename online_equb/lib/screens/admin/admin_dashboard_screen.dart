import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import 'level_dashboard_screen.dart';

/// Admin hub: shows only the level(s) assigned to this admin.
/// If the admin has one level it goes straight into that level dashboard.
/// If the admin has multiple levels (future proof) it shows a selector.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  Map<String, dynamic>? _adminProfile;
  Map<String, List<Map<String, dynamic>>> _usersByLevel = {};
  final bool _isAmharic = false;

  String t(String en, String am) => _isAmharic ? am : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final user = auth.user;

    // Load admin profile from admins collection
    final adminId = user?['adminId'] ?? user?['uid'] ?? '';
    Map<String, dynamic>? adminProfile;

    if (adminId.isNotEmpty) {
      adminProfile = await RoleManagementService.getAdminById(adminId);
    }

    // Fallback: use auth user data
    adminProfile ??= user ?? {};

    final level = (adminProfile['level'] ?? adminProfile['assignedLevel'] ?? adminProfile['equbLevel'] ?? adminProfile['levelId'] ?? 'low').toString().toLowerCase();

    // Load users for this level
    final users = await RoleManagementService.getUsersByLevel(level);
    final history = await RoleManagementService.getDrawHistory(level);

    if (!mounted) return;
    setState(() {
      _adminProfile = {...adminProfile!, 'level': level, 'drawHistory': history};
      _usersByLevel = {level: users};
      _loading = false;
    });
  }

  String get _assignedLevel => (_adminProfile?['level'] ?? _adminProfile?['assignedLevel'] ?? 'low').toString().toLowerCase();

  Color get _levelColor {
    switch (_assignedLevel) {
      case 'medium':
        return AppColors.medium;
      case 'high':
        return AppColors.high;
      default:
        return AppColors.low;
    }
  }

  String get _levelLabel {
    if (_isAmharic) {
      switch (_assignedLevel) {
        case 'medium':
          return 'መካከለኛ';
        case 'high':
          return 'ከፍተኛ';
        default:
          return 'ዝቅተኛ';
      }
    }
    switch (_assignedLevel) {
      case 'medium':
        return 'Medium';
      case 'high':
        return 'High';
      default:
        return 'Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _adminProfile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(t('$_levelLabel Level Dashboard', '$_levelLabel ደረጃ ዳሽቦርድ')),
          backgroundColor: _levelColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return LevelDashboardScreen(
      level: _assignedLevel,
      adminId: _adminProfile?['adminId'] ?? _adminProfile?['uid'] ?? '',
      data: _adminProfile ?? {},
      allUsers: _usersByLevel[_assignedLevel] ?? [],
      onRefresh: _load,
      isAmharic: _isAmharic,
    );
  }
}
