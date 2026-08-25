import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import '../../utils/constants.dart';
import '../../widgets/page_header_banner.dart';
import '../../widgets/smart_back_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EqubHistoryScreen
//
// Public-facing history page showing draw winners for ALL three equb levels.
// Users can switch between Low / Medium / High tabs.
// Admins and super-admins additionally see a delete button on each record.
// ─────────────────────────────────────────────────────────────────────────────
class EqubHistoryScreen extends StatefulWidget {
  /// Pre-selects a tab on open.  Defaults to 'low'.
  final String initialLevel;
  const EqubHistoryScreen({super.key, this.initialLevel = 'low'});

  @override
  State<EqubHistoryScreen> createState() => _EqubHistoryScreenState();
}

class _EqubHistoryScreenState extends State<EqubHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Ordered list of the three levels shown as tabs
  static const List<String> _levels = ['low', 'medium', 'high'];

  // Per-level data caches and loading flags
  final Map<String, List<Map<String, dynamic>>> _historyMap = {
    'low': [],
    'medium': [],
    'high': [],
  };
  final Map<String, bool> _loadingMap = {
    'low': false,
    'medium': false,
    'high': false,
  };
  final Map<String, bool> _loadedMap = {
    'low': false,
    'medium': false,
    'high': false,
  };

  @override
  void initState() {
    super.initState();
    final initialIndex =
        _levels.indexOf(widget.initialLevel.toLowerCase().replaceAll('equb_', ''));
    _tabs = TabController(
      length: _levels.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    );
    // Load the initially visible tab immediately
    _loadLevel(_levels[_tabs.index]);

    // Lazy-load other tabs when switched
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        final level = _levels[_tabs.index];
        if (!(_loadedMap[level] ?? false)) _loadLevel(level);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLevel(String level) async {
    if (_loadingMap[level] == true) return;
    setState(() => _loadingMap[level] = true);
    try {
      final list = await RoleManagementService.getDrawHistory(level);
      if (mounted) {
        setState(() {
          _historyMap[level] =
              list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loadingMap[level] = false;
          _loadedMap[level] = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMap[level] = false);
    }
  }

  // Colours / labels
  Color _color(String level) {
    switch (level) {
      case 'medium':
        return AppColors.medium;
      case 'high':
        return AppColors.high;
      default:
        return AppColors.low;
    }
  }

  String _label(String level) {
    switch (level) {
      case 'medium':
        return 'Medium';
      case 'high':
        return 'High';
      default:
        return 'Low';
    }
  }

  String _amLabel(String level) {
    switch (level) {
      case 'medium':
        return 'መካከለኛ';
      case 'high':
        return 'ከፍተኛ';
      default:
        return 'ዝቅተኛ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAmharic = AppConstants.currentLanguage == 'am';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Animated page banner ───────────────────────────────────────
            PageHeaderBanner(
              color: const Color(0xFF1A237E),
              icon: Icons.emoji_events_rounded,
              phrases: PageHeaderBanner.historyPhrases,
              staticTitle:
                  isAmharic ? 'የዕጣ ታሪክ — ሁሉም ደረጃዎች' : 'Equb Draw History — All Levels',
            ),

            // ── AppBar-style row ──────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  const SmartBackButton(),
                  Expanded(
                    child: Text(
                      isAmharic ? 'የዕጣ አሸናፊዎች ታሪክ' : 'All-Level Draw Winners',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  // Refresh current tab
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.primary),
                    tooltip: 'Refresh',
                    onPressed: () {
                      final level = _levels[_tabs.index];
                      _loadedMap[level] = false;
                      _loadLevel(level);
                    },
                  ),
                ],
              ),
            ),

            // ── Level tabs ────────────────────────────────────────────────
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabs,
                labelPadding: EdgeInsets.zero,
                indicator: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _color(_levels[_tabs.index]),
                      width: 3,
                    ),
                  ),
                ),
                tabs: _levels.map((lvl) {
                  final selected = _levels[_tabs.index] == lvl;
                  final c = _color(lvl);
                  final count = _historyMap[lvl]?.length ?? 0;
                  return Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: selected ? c : c.withOpacity(0.3),
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAmharic ? _amLabel(lvl) : _label(lvl),
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w900
                                : FontWeight.w500,
                            fontSize: 13,
                            color: selected ? c : AppColors.textSecondary,
                          ),
                        ),
                        if ((_loadedMap[lvl] ?? false) && count > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: c,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Tab content ───────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: _levels
                    .map((lvl) => _LevelHistoryTab(
                          level: lvl,
                          color: _color(lvl),
                          isAmharic: isAmharic,
                          loading: _loadingMap[lvl] ?? false,
                          history: _historyMap[lvl] ?? [],
                          onDelete: (draw) => _confirmDelete(draw, lvl),
                          onRefresh: () => _loadLevel(lvl),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      Map<String, dynamic> draw, String level) async {
    final isAmharic = AppConstants.currentLanguage == 'am';
    final drawId = (draw['drawId'] ?? draw['id'] ?? '').toString();
    final winnerName =
        (draw['winnerName'] ?? draw['name'] ?? 'Winner').toString();
    final winnerId = (draw['winnerId'] ?? draw['userId'] ?? '').toString();
    final winnerUniqueId =
        (draw['winnerUniqueId'] ?? draw['uniqueId'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.red, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAmharic ? 'የዕጣ መዝገብ ይሰረዝ?' : 'Delete Draw Record?',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ]),
        content: Text(
          isAmharic
              ? 'ለ "$winnerName" የተመዘገበው የዕጣ ታሪክ ይሰረዛል። የዚህ ተጠቃሚ አሸናፊነት ሁኔታ ይሻሻላል።'
              : 'Delete the draw record for "$winnerName"?\nThis resets their win status so they can participate again.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAmharic ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              isAmharic ? 'አረጋግጥና ሰርዝ' : 'Delete',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final ok = await RoleManagementService.deleteDrawHistory(
        drawId: drawId,
        winnerId: winnerId,
        winnerUniqueId: winnerUniqueId,
        level: level,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            ok
                ? (isAmharic
                    ? '✅ መዝገቡ ተሰርዟል'
                    : '✅ Record deleted successfully')
                : (isAmharic ? '❌ ሰርዝ አልተቻለም' : '❌ Failed to delete'),
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
        ));
        if (ok) {
          _loadedMap[level] = false;
          _loadLevel(level);
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LevelHistoryTab — content for one level tab
// ─────────────────────────────────────────────────────────────────────────────
class _LevelHistoryTab extends StatelessWidget {
  final String level;
  final Color color;
  final bool isAmharic, loading;
  final List<Map<String, dynamic>> history;
  final void Function(Map<String, dynamic>) onDelete;
  final VoidCallback onRefresh;

  const _LevelHistoryTab({
    required this.level,
    required this.color,
    required this.isAmharic,
    required this.loading,
    required this.history,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isAdmin ||
        context.watch<AuthProvider>().isSuperAdmin;

    if (loading) {
      return Center(
        child: CircularProgressIndicator(color: color),
      );
    }

    final priceRange =
        AppConstants.getLevelPriceRange(level, isAmharic: isAmharic);
    final netPrize =
        AppConstants.getLevelNetPrize(level, isAmharic: isAmharic);

    return Column(
      children: [
        // ── Level summary bar ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: color.withOpacity(0.06),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAmharic
                          ? 'ክፍያ: $priceRange'
                          : 'Contribution: $priceRange',
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      isAmharic
                          ? 'ጠቅላላ ድል አበል: $netPrize'
                          : 'Net prize: $netPrize',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${history.length} ${isAmharic ? "አሸናፊዎች" : "Winners"}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        // ── History list ───────────────────────────────────────────────
        Expanded(
          child: history.isEmpty
              ? _EmptyState(color: color, isAmharic: isAmharic)
              : RefreshIndicator(
                  onRefresh: () async => onRefresh(),
                  color: color,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: history.length,
                    itemBuilder: (_, i) => _WinnerCard(
                      draw: history[i],
                      index: i,
                      color: color,
                      isAmharic: isAmharic,
                      netPrize: netPrize,
                      isAdmin: isAdmin,
                      onDelete: onDelete,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WinnerCard
// ─────────────────────────────────────────────────────────────────────────────
class _WinnerCard extends StatelessWidget {
  final Map<String, dynamic> draw;
  final int index;
  final Color color;
  final bool isAmharic, isAdmin;
  final String netPrize;
  final void Function(Map<String, dynamic>) onDelete;

  const _WinnerCard({
    required this.draw,
    required this.index,
    required this.color,
    required this.isAmharic,
    required this.netPrize,
    required this.isAdmin,
    required this.onDelete,
  });

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = raw is String
          ? DateTime.parse(raw)
          : (raw as dynamic).toDate() as DateTime;
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final mm = dt.month.toString().padLeft(2, '0');
      final dd = dt.day.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.year}-$mm-$dd  •  $h:$min $period';
    } catch (_) {
      final s = raw.toString();
      return s.length > 16 ? s.substring(0, 16) : s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawNum = draw['drawNumber'] ?? (index + 1);
    final winnerName =
        (draw['winnerName'] ?? draw['name'] ?? '—').toString();
    final winnerId =
        (draw['winnerUniqueId'] ?? draw['winnerNationalId'] ?? draw['winnerId'] ?? '—')
            .toString();
    final date = _formatDate(draw['createdAt'] ?? draw['drawDate']);
    final isLatest = index == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isLatest ? color : color.withOpacity(0.2),
          width: isLatest ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isLatest ? 0.15 : 0.06),
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
            // Round badge + trophy + delete
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amberAccent, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        isAmharic
                            ? '$drawNumኛ ዙር አሸናፊ'
                            : 'Round #$drawNum Winner',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLatest) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isAmharic ? 'ቅርብ ጊዜ' : 'Latest',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.emoji_events,
                      color: Colors.amber, size: 17),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red, size: 19),
                    onPressed: () => onDelete(draw),
                    tooltip: isAmharic ? 'ሰርዝ' : 'Delete',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 10),

            // Winner info
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withOpacity(0.15),
                  child: Text(
                    winnerName.isNotEmpty
                        ? winnerName[0].toUpperCase()
                        : 'W',
                    style: TextStyle(
                      color: color,
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
                        '${isAmharic ? "ID" : "ID"}: #$winnerId',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 18, thickness: 0.8),

            // Date + prize
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 5),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  netPrize,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyState
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final Color color;
  final bool isAmharic;
  const _EmptyState({required this.color, required this.isAmharic});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_toggle_off_rounded,
                  size: 70, color: color.withOpacity(0.35)),
              const SizedBox(height: 16),
              Text(
                isAmharic
                    ? 'እስካሁን ምንም ዕጣ አልተካሄደም'
                    : 'No draw history yet for this level',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isAmharic
                    ? 'የሳምንቱ አሸናፊ ሲመረጥ እዚህ ይቀመጣል'
                    : 'Weekly draw winners are permanently recorded here',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
