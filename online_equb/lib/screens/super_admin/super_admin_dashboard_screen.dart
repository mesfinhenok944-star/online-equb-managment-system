import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState
    extends State<SuperAdminDashboardScreen> {
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  String _searchQuery = '';
  String _filterLevel = 'all';
  String _filterStatus = 'all';
  bool _isAmharic = false;

  // ── language helpers ──────────────────────────────────────────────────────
  String t(String en, String am) => _isAmharic ? am : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final admins = await RoleManagementService.getAdmins();
    if (!mounted) return;
    setState(() {
      _admins = admins;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    return _admins.where((a) {
      final q = _searchQuery.toLowerCase();
      final name = (a['fullName'] ?? '${a['firstName']} ${a['lastName']}')
          .toString()
          .toLowerCase();
      final email = (a['email'] ?? '').toString().toLowerCase();
      final username = (a['username'] ?? '').toString().toLowerCase();
      final matchSearch = q.isEmpty ||
          name.contains(q) ||
          email.contains(q) ||
          username.contains(q);

      final level = (a['level'] ?? 'low').toString();
      final matchLevel = _filterLevel == 'all' || level == _filterLevel;

      final status = (a['status'] ?? 'active').toString();
      final matchStatus = _filterStatus == 'all' || status == _filterStatus;

      return matchSearch && matchLevel && matchStatus;
    }).toList();
  }

  // ── stats ─────────────────────────────────────────────────────────────────
  int _countByLevel(String level) =>
      _admins.where((a) => a['level'] == level).length;
  int _countByStatus(String status) =>
      _admins.where((a) => (a['status'] ?? 'active') == status).length;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final displayName = auth.user?['fullName'] ??
        auth.user?['username'] ??
        t('Super Admin', 'ሱፐር አስተዳዳሪ');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('Super Admin Dashboard', 'የሱፐር አስተዳዳሪ ዳሽቦርድ')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          // Language toggle
          IconButton(
            icon: Text(
              _isAmharic ? 'EN' : 'አማ',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            onPressed: () => setState(() => _isAmharic = !_isAmharic),
            tooltip: 'Switch Language',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/super-admin/settings'),
            tooltip: t('Settings', 'ቅንብሮች'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogout,
            tooltip: t('Logout', 'ውጣ'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/super-admin/add-admin');
          _load();
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(t('Assign Admin', 'አስተዳዳሪ መድብ')),
        backgroundColor: AppColors.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildWelcomeBanner(displayName),
                          const SizedBox(height: 14),
                          _buildQuickActionRow(),
                          const SizedBox(height: 16),
                          _buildStatsRow(),
                          const SizedBox(height: 16),
                          _buildSearchBar(),
                          const SizedBox(height: 8),
                          _buildFilterRow(),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  _filtered.isEmpty
                      ? SliverFillRemaining(child: _buildEmptyState())
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _AdminCard(
                                admin: _filtered[i],
                                isAmharic: _isAmharic,
                                onEdit: () async {
                                  await context.push(
                                    '/super-admin/edit-admin',
                                    extra: _filtered[i],
                                  );
                                  _load();
                                },
                                onView: () => _showAdminDetail(_filtered[i]),
                                onDelete: () =>
                                    _confirmDelete(_filtered[i]),
                                onToggleStatus: () =>
                                    _toggleStatus(_filtered[i]),
                              ),
                              childCount: _filtered.length,
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  // ── banner ────────────────────────────────────────────────────────────────
  Widget _buildWelcomeBanner(String displayName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF5C6BC0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Welcome back,', 'እንኳን ደህና መጡ,'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  t('You manage ${_admins.length} admin(s) across all EQUB levels.',
                      'ለሁሉም የEQUB ደረጃዎች ${_admins.length} አስተዳዳሪ(ዎች) ያስተዳድራሉ።'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.admin_panel_settings,
                color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              await context.push('/super-admin/add-admin');
              _load();
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(t('Assign Admin', 'አስተዳዳሪ መድብ')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              final ok = await context.push('/super-admin/add-equb-level');
              if (ok == true) _load();
            },
            icon: const Icon(Icons.add_business),
            label: Text(t('Add Equb Level', 'እቁብ ደረጃ መዝግብ')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── stats row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(
          label: t('Total', 'ጠቅላላ'),
          value: '${_admins.length}',
          color: AppColors.primary,
          icon: Icons.people,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: t('Active', 'ንቁ'),
          value: '${_countByStatus('active')}',
          color: AppColors.success,
          icon: Icons.check_circle,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: t('Suspended', 'ታግዷል'),
          value: '${_countByStatus('suspended')}',
          color: AppColors.warning,
          icon: Icons.pause_circle,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: t('Low', 'ዝቅተኛ'),
          value: '${_countByLevel('low')}',
          color: AppColors.low,
          icon: Icons.savings,
        ),
      ],
    );
  }

  // ── search ────────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: t('Search admins by name, email or username…',
            'አስተዳዳሪዎችን በስም፣ ኢሜይል ወይም ተጠቃሚ ስም ይፈልጉ…'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => _searchQuery = ''),
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  // ── filter chips ──────────────────────────────────────────────────────────
  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(t('Level: ', 'ደረጃ: '),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          _FilterChip(
              label: t('All', 'ሁሉም'),
              selected: _filterLevel == 'all',
              color: AppColors.primary,
              onTap: () => setState(() => _filterLevel = 'all')),
          const SizedBox(width: 6),
          _FilterChip(
              label: t('Low', 'ዝቅተኛ'),
              selected: _filterLevel == 'low',
              color: AppColors.low,
              onTap: () => setState(() => _filterLevel = 'low')),
          const SizedBox(width: 6),
          _FilterChip(
              label: t('Medium', 'መካከለኛ'),
              selected: _filterLevel == 'medium',
              color: AppColors.medium,
              onTap: () => setState(() => _filterLevel = 'medium')),
          const SizedBox(width: 6),
          _FilterChip(
              label: t('High', 'ከፍተኛ'),
              selected: _filterLevel == 'high',
              color: AppColors.high,
              onTap: () => setState(() => _filterLevel = 'high')),
          const SizedBox(width: 16),
          Text(t('Status: ', 'ሁኔታ: '),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          _FilterChip(
              label: t('All', 'ሁሉም'),
              selected: _filterStatus == 'all',
              color: AppColors.primary,
              onTap: () => setState(() => _filterStatus = 'all')),
          const SizedBox(width: 6),
          _FilterChip(
              label: t('Active', 'ንቁ'),
              selected: _filterStatus == 'active',
              color: AppColors.success,
              onTap: () => setState(() => _filterStatus = 'active')),
          const SizedBox(width: 6),
          _FilterChip(
              label: t('Suspended', 'ታግዷል'),
              selected: _filterStatus == 'suspended',
              color: AppColors.warning,
              onTap: () => setState(() => _filterStatus = 'suspended')),
        ],
      ),
    );
  }

  // ── empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? t('No admins match your search.', 'ምንም አስተዳዳሪ አልተገኘም።')
                : t('No admins assigned yet.', 'ምንም አስተዳዳሪ አልተመደበም።'),
            style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await context.push('/super-admin/add-admin');
                _load();
              },
              icon: const Icon(Icons.person_add),
              label: Text(t('Assign First Admin', 'የመጀመሪያ አስተዳዳሪ ይመድቡ')),
            ),
          ],
        ],
      ),
    );
  }

  // ── actions ───────────────────────────────────────────────────────────────
  void _showAdminDetail(Map<String, dynamic> admin) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AdminDetailSheet(
        admin: admin,
        isAmharic: _isAmharic,
        onEdit: () async {
          Navigator.pop(context);
          await context.push('/super-admin/edit-admin', extra: admin);
          _load();
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDelete(admin);
        },
        onToggleStatus: () {
          Navigator.pop(context);
          _toggleStatus(admin);
        },
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> admin) async {
    final name = admin['fullName'] ?? '${admin['firstName']} ${admin['lastName']}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Delete Admin', 'አስተዳዳሪ ሰርዝ')),
        content: Text(t(
            'Are you sure you want to delete "$name"? This cannot be undone.',
            '"$name"ን መሰረዝ ይፈልጋሉ? ይህ ሊቀለበስ አይችልም።')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'ሰርዝ'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(t('Delete', 'ሰርዝ')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok =
        await RoleManagementService.deleteAdmin(admin['adminId'] ?? '');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? t('Admin deleted.', 'አስተዳዳሪ ተሰርዟል።')
          : t('Failed to delete admin.', 'አስተዳዳሪ ሊሰረዝ አልቻለም።')),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
    if (ok) _load();
  }

  Future<void> _toggleStatus(Map<String, dynamic> admin) async {
    final adminId = admin['adminId'] ?? '';
    final isActive = (admin['status'] ?? 'active') == 'active';

    if (isActive) {
      // Ask for suspension reason
      final reasonController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t('Suspend Admin', 'አስተዳዳሪ ታግድ')),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: t('Reason (optional)', 'ምክንያት (አማራጭ)'),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('Cancel', 'ሰርዝ'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning),
              child: Text(t('Suspend', 'ታግድ')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await RoleManagementService.suspendAdmin(adminId,
          reason: reasonController.text.trim());
    } else {
      await RoleManagementService.activateAdmin(adminId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isActive
          ? t('Admin suspended.', 'አስተዳዳሪ ታግዷል።')
          : t('Admin reactivated.', 'አስተዳዳሪ ንቁ ሆኗል።')),
      backgroundColor: isActive ? AppColors.warning : AppColors.success,
    ));
    _load();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Logout', 'ውጣ')),
        content:
            Text(t('Are you sure you want to logout?', 'መውጣት ይፈልጋሉ?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'ሰርዝ'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(t('Logout', 'ውጣ')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    context.go('/login');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Admin card widget
// ═══════════════════════════════════════════════════════════════════════════
class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.admin,
    required this.isAmharic,
    required this.onEdit,
    required this.onView,
    required this.onDelete,
    required this.onToggleStatus,
  });

  final Map<String, dynamic> admin;
  final bool isAmharic;
  final VoidCallback onEdit;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final VoidCallback onToggleStatus;

  String t(String en, String am) => isAmharic ? am : en;

  Color _levelColor(String level) {
    switch (level) {
      case 'medium':
        return AppColors.medium;
      case 'high':
        return AppColors.high;
      default:
        return AppColors.low;
    }
  }

  String _levelLabel(String level) {
    if (isAmharic) {
      switch (level) {
        case 'medium':
          return 'መካከለኛ';
        case 'high':
          return 'ከፍተኛ';
        default:
          return 'ዝቅተኛ';
      }
    }
    switch (level) {
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
    final level = (admin['level'] ?? 'low').toString();
    final status = (admin['status'] ?? 'active').toString();
    final isActive = status == 'active';
    final levelColor = _levelColor(level);
    final name =
        admin['fullName'] ?? '${admin['firstName']} ${admin['lastName']}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: levelColor,
                    child: Text(
                      name.isNotEmpty
                          ? name[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(admin['email'] ?? '',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isActive ? AppColors.success : AppColors.warning)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isActive
                          ? t('Active', 'ንቁ')
                          : t('Suspended', 'ታግዷል'),
                      style: TextStyle(
                          color: isActive
                              ? AppColors.success
                              : AppColors.warning,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Info row
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _infoChip(Icons.savings, '${_levelLabel(level)} Level',
                      levelColor),
                  _infoChip(Icons.phone, admin['phone'] ?? 'N/A',
                      AppColors.textSecondary),
                  _infoChip(Icons.person, admin['username'] ?? 'N/A',
                      AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // Action buttons
              Row(
                children: [
                  _actionBtn(
                      Icons.visibility_outlined,
                      t('View', 'አይት'),
                      AppColors.primary,
                      onView),
                  const SizedBox(width: 8),
                  _actionBtn(
                      Icons.edit_outlined, t('Edit', 'አርትዕ'), AppColors.secondary,
                      onEdit),
                  const SizedBox(width: 8),
                  _actionBtn(
                    isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    isActive ? t('Suspend', 'ታግድ') : t('Activate', 'ንቁ ሁን'),
                    isActive ? AppColors.warning : AppColors.success,
                    onToggleStatus,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: onDelete,
                    tooltip: t('Delete', 'ሰርዝ'),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Admin detail bottom sheet
// ═══════════════════════════════════════════════════════════════════════════
class _AdminDetailSheet extends StatelessWidget {
  const _AdminDetailSheet({
    required this.admin,
    required this.isAmharic,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleStatus,
  });

  final Map<String, dynamic> admin;
  final bool isAmharic;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleStatus;

  String t(String en, String am) => isAmharic ? am : en;

  @override
  Widget build(BuildContext context) {
    final name =
        admin['fullName'] ?? '${admin['firstName']} ${admin['lastName']}';
    final level = (admin['level'] ?? 'low').toString();
    final status = (admin['status'] ?? 'active').toString();
    final isActive = status == 'active';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'A',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                          t('$level Level Admin', '$level ደረጃ አስተዳዳሪ'),
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isActive ? AppColors.success : AppColors.warning)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? t('Active', 'ንቁ') : t('Suspended', 'ታግዷል'),
                    style: TextStyle(
                        color: isActive
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            // Details
            _detailRow(t('Full Name', 'ሙሉ ስም'), name),
            _detailRow(t('Email', 'ኢሜይል'), admin['email'] ?? 'N/A'),
            _detailRow(t('Username', 'ተጠቃሚ ስም'), admin['username'] ?? 'N/A'),
            _detailRow(t('Phone', 'ስልክ'), admin['phone'] ?? 'N/A'),
            _detailRow(t('Address', 'አድራሻ'), admin['address'] ?? 'N/A'),
            _detailRow(t('Assigned Level', 'የተመደበ ደረጃ'),
                '${level[0].toUpperCase()}${level.substring(1)} Level'),
            _detailRow(t('Status', 'ሁኔታ'),
                isActive ? t('Active', 'ንቁ') : t('Suspended', 'ታግዷል')),
            if (admin['createdAt'] != null)
              _detailRow(t('Created', 'ተፈጥሯል'),
                  admin['createdAt'].toString().substring(0, 10)),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    label: Text(t('Edit', 'አርትዕ')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onToggleStatus,
                    icon: Icon(isActive
                        ? Icons.pause_circle
                        : Icons.play_circle),
                    label: Text(isActive
                        ? t('Suspend', 'ታግድ')
                        : t('Activate', 'ንቁ ሁን')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isActive ? AppColors.warning : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              label: Text(t('Delete Admin', 'አስተዳዳሪ ሰርዝ'),
                  style: const TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Small reusable widgets
// ═══════════════════════════════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color)),
            Text(label,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: selected ? Colors.white : color,
              fontWeight: FontWeight.w600,
              fontSize: 12),
        ),
      ),
    );
  }
}
