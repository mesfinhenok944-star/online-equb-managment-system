import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  bool _isAmharic = false;

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

    final level = (adminProfile['level'] ?? 'low').toString();

    // Load users for this level
    final users = await RoleManagementService.getUsersByLevel(level);
    final history = await RoleManagementService.getDrawHistory(level);

    if (!mounted) return;
    setState(() {
      _adminProfile = {...adminProfile!, 'drawHistory': history};
      _usersByLevel = {level: users};
      _loading = false;
    });
  }

  String get _assignedLevel => (_adminProfile?['level'] ?? 'low').toString();

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
    final auth = context.read<AuthProvider>();
    final name = _adminProfile?['fullName'] ??
        '${_adminProfile?['firstName'] ?? ''} ${_adminProfile?['lastName'] ?? ''}'
            .trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('Admin Dashboard', 'የአስተዳዳሪ ዳሽቦርድ')),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Text(
              _isAmharic ? 'EN' : 'አማ',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            onPressed: () => setState(() => _isAmharic = !_isAmharic),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              auth.logout().then((_) {
                if (!mounted) return;
                context.go('/login');
              });
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildWelcomeCard(name),
                  const SizedBox(height: 16),
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                  _buildLevelCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildWelcomeCard(String name) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_levelColor, _levelColor.withOpacity(0.7)],
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
                Text(t('Welcome,', 'እንኳን ደህና መጡ,'),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(name.isEmpty ? t('Admin', 'አስተዳዳሪ') : name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    t('$_levelLabel Level Admin', '$_levelLabel ደረጃ አስተዳዳሪ'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: const Icon(Icons.person, color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final users = _usersByLevel[_assignedLevel] ?? [];
    final active =
        users.where((u) => (u['status'] ?? 'active') == 'active').length;
    final winners = users.where((u) => u['hasWon'] == true).length;
    final eligible = active - winners;
    final history = (_adminProfile?['drawHistory'] as List<dynamic>?) ?? [];

    return Row(
      children: [
        _StatCard(
            label: t('Members', 'አባላት'),
            value: '${users.length}',
            color: _levelColor,
            icon: Icons.people),
        const SizedBox(width: 8),
        _StatCard(
            label: t('Active', 'ንቁ'),
            value: '$active',
            color: AppColors.success,
            icon: Icons.check_circle),
        const SizedBox(width: 8),
        _StatCard(
            label: t('Eligible', 'ብቁ'),
            value: '${eligible < 0 ? 0 : eligible}',
            color: AppColors.primary,
            icon: Icons.how_to_reg),
        const SizedBox(width: 8),
        _StatCard(
            label: t('Draws', 'ስዕሎች'),
            value: '${history.length}',
            color: AppColors.warning,
            icon: Icons.casino),
      ],
    );
  }

  Widget _buildLevelCard() {
    final users = _usersByLevel[_assignedLevel] ?? [];
    const maxSlots = 100;
    final progress = maxSlots > 0 ? users.length / maxSlots : 0.0;
    final prize = _assignedLevel == 'high'
        ? '20,000 ETB'
        : _assignedLevel == 'medium'
            ? '10,000 ETB'
            : '5,000 ETB';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _levelColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _levelColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/levels/$_assignedLevel.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/levels/${_assignedLevel}_equb.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _levelColor.withOpacity(0.1),
                        child: Icon(Icons.savings, color: _levelColor, size: 28),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('$_levelLabel Level EQUB', '$_levelLabel ደረጃ EQUB'),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: _levelColor),
                    ),
                    Text(
                      t('$prize · $maxSlots max members',
                          '$prize · ከፍተኛ $maxSlots አባላት'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: _levelColor.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(_levelColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t(
                '${users.length}/$maxSlots members · ${(progress * 100).toStringAsFixed(0)}% filled',
                '${users.length}/$maxSlots አባላት · ${(progress * 100).toStringAsFixed(0)}% ተሞልቷል',
              ),
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _levelColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _levelColor.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.casino_outlined, color: _levelColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Verified Draw Algorithm', 'የተረጋገጠ የእጣ ስልተ ቀመር'),
                            style: TextStyle(fontWeight: FontWeight.bold, color: _levelColor)),
                        Text(
                          t('Server-selected • 100 eligible members • no repeat winners',
                              'በሰርቨር የሚመረጥ • 100 ብቁ አባላት • ድጋሚ አሸናፊ የለም'),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LevelDashboardScreen(
                        level: _assignedLevel,
                        adminId: _adminProfile?['adminId'] ??
                            _adminProfile?['uid'] ??
                            '',
                        data: _adminProfile ?? {},
                        allUsers: _usersByLevel[_assignedLevel] ?? [],
                        onRefresh: _load,
                        isAmharic: _isAmharic,
                      ),
                    ),
                  ).then((_) => _load());
                },
                icon: const Icon(Icons.casino),
                label: Text(
                  t('Open Members & Draw Algorithm',
                      'አባላትን እና የእጣ ስልተ ቀመርን ክፈት'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _levelColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                    fontWeight: FontWeight.bold, fontSize: 18, color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
