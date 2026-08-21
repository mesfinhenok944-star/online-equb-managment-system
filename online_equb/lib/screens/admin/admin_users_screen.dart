import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '_invite_user_dialog.dart';
import '_select_level_dialog.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<dynamic> _users = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.adminGetUsers();
      if (mounted) {
        setState(() {
          _users = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<dynamic> get _filtered => _filter == 'all'
      ? _users
      : _users.where((u) => u['verificationStatus'] == _filter).toList();

  Future<void> _verify(String userId) async {
    await ApiService.adminVerifyUser(userId);
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ User verified'),
          backgroundColor: AppColors.success));
    }
  }

  Future<void> _suspend(String userId) async {
    await ApiService.adminSuspendUser(userId);
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('User suspended'), backgroundColor: AppColors.warning));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Users (${_users.length})'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/admin');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add User',
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (_) => const InviteUserDialog(),
              );
              if (result == true) _load();
            },
          )
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _chip('All', 'all'),
            const SizedBox(width: 8),
            _chip('Pending', 'pending'),
            const SizedBox(width: 8),
            _chip('Verified', 'verified'),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _userCard(_filtered[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _userCard(Map<String, dynamic> u) {
    final status = u['verificationStatus'] as String? ?? 'pending';
    final color = status == 'verified'
        ? AppColors.success
        : status == 'pending'
            ? AppColors.warning
            : AppColors.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Text((u['fullName'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(u['fullName'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(u['email'] ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(status,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.phone, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(u['phoneNumber'] ?? '',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(width: 16),
            const Icon(Icons.badge, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(u['role'] ?? '',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ]),
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _verify(u['userId'] ?? u['id'] ?? ''),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Verify'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _suspend(u['userId'] ?? u['id'] ?? ''),
                  icon:
                      const Icon(Icons.block, size: 16, color: AppColors.error),
                  label: const Text('Suspend',
                      style: TextStyle(color: AppColors.error)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Assign user to an EQUB level
                  final selected = await showDialog<String>(
                    context: context,
                    builder: (_) => const SelectLevelDialog(),
                  );
                  if (selected != null) {
                    final res = await ApiService.adminRegisterToLevel(u['uid'] ?? u['userId'] ?? u['id'], selected);
                    if (!mounted) return;
                    if (res['error'] != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.error));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Assigned successfully'), backgroundColor: AppColors.success));
                      _load();
                    }
                  }
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Assign to EQUB'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final sel = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
  }
}
