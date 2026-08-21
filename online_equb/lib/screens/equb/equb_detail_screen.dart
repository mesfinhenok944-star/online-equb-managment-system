import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/smart_back_button.dart';

class EqubDetailScreen extends StatefulWidget {
  final String equbId;
  const EqubDetailScreen({super.key, required this.equbId});
  @override
  State<EqubDetailScreen> createState() => _EqubDetailScreenState();
}

class _EqubDetailScreenState extends State<EqubDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _equb;
  List<dynamic> _draws = [];
  bool _loading = true;
  bool _joining = false;
  bool _alreadyJoined = false;
  String _paymentMethod = 'bank_transfer';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      Map<String, dynamic>? equb;
      List<dynamic> draws = [];
      try {
        equb = await FirestoreService.getEqubById(widget.equbId);
      } catch (_) {
        equb = null;
      }

      try {
        draws = await ApiService.getEqubDraws(widget.equbId);
      } catch (_) {
        draws = [];
      }

      if (equb == null) {
        // fallback to ApiService
        try {
          equb = await ApiService.getEqub(widget.equbId);
        } catch (_) {
          equb = null;
        }
      }

      if (mounted) {
        setState(() {
          _equb = equb;
          _draws = draws;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final res = await ApiService.joinEqub(widget.equbId, _paymentMethod);
      if (!mounted) return;
      if (res['participantId'] != null) {
        setState(() => _alreadyJoined = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Joined successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      } else {
        final err = res['error'] as String? ?? 'Failed to join';
        // Already joined — treat as joined state
        if (err.toLowerCase().contains('already')) {
          setState(() => _alreadyJoined = true);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Connection error'),
              backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _joining = false);
  }

  Color get _levelColor => switch (_equb?['level']) {
        'low' => AppColors.low,
        'medium' => AppColors.medium,
        'high' => AppColors.high,
        _ => AppColors.primary,
      };

  String get _levelLabel => switch (_equb?['level']) {
        'low' => 'ዝቅተኛ · Low',
        'medium' => 'መካከለኛ · Medium',
        'high' => 'ከፍተኛ · High',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: const SmartBackButton()),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_equb == null) {
      return Scaffold(
        appBar: AppBar(leading: const SmartBackButton()),
        body: const Center(child: Text('Equb not found')),
      );
    }

    final price = ((_equb!['price'] as num?)?.toDouble()) ?? 0;
    final prize = ((_equb!['netPrize'] as num?)?.toDouble()) ?? 0;
    final fee = ((_equb!['adminFee'] as num?)?.toDouble()) ?? 0;
    final current = ((_equb!['currentParticipants'] as num?)?.toInt()) ?? 0;
    final max = ((_equb!['maxParticipants'] as num?)?.toInt()) ?? 100;
    final status = _equb!['status'] as String? ?? '';
    final canJoin =
        (status == 'active' || status == 'pending') && !_alreadyJoined;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            leading: const SmartBackButton(color: Colors.white),
            backgroundColor: _levelColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/levels/${_equb!['level'] ?? 'low'}.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/levels/${_equb!['level'] ?? 'low'}_equb.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_levelColor, _levelColor.withOpacity(0.75)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black45,
                          _levelColor.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_equb!['name'] ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(_levelLabel,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _heroStat('Entry', '${_fmt(price)} ETB'),
                              _heroStat('Net Prize', '${_fmt(prize)} ETB'),
                              _heroStat('Fee', '${_fmt(fee)} ETB'),
                              _heroStat('Slots', '$current/$max'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              tabs: const [
                Tab(text: 'Details'),
                Tab(text: 'Draw History'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // ── Tab 1: Details + Join ──────────────────────────────────────
            _DetailsTab(
              equb: _equb!,
              levelColor: _levelColor,
              current: current,
              max: max,
              canJoin: canJoin,
              alreadyJoined: _alreadyJoined,
              joining: _joining,
              paymentMethod: _paymentMethod,
              onPaymentMethodChanged: (v) => setState(() => _paymentMethod = v),
              onJoin: _join,
            ),

            // ── Tab 2: Bingo Draw History ──────────────────────────────────
            _DrawHistoryTab(
              draws: _draws,
              max: max,
              levelColor: _levelColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Details + Join
// ─────────────────────────────────────────────────────────────────────────────
class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.equb,
    required this.levelColor,
    required this.current,
    required this.max,
    required this.canJoin,
    required this.alreadyJoined,
    required this.joining,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.onJoin,
  });

  final Map<String, dynamic> equb;
  final Color levelColor;
  final int current, max;
  final bool canJoin, alreadyJoined, joining;
  final String paymentMethod;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Slot progress
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Participants',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Text('$current / $max',
              style: TextStyle(color: levelColor, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: max > 0 ? current / max : 0,
            backgroundColor: levelColor.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(levelColor),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 20),

        // Description
        if ((equb['description'] as String? ?? '').isNotEmpty) ...[
          const Text('About',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(equb['description'] ?? '',
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 20),
        ],

        // Details grid
        const Text('Details',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _row('Payment Schedule', equb['paymentSchedule'] ?? ''),
        _row('Draw Time', equb['drawTime'] ?? ''),
        _row('Status', equb['status'] ?? ''),
        _row('Risk Level', equb['riskLevel'] ?? ''),
        _row('Target Audience', equb['targetAudience'] ?? ''),
        const SizedBox(height: 24),

        // Payment method
        if (canJoin) ...[
          const Text('Payment Method',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(children: [
            _pmChip(context, 'bank_transfer', 'Bank Transfer',
                Icons.account_balance),
            const SizedBox(width: 10),
            _pmChip(context, 'telebirr', 'Telebirr', Icons.phone_android),
          ]),
          const SizedBox(height: 20),
        ],

        // Join / status button
        SizedBox(
          width: double.infinity,
          child: alreadyJoined
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text('Already Joined',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ],
                  ),
                )
              : canJoin
                  ? ElevatedButton(
                      onPressed: joining ? null : onJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: levelColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: joining
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Join Equb',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          equb['status'] == 'completed'
                              ? 'Equb Completed'
                              : 'Equb Closed',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
              width: 140,
              child: Text(label,
                  style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _pmChip(
      BuildContext context, String value, String label, IconData icon) {
    final selected = paymentMethod == value;
    return GestureDetector(
      onTap: () => onPaymentMethodChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? levelColor : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? levelColor : AppColors.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 18,
              color: selected ? Colors.white : AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Bingo-style Draw History
// Each round: one person selected, removed from next pool (like bingo)
// Shows: round number, winner name, prize, remaining pool size
// ─────────────────────────────────────────────────────────────────────────────
class _DrawHistoryTab extends StatelessWidget {
  const _DrawHistoryTab({
    required this.draws,
    required this.max,
    required this.levelColor,
  });

  final List<dynamic> draws;
  final int max;
  final Color levelColor;

  @override
  Widget build(BuildContext context) {
    if (draws.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.casino_outlined,
                size: 64, color: levelColor.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No draws held yet',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text(
                'Each round one participant wins.\nPrevious winners are excluded from future draws.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Algorithm info banner
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: levelColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: levelColor.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, color: levelColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bingo Algorithm: Each round selects 1 winner from remaining pool. '
                'Winners are permanently excluded. '
                '${draws.length}/$max rounds complete.',
                style: TextStyle(
                    fontSize: 12,
                    color: levelColor,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),

        // Progress bar for rounds
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${draws.length} rounds held',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('${max - draws.length} remaining',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: max > 0 ? draws.length / max : 0,
                  backgroundColor: levelColor.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation(levelColor),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Draw list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: draws.length,
            itemBuilder: (_, i) {
              final d = draws[i] as Map<String, dynamic>;
              final drawNum = d['drawNumber'] as int? ?? (i + 1);
              final name = d['winnerName'] as String? ?? '—';
              final phone = d['winnerPhone'] as String? ?? '';
              final prize = (d['prizeAmount'] as num?)?.toDouble() ?? 0;
              final date = d['drawDate'] as String? ?? '';
              final remaining = max - drawNum; // pool after this draw
              final isLatest = i == draws.length - 1;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLatest
                        ? levelColor.withOpacity(0.5)
                        : AppColors.divider,
                    width: isLatest ? 1.5 : 1,
                  ),
                  boxShadow: isLatest
                      ? [
                          BoxShadow(
                              color: levelColor.withOpacity(0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]
                      : null,
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        backgroundColor: levelColor.withOpacity(0.15),
                        radius: 22,
                        child: Text(
                          '#$drawNum',
                          style: TextStyle(
                              color: levelColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                      if (isLatest)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(children: [
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    if (isLatest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Latest',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (phone.isNotEmpty)
                        Text(phone,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.calendar_today,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(date,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        const Icon(Icons.group,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          remaining >= 0
                              ? '$remaining left in pool'
                              : 'Pool complete',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ]),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_fmt(prize)} ETB',
                        style: TextStyle(
                            color: levelColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      const Text('prize',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _fmt(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}
