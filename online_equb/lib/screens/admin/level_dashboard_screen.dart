import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import '../../services/api_service.dart';
import '../../services/sound_service.dart';
import '../../utils/constants.dart';
import '../../widgets/equb_draw_wheel.dart';
import 'admin_register_user_screen.dart';

/// Full level-specific dashboard for the assigned admin.
/// Handles: user list (Firestore), CRUD (add/edit/delete/suspend),
/// search/filter, wheel draw algorithm, draw history.
class LevelDashboardScreen extends StatefulWidget {
  final String level;
  final String adminId;
  final Map<String, dynamic> data;
  final List<dynamic> allUsers;
  final VoidCallback onRefresh;
  final bool isAmharic;

  const LevelDashboardScreen({
    super.key,
    required this.level,
    required this.adminId,
    required this.data,
    required this.allUsers,
    required this.onRefresh,
    this.isAmharic = false,
  });

  @override
  State<LevelDashboardScreen> createState() => _LevelDashboardScreenState();
}

class _LevelDashboardScreenState extends State<LevelDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _drawHistory = [];
  bool _loading = true;
  bool _isAmharic = false;
  String _searchQuery = '';
  String _participantFilter = 'all'; // all | eligible | winners | suspended
  bool _isSpinning = false;
  Map<String, dynamic>? _pendingDraw;
  bool _isTableView = true;

  String t(String en, String am) => _isAmharic ? am : en;

  // ── computed ──────────────────────────────────────────────────────────────
  Color get _levelColor {
    switch (widget.level) {
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
      switch (widget.level) {
        case 'medium':
          return 'መካከለኛ';
        case 'high':
          return 'ከፍተኛ';
        default:
          return 'ዝቅተኛ';
      }
    }
    switch (widget.level) {
      case 'medium':
        return 'Medium';
      case 'high':
        return 'High';
      default:
        return 'Low';
    }
  }

  int get _maxSlots =>
      int.tryParse(widget.data['maxParticipants']?.toString() ?? '') ?? 100;

  List<Map<String, dynamic>> get _eligible => _participants
      .where(
          (p) => p['hasWon'] != true && (p['status'] ?? 'active') == 'active')
      .toList();

  List<Map<String, dynamic>> get _filteredParticipants {
    return _participants.where((p) {
      // search
      final q = _searchQuery.toLowerCase();
      final name = (p['fullName'] ?? '').toString().toLowerCase();
      final uid = (p['uniqueId'] ?? '').toString().toLowerCase();
      final phone = (p['phoneNumber'] ?? '').toString().toLowerCase();
      final email = (p['email'] ?? '').toString().toLowerCase();
      final matchSearch = q.isEmpty ||
          name.contains(q) ||
          uid.contains(q) ||
          phone.contains(q) ||
          email.contains(q);

      // filter
      bool matchFilter = true;
      if (_participantFilter == 'eligible') {
        matchFilter =
            p['hasWon'] != true && (p['status'] ?? 'active') == 'active';
      } else if (_participantFilter == 'winners') {
        matchFilter = p['hasWon'] == true;
      } else if (_participantFilter == 'suspended') {
        matchFilter = (p['status'] ?? 'active') == 'suspended';
      }

      return matchSearch && matchFilter;
    }).toList();
  }

  late final TextEditingController _settingsNameController;
  late final TextEditingController _settingsEmailController;
  late final TextEditingController _settingsUsernameController;
  late final TextEditingController _settingsPasswordController;
  late final TextEditingController _settingsConfirmPasswordController;
  late final TextEditingController _settingsPhoneController;
  late final TextEditingController _settingsAddressController;
  bool _settingsSaving = false;
  bool _obscureSettingsPass = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _isAmharic = widget.isAmharic;
    _settingsNameController = TextEditingController(
        text: widget.data['fullName'] ?? widget.data['firstName'] ?? '');
    _settingsEmailController = TextEditingController(
        text: widget.data['email'] ?? '');
    _settingsUsernameController = TextEditingController(
        text: widget.data['username'] ?? widget.data['email']?.toString().split('@').first ?? '');
    _settingsPasswordController = TextEditingController();
    _settingsConfirmPasswordController = TextEditingController();
    _settingsPhoneController = TextEditingController(
        text: widget.data['phone'] ?? widget.data['phoneNumber'] ?? '');
    _settingsAddressController = TextEditingController(
        text: widget.data['address'] ?? '');
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _settingsNameController.dispose();
    _settingsEmailController.dispose();
    _settingsUsernameController.dispose();
    _settingsPasswordController.dispose();
    _settingsConfirmPasswordController.dispose();
    _settingsPhoneController.dispose();
    _settingsAddressController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final users = await RoleManagementService.getUsersByLevel(widget.level);
    final history = await RoleManagementService.getDrawHistory(widget.level);

    if (mounted) {
      final authUser = context.read<AuthProvider>().user ?? widget.data;
      if (_settingsNameController.text.isEmpty && authUser.isNotEmpty) {
        _settingsNameController.text = (authUser['fullName'] ?? authUser['firstName'] ?? '').toString();
        _settingsEmailController.text = (authUser['email'] ?? '').toString();
        _settingsUsernameController.text = (authUser['username'] ?? authUser['email']?.toString().split('@').first ?? '').toString();
        _settingsPhoneController.text = (authUser['phone'] ?? authUser['phoneNumber'] ?? '').toString();
        _settingsAddressController.text = (authUser['address'] ?? '').toString();
      }
    }

    if (!mounted) return;
    setState(() {
      _participants = users;
      _drawHistory = history;
      _loading = false;
    });
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('Logout', 'ውጣ')),
        content: Text(t('Are you sure you want to log out of your session?', 'እርግጠኛ ነዎት ከመለያዎ መውጣት ይፈልጋሉ?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'ሰርዝ')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Logout', 'ውጣ'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    await auth.logout();
    if (mounted) context.go('/login');
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title:
            Text(t('$_levelLabel Level Dashboard', '$_levelLabel ደረጃ ዳሽቦርድ')),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/home');
            }
          },
          tooltip: t('Back', 'ተመለስ'),
        ),
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
            onPressed: _loadData,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Material(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _confirmLogout,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        t('Logout', 'ውጣ'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: t('Members', 'አባላት')),
            Tab(text: t('Draw Algorithm', 'የእጣ ስልተ ቀመር')),
            Tab(text: t('History', 'ታሪክ')),
            Tab(text: t('Settings', 'መቼቶች')),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _addUser,
              backgroundColor: _levelColor,
              icon: const Icon(Icons.person_add),
              label: Text(t('Add User', 'ተጠቃሚ ጨምር')),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMembersTab(),
                _buildDrawWheelTab(),
                _buildHistoryTab(),
                _buildSettingsTab(),
              ],
            ),
    );
  }

  Widget _buildExpertSystemAdvisor() {
    final total = _participants.length;
    final eligible = _eligible.length;
    final remainingSlots = _maxSlots - total;

    String levelTitle;
    String priceRange;
    String adviceText;
    IconData levelIcon;
    Color accentColor;

    switch (widget.level.toLowerCase()) {
      case 'medium':
        levelTitle = t('Medium Level Equb (SME & Business Pool)', 'መካከለኛ ደረጃ እቁብ (አነስተኛና መካከለኛ ንግድ)');
        priceRange = 'ETB 10,000 – 50,000 / cycle';
        accentColor = AppColors.medium;
        levelIcon = Icons.account_balance_wallet_rounded;
        break;
      case 'high':
        levelTitle = t('High Level Equb (VIP Investment Pool)', 'ከፍተኛ ደረጃ እቁብ (ቪአይፒ ኢንቨስትመንት)');
        priceRange = 'ETB 50,000+ / cycle';
        accentColor = AppColors.high;
        levelIcon = Icons.stars_rounded;
        break;
      default:
        levelTitle = t('Low Level Equb (Micro-Savings Pool)', 'ዝቅተኛ ደረጃ እቁብ (አነስተኛ ቆጣቢዎች)');
        priceRange = 'ETB 1,000 – 10,000 / cycle';
        accentColor = AppColors.low;
        levelIcon = Icons.savings_rounded;
        break;
    }

    if (total == 0) {
      adviceText = t(
          '💡 Expert System Status: No members registered yet. Use "Add User" to register the first member for $levelTitle.',
          '💡 የኤክስፐርት ሲስተም ሁኔታ፡ እስካሁን ምንም አባል አልተመዘገበም። "ተጠቃሚ ጨምር" በመጠቀም የመጀመሪያውን አባል ይመዝግቡ።');
    } else if (eligible == 0) {
      adviceText = t(
          '⚠️ Expert System Insight: All active members have won previous draws! Reset cycle or add new members to initiate next draw.',
          '⚠️ የኤክስፐርት ሲስተም ትንተና፡ ሁሉም ንቁ አባላት ቀደም ሲል አሸንፈዋል! ለቀጣይ እጣ አዲስ አባላት ይጨምሩ።');
    } else if (eligible >= 2) {
      adviceText = t(
          '🎯 Expert System Advice: $eligible members are eligible for the random weighted spin! Proceed to "Draw Algorithm" tab to execute draw.',
          '🎯 የኤክስፐርት ሲስተም ምክር፡ $eligible አባላት ለእጣው ብቁ ናቸው! እጣ ለማውጣት ወደ "የእጣ ስልተ ቀመር" ትር ይሂዱ።');
    } else {
      adviceText = t(
          '📊 Expert System Analysis: 1 eligible member remaining ($eligible/$total). Capacity: $remainingSlots slots available.',
          '📊 የኤክስፐርት ሲስተም ትንተና፡ 1 ብቁ አባል ቀርቷል። ክፍት ቦታዎች፡ $remainingSlots።');
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
            ),
            child: Icon(levelIcon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        levelTitle,
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accentColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        priceRange,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  adviceText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 – Members (Permanent Data Table & Card View)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMembersTab() {
    return Column(
      children: [
        // Stats bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _miniStat(
                  t('Total', 'ጠቅላላ'), '${_participants.length}', _levelColor),
              _miniStat(t('Eligible', 'ብቁ'), '${_eligible.length}',
                  AppColors.success),
              _miniStat(
                  t('Winners', 'አሸናፊዎች'),
                  '${_participants.where((p) => p['hasWon'] == true).length}',
                  AppColors.warning),
              _miniStat(t('Cap', 'ቁጥር'), '$_maxSlots', AppColors.textSecondary),
            ],
          ),
        ),
        _buildExpertSystemAdvisor(),
        // Search + filter + view toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: t('Search by name, ID, phone…', 'በስም፣ መታወቂያ፣ ስልክ ይፈልጉ…'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isTableView ? Icons.grid_view_rounded : Icons.table_chart_rounded,
                        color: _levelColor,
                      ),
                      tooltip: _isTableView ? t('Card View', 'ካርድ እይታ') : t('Table View', 'ሠንጠረዥ እይታ'),
                      onPressed: () => setState(() => _isTableView = !_isTableView),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(t('All', 'ሁሉም'), 'all'),
                    const SizedBox(width: 6),
                    _filterChip(t('Eligible', 'ብቁ'), 'eligible'),
                    const SizedBox(width: 6),
                    _filterChip(t('Winners', 'አሸናፊዎች'), 'winners'),
                    const SizedBox(width: 6),
                    _filterChip(t('Suspended', 'ታግዷል'), 'suspended'),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Members View (Table vs Cards)
        Expanded(
          child: _filteredParticipants.isEmpty
              ? _emptyMembersState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _isTableView
                      ? _buildPermanentMembersTable()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                          itemCount: _filteredParticipants.length,
                          itemBuilder: (_, i) => _userCard(_filteredParticipants[i]),
                        ),
                ),
        ),
      ],
    );
  }

  /// Permanent Data Table view for registered Equb members
  Widget _buildPermanentMembersTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
      scrollDirection: Axis.vertical,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_levelColor.withOpacity(0.12)),
            columnSpacing: 18,
            columns: [
              DataColumn(label: Text('#', style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(t('Member Name', 'አባል ስም'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(t('Unique ID', 'መታወቂያ'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(t('Phone', 'ስልክ'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(t('Status', 'ሁኔታ'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(t('Actions', 'ተግባራት'), style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List.generate(_filteredParticipants.length, (index) {
              final user = _filteredParticipants[index];
              final hasWon = user['hasWon'] == true;
              final status = (user['status'] ?? 'active').toString();
              final isSuspended = status == 'suspended';
              final name = user['fullName'] ??
                  '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();

              Color statusColor;
              String statusLabel;
              if (hasWon) {
                statusColor = AppColors.warning;
                statusLabel = t('Winner', 'አሸናፊ');
              } else if (isSuspended) {
                statusColor = AppColors.error;
                statusLabel = t('Suspended', 'ታግዷል');
              } else {
                statusColor = AppColors.success;
                statusLabel = t('Active', 'ንቁ');
              }

              return DataRow(
                cells: [
                  DataCell(Text('${index + 1}')),
                  DataCell(
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: statusColor,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(user['email'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(user['uniqueId']?.toString() ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(user['phoneNumber']?.toString() ?? 'N/A')),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 18),
                          onPressed: () => _editUser(user),
                          tooltip: t('Edit', 'አርትዕ'),
                        ),
                        IconButton(
                          icon: Icon(
                            isSuspended ? Icons.play_circle_outline : Icons.pause_circle_outline,
                            color: isSuspended ? AppColors.success : AppColors.warning,
                            size: 18,
                          ),
                          onPressed: () => _toggleUserStatus(user),
                          tooltip: isSuspended ? t('Activate', 'ንቁ ሁን') : t('Suspend', 'ታግድ'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                          onPressed: () => _confirmDeleteUser(user),
                          tooltip: t('Delete', 'ሰርዝ'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final hasWon = user['hasWon'] == true;
    final status = (user['status'] ?? 'active').toString();
    final isSuspended = status == 'suspended';
    final name = user['fullName'] ??
        '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();

    Color statusColor;
    String statusLabel;
    if (hasWon) {
      statusColor = AppColors.warning;
      statusLabel = t('Winner', 'አሸናፊ');
    } else if (isSuspended) {
      statusColor = AppColors.error;
      statusLabel = t('Suspended', 'ታግዷል');
    } else {
      statusColor = AppColors.success;
      statusLabel = t('Active', 'ንቁ');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: hasWon
                      ? AppColors.warning
                      : isSuspended
                          ? AppColors.error
                          : _levelColor,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(user['email'] ?? '',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                _infoChip(Icons.badge,
                    '${t('ID', 'መ')}: ${user['uniqueId'] ?? 'N/A'}'),
                _infoChip(Icons.phone, user['phoneNumber'] ?? 'N/A'),
              ],
            ),
            const SizedBox(height: 8),
            // Action row
            Row(
              children: [
                _actionBtn(Icons.edit_outlined, t('Edit', 'አርትዕ'),
                    AppColors.primary, () => _editUser(user)),
                const SizedBox(width: 6),
                _actionBtn(
                  isSuspended
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  isSuspended ? t('Activate', 'ንቁ ሁን') : t('Suspend', 'ታግድ'),
                  isSuspended ? AppColors.success : AppColors.warning,
                  () => _toggleUserStatus(user),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 20),
                  onPressed: () => _confirmDeleteUser(user),
                  tooltip: t('Delete', 'ሰርዝ'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyMembersState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? t('No members match your search.', 'ምንም አባል አልተገኘም።')
                : t('No members yet. Tap + to add.', 'ምንም አባል የለም። + ይጫኑ።'),
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2 – Draw Wheel (Active algorithm without minimum limitations)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDrawWheelTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Eligible summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _levelColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _levelColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _drawStat(
                    t('Total', 'ጠቅላላ'), '${_participants.length}', _levelColor),
                _drawStat(t('Eligible', 'ብቁ'), '${_eligible.length}',
                    AppColors.success),
                _drawStat(t('Drawn', 'ስዕሎች'), '${_drawHistory.length}',
                    AppColors.warning),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_eligible.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.warning, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      'No eligible participants available for this level.',
                      'ለዚህ ደረጃ ምንም ብቁ ተሳታፊ የለም።',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.warning),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Ethiopian Golden Wheel
          EqubDrawWheel(
            participants: _participants,
            accentColor: _levelColor,
            levelName: _levelLabel,
            disabled: _isSpinning || _eligible.isEmpty,
            onSpinRequested: _requestServerWinner,
            onWinnerSelected: (index) => _handleWinnerSelected(index),
          ),

          const SizedBox(height: 16),
          // Algorithm note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(t('How the Algorithm Works', 'ስልተ ቀመሩ እንዴት ይሰራል'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                ]),
                const SizedBox(height: 8),
                Text(
                  t(
                    '• Each spin randomly selects one eligible participant.\n'
                        '• Selected winner is excluded from all future draws.\n'
                        '• Winner\'s name and ID are recorded in history.\n'
                        '• The wheel shows only eligible participants.',
                    '• እያንዳንዱ ስዕሉ ከብቁ ተሳታፊዎች አንዱን ይመርጣል።\n'
                        '• የተመረጠው አሸናፊ ከወደፊት ስዕሎች ይወጣል።\n'
                        '• የአሸናፊው ስምና መታወቂያ ይመዘገባል።\n'
                        '• ስዕሉ ብቁ ተሳታፊዎችን ብቻ ያሳያል።',
                  ),
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<int?> _requestServerWinner() async {
    if (_eligible.isEmpty) return null;

    final result = await ApiService.adminRunDraw(widget.level);
    if (result.containsKey('error')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['error'].toString()),
          backgroundColor: AppColors.error,
        ));
      }
      return null;
    }

    final winnerId = result['winnerId']?.toString();
    final index = _eligible.indexWhere(
      (participant) =>
          (participant['userId'] ?? participant['id']).toString() == winnerId,
    );
    if (index < 0) return null;
    _pendingDraw = result;
    return index;
  }

  Future<void> _handleWinnerSelected(int index) async {
    if (index < 0 || index >= _eligible.length) return;
    final winner = _eligible[index];
    if (_pendingDraw == null) return;

    setState(() => _isSpinning = true);

    // The backend selected and saved this winner before the wheel animation.
    // Reloading makes the winner unavailable for every later spin.
    await _loadData();
    _pendingDraw = null;
    setState(() => _isSpinning = false);

    if (!mounted) return;
    _showWinnerDialog(winner);
    widget.onRefresh();
  }

  void _showWinnerDialog(Map<String, dynamic> winner) {
    final name = (winner['fullName'] ?? winner['firstName'] ?? '').toString();
    final uid = (winner['uniqueId'] ?? winner['userId'] ?? winner['id'] ?? '').toString();

    // Trigger 3-times repeated Amharic winner announcement
    SoundService.speakWinnerRepeatedThreeTimes(fullName: name, uniqueId: uid);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(children: [
          Icon(Icons.emoji_events, color: _levelColor, size: 56),
          const SizedBox(height: 8),
          Text(t('🎉 Winner!', '🎉 አሸናፊ!'),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _levelColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Text(name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('ID: $uid',
                    style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Text(
                  t(
                    'Congratulations! This winner will not participate in future draws of $_levelLabel Level.',
                    'እንኳን ደስ አለዎ! ይህ አሸናፊ ወደፊት በ$_levelLabel ደረጃ ስዕሎች አይሳተፍም።',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _levelColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 13),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                SoundService.stop();
                Navigator.of(dialogCtx, rootNavigator: true).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _levelColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                t('Close', 'ዝጋ'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3 – History
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildHistoryTab() {
    final priceRangeText = AppConstants.getLevelPriceRange(widget.level, isAmharic: _isAmharic);
    final netPrizeText = AppConstants.getLevelNetPrize(widget.level, isAmharic: _isAmharic);

    return Column(
      children: [
        // Price Range & Prize Summary Banner
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_levelColor.withOpacity(0.15), _levelColor.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _levelColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _levelColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.emoji_events_rounded, color: _levelColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_levelLabel.toUpperCase()} LEVEL HISTORY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _levelColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t("Price", "ክፍያ")}: $priceRangeText',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Text(
                      '${t("Prize", "የአሸናፊ ድል አበል")}: $netPrizeText',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _levelColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _levelColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: _levelColor.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Text(
                  '${_drawHistory.length} ${t("Winners", "አሸናፊዎች")}',
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _drawHistory.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _levelColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.emoji_events_outlined, size: 64, color: _levelColor),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('No draw history recorded yet for $_levelLabel level.',
                              'ለ$_levelLabel ደረጃ እስካሁን የተመዘገበ የስዕል ታሪክ የለም።'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('Spin the algorithm wheel to draw weekly winners!',
                              'የሳምንቱን አሸናፊዎች ለመምረጥ ስዕሉን ያሽከርክሩ!'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: _drawHistory.length,
                    itemBuilder: (_, i) {
                      final draw = _drawHistory[i];
                      final drawNum = draw['drawNumber'] ?? (i + 1);
                      final winnerName = (draw['winnerName'] ?? draw['fullName'] ?? 'N/A').toString();
                      final winnerId = (draw['winnerUniqueId'] ?? draw['winnerId'] ?? draw['uniqueId'] ?? 'N/A').toString();
                      final createdAt = draw['createdAt'];

                      String fullDateTimeStr = '';
                      if (createdAt != null) {
                        try {
                          final dt = createdAt is String
                              ? DateTime.parse(createdAt)
                              : (createdAt as dynamic).toDate();
                          final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                          final period = dt.hour >= 12 ? 'PM' : 'AM';
                          final monthStr = dt.month.toString().padLeft(2, '0');
                          final dayStr = dt.day.toString().padLeft(2, '0');
                          final minStr = dt.minute.toString().padLeft(2, '0');
                          fullDateTimeStr = '${dt.year}-$monthStr-$dayStr  •  $hour:$minStr $period';
                        } catch (_) {
                          fullDateTimeStr = createdAt.toString();
                          if (fullDateTimeStr.length > 16) {
                            fullDateTimeStr = fullDateTimeStr.substring(0, 16);
                          }
                        }
                      } else {
                        final now = DateTime.now();
                        final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
                        final period = now.hour >= 12 ? 'PM' : 'AM';
                        fullDateTimeStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}  •  $hour:${now.minute.toString().padLeft(2, '0')} $period';
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _levelColor.withOpacity(0.2), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Round / Week Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _levelColor,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          _isAmharic ? '$drawNumኛ ሳምንት አሸናፊ' : 'Round #$drawNum Winner',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  // Trophy Icon
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.emoji_events, color: Colors.amber, size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: _levelColor.withOpacity(0.15),
                                    child: Text(
                                      winnerName.isNotEmpty ? winnerName[0].toUpperCase() : 'W',
                                      style: TextStyle(
                                        color: _levelColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          winnerName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${t("Unique ID", "መታወቂያ")}: $winnerId',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _levelColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 18, thickness: 0.8),
                              Row(
                                children: [
                                  Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 6),
                                  Text(
                                    fullDateTimeStr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    netPrizeText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _levelColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CRUD actions
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _addUser() async {
    if (_participants.length >= _maxSlots) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'This level has reached its maximum capacity of $_maxSlots members.',
          'ይህ ደረጃ ከፍተኛ ቁጥሩን ($_maxSlots) ደርሷል።',
        )),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminRegisterUserScreen(
          level: widget.level,
          adminId: widget.adminId,
        ),
      ),
    );
    if (result == true) _loadData();
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminRegisterUserScreen(
          level: widget.level,
          adminId: widget.adminId,
          editData: user,
        ),
      ),
    );
    if (result == true) _loadData();
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final userId = user['userId'] ?? user['id'] ?? '';
    final isSuspended = (user['status'] ?? 'active') == 'suspended';
    bool ok;
    if (isSuspended) {
      ok = await RoleManagementService.activateUser(userId);
    } else {
      ok = await RoleManagementService.suspendUser(userId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (isSuspended
              ? t('User activated.', 'ተጠቃሚ ንቁ ሆኗል።')
              : t('User suspended.', 'ተጠቃሚ ታግዷል።'))
          : t('Action failed.', 'ተግባሩ አልተሳካም።')),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
    if (ok) _loadData();
  }

  Future<void> _confirmDeleteUser(Map<String, dynamic> user) async {
    final name = user['fullName'] ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Delete User', 'ተጠቃሚ ሰርዝ')),
        content: Text(t(
          'Delete "$name"? This cannot be undone.',
          '"$name"ን ይሰርዙ? ሊቀለበስ አይችልም።',
        )),
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
    final ok = await RoleManagementService.deleteUser(
        user['userId'] ?? user['id'] ?? '');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? t('User deleted.', 'ተጠቃሚ ተሰርዟል።')
          : t('Failed to delete.', 'ሊሰረዝ አልቻለም።')),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
    if (ok) _loadData();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _drawStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 22, color: color)),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final sel = _participantFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _participantFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? _levelColor : _levelColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _levelColor.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : _levelColor,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4 – Settings
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _levelColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.manage_accounts, color: _levelColor, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('Admin Account Settings', 'የአስተዳዳሪ መለያ መቼቶች'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: _levelColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('Update your username, password, phone, and details for $_levelLabel level',
                              'ለ$_levelLabel ደረጃ የእርስዎን ተጠቃሚ ስም፣ የይለፍ ቃል፣ ስልክ እና መረጃዎችን ያሻሽሉ'),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Full Name
                Text(t('Full Name', 'ሙሉ ስም'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsNameController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person),
                    hintText: t('Admin Full Name', 'የአስተዳዳሪ ሙሉ ስም'),
                  ),
                ),
                const SizedBox(height: 14),

                // Email Address
                Text(t('Email Address', 'ኢሜይል አድራሻ'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.email),
                    hintText: 'admin@equb.et',
                  ),
                ),
                const SizedBox(height: 14),

                // Username
                Text(t('Username', 'ተጠቃሚ ስም'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsUsernameController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.alternate_email),
                    hintText: 'admin_username',
                  ),
                ),
                const SizedBox(height: 14),

                // Phone Number
                Text(t('Phone Number', 'ስልክ ቁጥር'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone),
                    hintText: '09XXXXXXXX',
                  ),
                ),
                const SizedBox(height: 14),

                // Address
                Text(t('Address', 'አድራሻ'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsAddressController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.location_on),
                    hintText: t('Addis Ababa, Ethiopia', 'አዲስ አበባ፣ ኢትዮጵያ'),
                  ),
                ),
                const SizedBox(height: 14),

                // Password & Confirm Password
                Text(t('New Password (leave blank to keep current)',
                       'አዲስ የይለፍ ቃል (አሁን ያለውን ለማቆየት ባዶ ይተውት)'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsPasswordController,
                  obscureText: _obscureSettingsPass,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureSettingsPass ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureSettingsPass = !_obscureSettingsPass),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text(t('Confirm New Password', 'አዲሱን የይለፍ ቃል ድገም'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsConfirmPasswordController,
                  obscureText: _obscureSettingsPass,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_clock),
                    hintText: '••••••••',
                  ),
                ),
                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _settingsSaving ? null : _saveAdminSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _levelColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _settingsSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.save, color: Colors.white),
                    label: Text(
                      _settingsSaving
                          ? t('Saving Changes…', 'ለውጦችን በማስቀመጥ ላይ…')
                          : t('Save Account Settings', 'የመለያ መቼቶችን አስቀምጥ'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAdminSettings() async {
    final pass = _settingsPasswordController.text;
    final confirm = _settingsConfirmPasswordController.text;

    if (pass.isNotEmpty && pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Passwords do not match.', 'የይለፍ ቃሎቹ አይመሳሰሉም።')),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    setState(() => _settingsSaving = true);

    final updates = <String, dynamic>{
      'fullName': _settingsNameController.text.trim(),
      'email': _settingsEmailController.text.trim().toLowerCase(),
      'username': _settingsUsernameController.text.trim(),
      'phone': _settingsPhoneController.text.trim(),
      'address': _settingsAddressController.text.trim(),
    };
    if (pass.isNotEmpty) {
      updates['password'] = pass;
    }

    final auth = context.read<AuthProvider>();
    final adminId = widget.adminId.isNotEmpty
        ? widget.adminId
        : (widget.data['adminId'] ?? widget.data['id'] ?? auth.user?['adminId'] ?? auth.user?['uid'] ?? 'super_admin').toString();
    final ok = await RoleManagementService.updateAdmin(adminId, updates);

    setState(() => _settingsSaving = false);
    if (!mounted) return;

    if (ok) {
      if (auth.user != null) {
        auth.refreshUser({
          ...auth.user!,
          ...updates,
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Admin settings saved successfully.', 'የአስተዳዳሪ መቼቶች በተሳካ ሁኔታ ተቀምጠዋል።')),
        backgroundColor: AppColors.success,
      ));
      _settingsPasswordController.clear();
      _settingsConfirmPasswordController.clear();
      widget.onRefresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Failed to save settings.', 'መቼቶችን ማስቀመጥ አልተቻለም።')),
        backgroundColor: AppColors.error,
      ));
    }
  }
}
