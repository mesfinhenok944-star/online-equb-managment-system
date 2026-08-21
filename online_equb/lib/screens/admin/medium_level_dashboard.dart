import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import 'level_dashboard_screen.dart';

class MediumLevelDashboardWrapper extends StatefulWidget {
  const MediumLevelDashboardWrapper({super.key});

  @override
  State<MediumLevelDashboardWrapper> createState() =>
      _MediumLevelDashboardWrapperState();
}

class _MediumLevelDashboardWrapperState
    extends State<MediumLevelDashboardWrapper> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await RoleManagementService.getUsersByLevel('medium');
    if (mounted) {
      setState(() {
        _users = users;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final adminId = auth.user?['adminId'] ?? auth.user?['uid'] ?? '';
    return _loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : LevelDashboardScreen(
            level: 'medium',
            adminId: adminId,
            data: const {},
            allUsers: _users,
            onRefresh: _load,
          );
  }
}
