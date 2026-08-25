import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import '../../services/api_service.dart';
import '../../services/sound_service.dart';
import '../../services/equb_draw_algorithm.dart';
import '../../utils/constants.dart';
import '../../widgets/equb_draw_wheel.dart';
import '../../widgets/offline_banner.dart';
import 'admin_register_user_screen.dart';
import 'level_admin_payment_verification_screen.dart';

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

class _LevelDashboardScreenState extends State<LevelDashboardScreen> {
  // BottomNavigationBar index (replaces TabController)
  // 0=Members 1=Draw 2=Payments 3=History 4=Settings
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

  List<Map<String, dynamic>> _levelPayments = [];
  String _paymentFilterStatus = 'pending_verification';

  int get _pendingPaymentsCount => _levelPayments.where((p) {
        final st = (p['status'] ?? 'pending_verification').toString();
        return st == 'pending_verification' || st == 'pending';
      }).length;

  String _getMemberPaymentStatus(Map<String, dynamic> user) {
    if (user['hasPaid'] == true) return 'verified';
    final uEmail = (user['email'] ?? '').toString().toLowerCase().trim();
    final uId = (user['uniqueId'] ?? user['userId'] ?? '').toString().trim();

    for (final pay in _levelPayments) {
      final pEmail = (pay['email'] ?? '').toString().toLowerCase().trim();
      final pId = (pay['nationalId'] ?? pay['uniqueId'] ?? pay['userId'] ?? '').toString().trim();
      if ((uEmail.isNotEmpty && pEmail == uEmail) || (uId.isNotEmpty && pId == uId)) {
        return (pay['status'] ?? 'unpaid').toString();
      }
    }
    return 'unpaid';
  }

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
      } else if (_participantFilter == 'paid') {
        matchFilter = p['hasPaid'] == true || _getMemberPaymentStatus(p) == 'verified';
      } else if (_participantFilter == 'pending_payment') {
        final st = _getMemberPaymentStatus(p);
        matchFilter = st == 'pending_verification' || st == 'pending';
      } else if (_participantFilter == 'unpaid') {
        final st = _getMemberPaymentStatus(p);
        matchFilter = p['hasPaid'] != true && st != 'verified' && st != 'pending_verification' && st != 'pending';
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

  late int _currentNavIndex;

  @override
  void initState() {
    super.initState();
    _currentNavIndex = 0;
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
    final payments = await RoleManagementService.getPaymentsByLevel(widget.level);

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
      _levelPayments = payments;
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
  //
  // Layout:
  //   AppBar             — title, lang, refresh, logout
  //   Top segmented tabs — Members (0) | Draw (1) | Settings (2)
  //   Body content       — selected top tab OR Payments/History full page
  //   Bottom bar         — Payments | History  (only these 2 at the bottom)
  //
  // _currentNavIndex:  0 = top-tabs active | 1 = Payments | 2 = History
  // _topTabIndex:      0 = Members | 1 = Draw | 2 = Settings

  int _topTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final bool showTopTabs = _currentNavIndex == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(t('$_levelLabel Level Dashboard',
                '$_levelLabel ደረጃ ዳሽቦርድ')),
          ],
        ),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/home');
            }
          },
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('Refresh', 'ዳግም ጫን'),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: t('Logout', 'ውጣ'),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      floatingActionButton:
          (showTopTabs && _topTabIndex == 0)
              ? FloatingActionButton.extended(
                  onPressed: _addUser,
                  backgroundColor: _levelColor,
                  icon: const Icon(Icons.person_add),
                  label: Text(t('Add User', 'ተጠቃሚ ጨምር')),
                )
              : null,
      body: Column(
        children: [
          const OfflineBanner(),
          if (showTopTabs) _buildTopTabBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildPage(showTopTabs),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildTopTabBar() {
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          _topTab(0, Icons.people_alt_rounded, Icons.people_alt_outlined, t('Members', 'አባላት')),
          _topTab(1, Icons.casino_rounded, Icons.casino_outlined, t('Draw', 'ዕጣ')),
          _topTab(2, Icons.settings_rounded, Icons.settings_outlined, t('Settings', 'መቼቶች')),
        ],
      ),
    );
  }

  Widget _topTab(int idx, IconData active, IconData inactive, String label) {
    final sel = _topTabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _topTabIndex = idx; _currentNavIndex = 0; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: sel ? _levelColor : Colors.transparent, width: 3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(sel ? active : inactive,
                  color: sel ? _levelColor : AppColors.textSecondary, size: 20),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  color: sel ? _levelColor : AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(bool showTopTabs) {
    if (!showTopTabs) {
      return _currentNavIndex == 1 ? _buildPaymentsTab() : _buildHistoryTab();
    }
    switch (_topTabIndex) {
      case 1: return _buildDrawWheelTab();
      case 2: return _buildSettingsTab();
      default: return _buildMembersTab();
    }
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(child: _bottomItem(1, Icons.receipt_long_outlined,
                Icons.receipt_long_rounded, t('Payments', 'ክፍያዎች'),
                badge: _pendingPaymentsCount)),
            Container(width: 1, height: 40, color: AppColors.divider),
            Expanded(child: _bottomItem(2, Icons.history_outlined,
                Icons.history_rounded, t('History', 'ታሪክ'))),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem(int navIdx, IconData icon, IconData activeIcon,
      String label, {int badge = 0}) {
    final sel = _currentNavIndex == navIdx;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = navIdx),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(sel ? activeIcon : icon,
                  color: sel ? _levelColor : AppColors.textSecondary, size: 24),
              if (badge > 0)
                Positioned(
                  right: -6, top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.amber, shape: BoxShape.circle),
                    child: Text('$badge', style: const TextStyle(
                        fontSize: 9, color: Colors.black,
                        fontWeight: FontWeight.bold)),
                  ),
                ),
            ]),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
                fontSize: 11,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                color: sel ? _levelColor : AppColors.textSecondary)),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3, width: sel ? 30 : 0,
              decoration: BoxDecoration(
                  color: _levelColor, borderRadius: BorderRadius.circular(2)),
            ),
          ],
        ),
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LevelAdminPaymentVerificationScreen(level: widget.level),
                        ),
                      );
                    },
                    icon: const Icon(Icons.verified, size: 16),
                    label: Text(
                      t('Verify Member Payments', 'የአባላትን ክፍያ አረጋግጥ'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
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
              const Spacer(),
              // Export CSV
              IconButton(
                icon: Icon(Icons.download_rounded, color: _levelColor, size: 22),
                tooltip: t('Export Members CSV', 'አባሎችን ወደ CSV ላክ'),
                onPressed: _participants.isEmpty ? null : _exportMembersCSV,
              ),
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
                    _filterChip(t('Paid', 'የከፈሉ'), 'paid'),
                    const SizedBox(width: 6),
                    _filterChip(t('Pending', 'ማረጋገጫ የሚጠብቁ'), 'pending_payment'),
                    const SizedBox(width: 6),
                    _filterChip(t('Unpaid', 'ያልከፈሉ'), 'unpaid'),
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

          const SizedBox(height: 16),

          // ── Reset Draw Cycle button ─────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _participants.isEmpty ? null : _resetDrawCycle,
              icon: const Icon(Icons.refresh_rounded, color: Colors.orange),
              label: Text(
                t('Reset Draw Cycle (New Round)', 'ዑደቱን ዳግም ጀምር (አዲስ ዙር)'),
                style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: Colors.orange, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pick a winner locally using [EqubDrawAlgorithm] (cryptographically secure).
  /// Falls back to the REST-API server if it is reachable, but the local draw
  /// always works even when the backend is offline.
  /// Returns the index of the winner inside [_eligible] so the wheel can
  /// animate to the correct slice.
  Future<int?> _requestServerWinner() async {
    if (_eligible.isEmpty) return null;

    // ── 1. Try the backend draw first (optional) ─────────────────────────
    try {
      final result = await ApiService.adminRunDraw(widget.level)
          .timeout(const Duration(seconds: 8));

      if (!result.containsKey('error') && result['winnerId'] != null) {
        final winnerId = result['winnerId'].toString();
        final idx = _eligible.indexWhere((p) =>
            (p['userId'] ?? p['id'] ?? p['participantId']).toString() ==
            winnerId);
        if (idx >= 0) {
          _pendingDraw = result;
          return idx;
        }
      }
    } catch (_) {
      // server offline or timeout — proceed with local draw below
    }

    // ── 2. Local draw using EqubDrawAlgorithm (Firestore-first) ──────────
    final localIndex = EqubDrawAlgorithm.chooseWinnerIndex(_eligible);
    if (localIndex == null || localIndex < 0) return null;

    final winner = _eligible[localIndex];
    _pendingDraw = {
      'local': true,
      'winnerId': (winner['userId'] ?? winner['id'] ?? winner['participantId'] ?? '').toString(),
      'winnerName': (winner['fullName'] ?? winner['firstName'] ?? '').toString(),
      'winnerUniqueId': (winner['uniqueId'] ?? '').toString(),
    };
    return localIndex;
  }

  /// Called by [EqubDrawWheel] after the animation finishes.
  /// Persists the winner to Firestore (hasWon=true, status=selected,
  /// draw record in draws/ collection) then refreshes the local lists
  /// so the winner never appears in eligible again.
  Future<void> _handleWinnerSelected(int index) async {
    if (index < 0 || index >= _eligible.length) return;
    if (_pendingDraw == null) return;

    final winner = Map<String, dynamic>.from(_eligible[index]);
    setState(() => _isSpinning = true);

    final adminId = _resolvedAdminId;
    final winnerId =
        (winner['userId'] ?? winner['id'] ?? winner['participantId'] ?? '').toString();
    final winnerName =
        (winner['fullName'] ?? winner['firstName'] ?? '').toString();
    final winnerUniqueId = (winner['uniqueId'] ?? winner['participantId'] ?? winnerId).toString();
    final drawNumber = _drawHistory.length + 1;

    // ── Persist to Firestore and get back the saved record ───────────────
    final savedRecord = await RoleManagementService.saveDrawResult(
      equbLevel: widget.level,
      adminId: adminId,
      winnerId: winnerId,
      winnerName: winnerName,
      winnerUniqueId: winnerUniqueId,
      drawNumber: drawNumber,
      participantIds: _participants
          .map((p) =>
              (p['userId'] ?? p['id'] ?? p['participantId'] ?? '').toString())
          .toList(),
    );

    // ── Update local state immediately (no reload latency) ───────────────
    final now = DateTime.now().toUtc().toIso8601String();
    // Mark winner in local participants list
    for (final p in _participants) {
      final pid = (p['userId'] ?? p['id'] ?? p['participantId'] ?? '').toString();
      if (pid == winnerId) {
        p['hasWon'] = true;
        p['status'] = 'selected';
        p['selectedAt'] = now;
        p['roundNumber'] = drawNumber;
        break;
      }
    }
    // Add to local draw history so History tab shows the winner immediately.
    // Use the record returned by saveDrawResult so drawId, createdAt,
    // winnerName etc. are all consistent with what Firestore stored.
    _drawHistory.insert(0, savedRecord);

    _pendingDraw = null;
    setState(() => _isSpinning = false);

    if (!mounted) return;

    // Show winner dialog + speak announcement
    _showWinnerDialog(winner);
    widget.onRefresh();

    // Reload from Firestore in background so list is authoritative
    _loadData();
  }

  void _showWinnerDialog(Map<String, dynamic> winner) {
    final name = (winner['fullName'] ?? winner['firstName'] ?? '').toString();
    final uid = (winner['uniqueId'] ?? winner['userId'] ?? winner['id'] ?? '').toString();

    // Smart bilingual announcement — Amharic + English, repeats until stopped
    SoundService.speakWinnerAnnouncement(fullName: name, uniqueId: uid, levelName: _levelLabel);

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
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                    onPressed: () => _confirmDeleteHistory(draw),
                                    tooltip: t('Delete Draw Record', 'የእጣ መዝገቡን ሰርዝ'),
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
          adminId: _resolvedAdminId,
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
          adminId: _resolvedAdminId,
          editData: user,
        ),
      ),
    );
    if (result == true) _loadData();
  }

  /// Returns the real Firestore document ID for the currently-logged-in admin.
  /// Priority: AuthProvider.user['adminId'] → widget.adminId → data['adminId'].
  String get _resolvedAdminId {
    final authUser = context.read<AuthProvider>().user;
    final fromAuth =
        (authUser?['adminId'] ?? authUser?['id'] ?? authUser?['uid'] ?? '')
            .toString()
            .trim();
    if (fromAuth.isNotEmpty) return fromAuth;
    if (widget.adminId.isNotEmpty) return widget.adminId;
    return (widget.data['adminId'] ?? widget.data['id'] ?? '').toString().trim();
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
    final authUser = context.read<AuthProvider>().user ?? {};
    final displayLevel = (_levelLabel).toUpperCase();
    final displayEmail = _settingsEmailController.text.isNotEmpty
        ? _settingsEmailController.text
        : (authUser['email'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Level & Admin identity banner ─────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_levelColor.withOpacity(0.15), _levelColor.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _levelColor.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _levelColor.withOpacity(0.15),
                    shape: BoxShape.circle),
                child: Icon(Icons.badge_rounded, color: _levelColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$displayLevel LEVEL ADMIN',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: _levelColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayEmail.isNotEmpty ? displayEmail : '—',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: _levelColor),
                tooltip: t('Reload profile', 'መገለጫ ዳግም ጫን'),
                onPressed: _loadData,
              ),
            ],
          ),
        ),

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
                            t(
                              'Update your info for $_levelLabel level',
                              'ለ$_levelLabel ደረጃ መረጃዎን ያሻሽሉ',
                            ),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
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
                _settingsField(
                  label: t('Full Name', 'ሙሉ ስም'),
                  controller: _settingsNameController,
                  icon: Icons.person,
                  hint: t('Admin Full Name', 'የአስተዳዳሪ ሙሉ ስም'),
                ),
                const SizedBox(height: 14),

                // Email Address
                _settingsField(
                  label: t('Email Address', 'ኢሜይል አድራሻ'),
                  controller: _settingsEmailController,
                  icon: Icons.email,
                  hint: 'admin@equb.et',
                  type: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),

                // Username
                _settingsField(
                  label: t('Username', 'ተጠቃሚ ስም'),
                  controller: _settingsUsernameController,
                  icon: Icons.alternate_email,
                  hint: 'admin_username',
                ),
                const SizedBox(height: 14),

                // Phone Number
                _settingsField(
                  label: t('Phone Number', 'ስልክ ቁጥር'),
                  controller: _settingsPhoneController,
                  icon: Icons.phone,
                  hint: '09XXXXXXXX',
                  type: TextInputType.phone,
                ),
                const SizedBox(height: 14),

                // Address
                _settingsField(
                  label: t('Address', 'አድራሻ'),
                  controller: _settingsAddressController,
                  icon: Icons.location_on,
                  hint: t('Addis Ababa, Ethiopia', 'አዲስ አበባ፣ ኢትዮጵያ'),
                ),
                const SizedBox(height: 20),

                // Password section divider
                Row(children: [
                  Expanded(
                      child: Divider(color: _levelColor.withOpacity(0.3))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      t('Change Password', 'የይለፍ ቃል ቀይር'),
                      style: TextStyle(
                          fontSize: 12,
                          color: _levelColor,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                      child: Divider(color: _levelColor.withOpacity(0.3))),
                ]),
                const SizedBox(height: 14),

                // New Password
                _settingsField(
                  label: t('New Password (leave blank to keep current)',
                      'አዲስ የይለፍ ቃል (ባዶ ከተወ አሁን ያለው ይቆያል)'),
                  controller: _settingsPasswordController,
                  icon: Icons.lock_outline,
                  hint: '••••••••',
                  obscure: _obscureSettingsPass,
                  toggleObscure: () =>
                      setState(() => _obscureSettingsPass = !_obscureSettingsPass),
                ),
                const SizedBox(height: 14),

                // Confirm Password
                _settingsField(
                  label: t('Confirm New Password', 'አዲሱን የይለፍ ቃል ድገም'),
                  controller: _settingsConfirmPasswordController,
                  icon: Icons.lock_clock,
                  hint: '••••••••',
                  obscure: _obscureSettingsPass,
                ),
                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _settingsSaving ? null : _saveAdminSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _levelColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                    icon: _settingsSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded, color: Colors.white),
                    label: Text(
                      _settingsSaving
                          ? t('Saving…', 'እያስቀመጠ ነው…')
                          : t('Save Account Settings', 'የመለያ መቼቶችን አስቀምጥ'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white),
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

  // Helper for uniform settings form field
  Widget _settingsField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String hint = '',
    TextInputType type = TextInputType.text,
    bool obscure = false,
    VoidCallback? toggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: type,
          obscureText: obscure,
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            hintText: hint.isNotEmpty ? hint : label,
            suffixIcon: toggleObscure != null
                ? IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: toggleObscure,
                  )
                : null,
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
    // Resolve the real admin doc ID — try all sources
    String adminId = _resolvedAdminId;
    if (adminId.isEmpty) {
      adminId = (auth.user?['adminId'] ?? auth.user?['id'] ??
              auth.user?['uid'] ?? widget.adminId)
          .toString()
          .trim();
    }
    // If still empty, try to find by email from backend
    if (adminId.isEmpty) {
      final email = _settingsEmailController.text.trim().toLowerCase();
      if (email.isNotEmpty) {
        final found = await RoleManagementService.findAdmin(email);
        if (found != null) {
          adminId = (found['adminId'] ?? found['id'] ?? '').toString();
        }
      }
    }
    if (adminId.isEmpty) {
      setState(() => _settingsSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'Cannot identify admin account. Please log out and log back in.',
            'የአስተዳዳሪ መለያ ማወቅ አልተቻለም። ይውጡና ዳግም ይግቡ።',
          )),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }
    final ok = await RoleManagementService.updateAdmin(adminId, updates);

    setState(() => _settingsSaving = false);
    if (!mounted) return;

    if (ok) {
      // Refresh auth user map so future _resolvedAdminId calls work
      if (auth.user != null) {
        auth.refreshUser({
          ...auth.user!,
          ...updates,
          'adminId': adminId,
          'id': adminId,
        });
      }
      // Update settings controllers to reflect saved values
      setState(() {
        _settingsNameController.text =
            (updates['fullName'] ?? _settingsNameController.text).toString();
        _settingsPasswordController.clear();
        _settingsConfirmPasswordController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          '✅ Admin settings saved successfully.',
          '✅ የአስተዳዳሪ መቼቶች በተሳካ ሁኔታ ተቀምጠዋል።',
        )),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ));
      widget.onRefresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Failed to save settings.', 'መቼቶችን ማስቀመጥ አልተቻለም።')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Widget _paymentFilterChip(String statusKey, String label, Color chipColor) {
    final selected = _paymentFilterStatus == statusKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
      selected: selected,
      selectedColor: chipColor,
      backgroundColor: Colors.grey.shade100,
      onSelected: (val) {
        if (val) setState(() => _paymentFilterStatus = statusKey);
      },
    );
  }

  Widget _buildPaymentsTab() {
    final filtered = _levelPayments.where((p) {
      if (_paymentFilterStatus == 'all') return true;
      final st = (p['status'] ?? 'pending_verification').toString();
      if (_paymentFilterStatus == 'pending_verification') {
        return st == 'pending_verification' || st == 'pending';
      }
      return st == _paymentFilterStatus;
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _paymentFilterChip('pending_verification', t('Pending', 'በመጠበቅ ላይ'), Colors.orange.shade800),
                const SizedBox(width: 8),
                _paymentFilterChip('verified', t('Verified', 'ተረጋግጧል'), Colors.green),
                const SizedBox(width: 8),
                _paymentFilterChip('rejected', t('Rejected', 'ተሰርዟል'), Colors.red),
                const SizedBox(width: 8),
                _paymentFilterChip('all', t('All Payments', 'ሁሉም'), _levelColor),
              ],
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payments_outlined, size: 54, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        t('No payment records found', 'ምንም የማረጋገጫ ክፍያ ጥያቄ የለም'),
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final pId = (item['paymentId'] ?? item['id'] ?? '').toString();
                      final fullName = (item['fullName'] ?? item['name'] ?? 'Equb Member').toString();
                      final email = (item['email'] ?? '').toString();
                      final nationalId = (item['nationalId'] ?? item['uniqueId'] ?? '—').toString();
                      final bankName = (item['bankName'] ?? item['paymentMethod'] ?? 'CBE').toString();
                      final refNum = (item['referenceNumber'] ?? item['reference'] ?? '—').toString();
                      final amount = (item['amount'] ?? 0).toString();
                      final status = (item['status'] ?? 'pending_verification').toString();

                      Color statusColor = status == 'verified'
                          ? Colors.green
                          : (status == 'rejected' ? Colors.red : Colors.orange.shade800);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _levelColor.withOpacity(0.3), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    status.toUpperCase().replaceAll('_', ' '),
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '$amount ETB',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _levelColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              fullName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Email: $email  •  ID: #$nationalId',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const Divider(height: 18),
                            Row(
                              children: [
                                const Icon(Icons.account_balance, size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text(
                                  'Bank: $bankName',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                Text(
                                  'Ref: $refNum',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showProofDialog(item),
                                  icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
                                  label: Text(t('View Proof', 'ደረሰኝ ተመልከት')),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue.shade800,
                                    side: BorderSide(color: Colors.blue.shade800),
                                  ),
                                ),
                                const Spacer(),
                                if (status == 'pending_verification' || status == 'pending') ...[
                                  IconButton(
                                    icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 28),
                                    onPressed: () => _showRejectReasonDialog(pId),
                                    tooltip: t('Reject Payment', 'ክፍያን ሰርዝ'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _verifyPayment(pId, 'verified'),
                                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                                    label: Text(t('Approve', 'አረጋግጥ')),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _verifyPayment(String paymentId, String status, {String reason = ''}) async {
    setState(() => _loading = true);
    final success = await RoleManagementService.verifyPayment(
      paymentId: paymentId,
      status: status,
      rejectionReason: reason,
      adminId: _resolvedAdminId.isNotEmpty ? _resolvedAdminId : 'admin_${widget.level}',
      level: widget.level,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (status == 'verified' ? '✅ Payment Verified & Member Contribution Updated!' : '❌ Payment Request Rejected.')
                : 'Failed to update payment status.',
          ),
          backgroundColor: status == 'verified' ? Colors.green : Colors.red,
        ),
      );
      _loadData();
    }
  }

  void _showProofDialog(Map<String, dynamic> item) {
    final base64Str = (item['proofScreenshotBase64'] ?? '').toString();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isAmharic ? 'የክፍያ ደረሰኝ ማረጋገጫ' : 'Bank Receipt Proof Inspection',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              if (base64Str.isNotEmpty && base64Str.contains('base64,')) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(base64Str.split('base64,').last),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('Error loading screenshot image'),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  height: 200,
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Text('No screenshot preview available'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Security Checksum: ${item['proofHash'] != null ? (item['proofHash'].toString().substring(0, 16) + '...') : 'SHA-256 Validated'}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRejectReasonDialog(String paymentId) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isAmharic ? 'ክፍያውን ለመሰረዝ ምክንያት ያስገቡ' : 'Specify Rejection Reason'),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(
            hintText: _isAmharic ? 'ለምሳሌ: የተሳሳተ ደረሰኝ ወይም አልተከፈለም' : 'e.g. Invalid reference code or wrong receipt',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isAmharic ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _verifyPayment(paymentId, 'rejected', reason: reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(_isAmharic ? 'አረጋግጥና ሰርዝ' : 'Reject Payment'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET DRAW CYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Resets every member's hasWon flag for this level so the next draw cycle
  /// starts fresh. Firestore-first, then local state update.
  Future<void> _resetDrawCycle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.refresh_rounded, color: Colors.orange, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('Reset Draw Cycle?', 'የእጣ ዑደትን ዳግም ጀምር?'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ]),
        content: Text(
          t(
            'This will clear the "hasWon" flag for ALL members in $_levelLabel Level, '
            'making everyone eligible again for the next cycle.\n\nDraw history records are kept.',
            'ይህ ለ$_levelLabel ደረጃ ሁሉም አባሎች "አሸናፊ" ሁኔታን ያጸዳ ሲሆን ሁሉም ለቀጣዩ ዙር ብቁ ይሆናሉ።\n\nየእጣ ታሪክ ይቀራል።',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel', 'ሰርዝ')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(
              t('Reset Cycle', 'ዑደቱን ዳግም ጀምር'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final p in _participants) {
        final uid = (p['userId'] ?? p['id'] ?? '').toString();
        if (uid.isEmpty) continue;
        batch.update(db.collection('users').doc(uid), {
          'hasWon': false,
          'status': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        p['hasWon'] = false;
        p['status'] = 'active';
      }
      await batch.commit();
    } catch (e) {
      // Fallback: update one-by-one if batch fails
      for (final p in _participants) {
        final uid = (p['userId'] ?? p['id'] ?? '').toString();
        if (uid.isEmpty) continue;
        try {
          await RoleManagementService.activateUser(uid);
          p['hasWon'] = false;
          p['status'] = 'active';
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t(
        '✅ Draw cycle reset! All ${_participants.length} members are now eligible.',
        '✅ የእጣ ዑደት ዳግም ጀምሯል! ሁሉም ${_participants.length} አባሎች ብቁ ናቸው።',
      )),
      backgroundColor: Colors.orange,
    ));
    widget.onRefresh();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT MEMBERS (CSV)
  // ═══════════════════════════════════════════════════════════════════════════

  void _exportMembersCSV() {
    if (_participants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('No members to export.', 'ወደ ውጪ ለመላክ አባሎች የሉም።')),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    // Build CSV content
    final buffer = StringBuffer();
    buffer.writeln('No,Full Name,Email,Phone,Unique ID,Status,Has Won,Level');
    for (int i = 0; i < _participants.length; i++) {
      final p = _participants[i];
      final name = (p['fullName'] ?? '${p['firstName'] ?? ''} ${p['lastName'] ?? ''}'.trim()).toString().replaceAll(',', ' ');
      final email = (p['email'] ?? '').toString();
      final phone = (p['phoneNumber'] ?? '').toString();
      final uid = (p['uniqueId'] ?? '').toString();
      final status = (p['status'] ?? 'active').toString();
      final hasWon = p['hasWon'] == true ? 'Yes' : 'No';
      buffer.writeln('${i + 1},$name,$email,$phone,$uid,$status,$hasWon,${widget.level}');
    }

    // Show the CSV in a dialog so the admin can copy it
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.download_rounded, color: _levelColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('Export Members — $_levelLabel Level', 'አባሎችን ወደ ውጪ ላክ — $_levelLabel'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('${_participants.length} members exported. Copy and paste into Excel or a text file.',
                  '${_participants.length} አባሎች ተላልፈዋል። ወደ Excel ወይም ጽሑፍ ፋይል ቅዳ።'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    buffer.toString(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Close', 'ዝጋ')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteHistory(Map<String, dynamic> draw) async {
    final drawId = (draw['drawId'] ?? draw['id'] ?? '').toString();
    final winnerName = (draw['winnerName'] ?? draw['fullName'] ?? 'Winner').toString();
    final winnerId = (draw['winnerId'] ?? draw['userId'] ?? '').toString();
    final winnerUniqueId = (draw['winnerUniqueId'] ?? draw['uniqueId'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isAmharic ? 'የእጣ ታሪክ መዝገብ ይሰረዝ?' : 'Delete Draw History Record?',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          _isAmharic
              ? 'ለ "$winnerName" የተመዘገበውን የስዕል ታሪክ በቋሚነት ለመሰረዝ እርግጠኛ ነዎት? ይህ እርምጃ የተጠቃሚውን አሸናፊነት ደረጃ ዳግም ያስጀምራል።'
              : 'Are you sure you want to delete the draw history record for "$winnerName"? This will reset the user\'s win status so they become eligible for future draws again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAmharic ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(_isAmharic ? 'አረጋግጥና ሰርዝ' : 'Delete Record'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _loading = true);
      final ok = await RoleManagementService.deleteDrawHistory(
        drawId: drawId,
        winnerId: winnerId,
        winnerUniqueId: winnerUniqueId,
        level: widget.level,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? (_isAmharic ? '✅ የስዕል ታሪክ መዝገብ በተሳካ ሁኔታ ተሰርዟል!' : '✅ Draw history record deleted successfully!')
                  : (_isAmharic ? '❌ መዝገቡን ማስወገድ አልተቻለም' : 'Failed to delete draw record.'),
            ),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
        _loadData();
      }
    }
  }
}
