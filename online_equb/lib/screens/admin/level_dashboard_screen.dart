import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/role_management_service.dart';
import '../../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _isAmharic = widget.isAmharic;
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final users = await RoleManagementService.getUsersByLevel(widget.level);
    final history = await RoleManagementService.getDrawHistory(widget.level);
    if (!mounted) return;
    setState(() {
      _participants = users;
      _drawHistory = history;
      _loading = false;
    });
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
          onPressed: () => Navigator.pop(context),
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
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 – Members
  // ═══════════════════════════════════════════════════════════════════════════
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
    final name = winner['fullName'] ?? '';
    final uid = winner['uniqueId'] ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
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
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _levelColor),
              child: Text(t('Close', 'ዝጋ')),
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
    if (_drawHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              t('No draws yet. Run the wheel to start.',
                  'ምንም ስዕሎች የሉም። ስዕሉን ያሽከርክሩ።'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _drawHistory.length,
        itemBuilder: (_, i) {
          final draw = _drawHistory[i];
          final drawNum = draw['drawNumber'] ?? (i + 1);
          final winnerName = draw['winnerName'] ?? 'N/A';
          final winnerId = draw['winnerUniqueId'] ?? draw['winnerId'] ?? 'N/A';
          final createdAt = draw['createdAt'];
          String dateStr = '';
          if (createdAt != null) {
            try {
              final dt = createdAt is String
                  ? DateTime.parse(createdAt)
                  : (createdAt as dynamic).toDate();
              dateStr =
                  '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            } catch (_) {
              dateStr = createdAt.toString().substring(0, 10);
            }
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _levelColor,
                child: Text('$drawNum',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(winnerName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${t('ID', 'መ')}: $winnerId\n${t('Date', 'ቀን')}: $dateStr',
                style: const TextStyle(height: 1.4),
              ),
              isThreeLine: true,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emoji_events, color: AppColors.warning),
              ),
            ),
          );
        },
      ),
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
}
