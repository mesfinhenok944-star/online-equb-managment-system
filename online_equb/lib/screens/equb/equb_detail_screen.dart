import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../services/role_management_service.dart';
import '../../services/firestore_direct_service.dart';
import '../../utils/constants.dart';
import '../../widgets/equb_draw_wheel.dart';
import '../payment/payment_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EqubDetailScreen
// ─────────────────────────────────────────────────────────────────────────────
class EqubDetailScreen extends StatefulWidget {
  final String equbId;
  const EqubDetailScreen({super.key, required this.equbId});

  @override
  State<EqubDetailScreen> createState() => _EqubDetailScreenState();
}

class _EqubDetailScreenState extends State<EqubDetailScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _equb;
  List<dynamic> _draws = [];
  List<Map<String, dynamic>> _participants = [];
  bool _loading = true;
  late TabController _tabController;
  Timer? _syncTimer;
  String? _lastSpinId;
  final GlobalKey _wheelKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 3 Tabs: Details (0), Live Wheel Algorithm (1 - default focus), Draw History (2)
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _load();
    _startLiveSyncTimer();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _startLiveSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _equb != null) {
        _syncLiveData();
      }
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      Map<String, dynamic>? equb;
      try {
        equb = await FirestoreService.getEqubById(widget.equbId);
      } catch (_) {}

      final lvl = (equb?['level'] ?? widget.equbId).toString().replaceAll('equb_', '').toLowerCase();
      try {
        final users = await RoleManagementService.getUsersByLevel(lvl);
        if (mounted) _participants = users;
      } catch (_) {}

      try {
        final d = await ApiService.getEqubDraws(widget.equbId);
        if (mounted) _draws = d;
      } catch (_) {}

      if (equb == null) {
        try {
          equb = await ApiService.getEqub(widget.equbId);
        } catch (_) {}
      }
      equb ??= _fallback(widget.equbId);
      if (mounted) {
        setState(() {
          _equb = equb;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncLiveData() async {
    final lvl = _lvl;
    if (lvl.isEmpty) return;

    try {
      final users = await RoleManagementService.getUsersByLevel(lvl);
      final draws = await RoleManagementService.getDrawHistory(lvl);
      final liveDraw = await RoleManagementService.getLatestLiveDraw(lvl);

      if (!mounted) return;

      setState(() {
        _participants = users;
        _draws = draws;
        if (_equb != null) {
          _equb!['currentParticipants'] = users.length;
        }
      });

      // Handle live spin event from admin
      if (liveDraw != null && liveDraw.isNotEmpty) {
        final spinId = (liveDraw['spinId'] ?? '').toString();
        if (spinId.isNotEmpty && spinId != _lastSpinId) {
          final timestampStr = (liveDraw['timestamp'] ?? '').toString();
          if (timestampStr.isNotEmpty) {
            final dt = DateTime.tryParse(timestampStr);
            if (dt != null && DateTime.now().difference(dt).inMinutes < 5) {
              _lastSpinId = spinId;
              // Auto switch to Wheel tab if not already on it
              if (_tabController.index != 1) {
                _tabController.animateTo(1);
              }
              // Trigger wheel spin to the target winner
              final winnerId = (liveDraw['winnerId'] ?? '').toString();
              final winnerUniqueId = (liveDraw['winnerUniqueId'] ?? '').toString();

              final eligible = users.where((u) {
                final hw = u['hasWon'];
                final st = (u['status'] ?? '').toString().toLowerCase();
                return !(hw == true || hw == 'true' || st == 'selected' || st == 'won');
              }).toList();

              int targetIdx = eligible.indexWhere((u) {
                final id = (u['userId'] ?? u['id'] ?? '').toString();
                final uq = (u['uniqueId'] ?? '').toString();
                return (id.isNotEmpty && id == winnerId) ||
                       (uq.isNotEmpty && uq == winnerUniqueId);
              });

              if (targetIdx < 0) targetIdx = 0;

              // Invoke spin on EqubDrawWheel widget state
              final dynamic wheelState = _wheelKey.currentState;
              if (wheelState != null) {
                try {
                  wheelState.spinToTargetIndex(targetIdx, precalculatedWinner: {
                    'id': winnerId,
                    'fullName': liveDraw['winnerName'] ?? 'Winner',
                    'uniqueId': winnerUniqueId,
                  });
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  // Fallback data when no server/Firestore data available
  Map<String, dynamic> _fallback(String id) {
    final lvl = id.replaceAll('equb_', '').toLowerCase();
    const prices    = {'low': 5000.0,   'medium': 10000.0,  'high': 20000.0};
    const prizes    = {'low': 465000.0, 'medium': 930000.0,  'high': 1800000.0};
    const fees      = {'low': 35000.0,  'medium': 70000.0,   'high': 200000.0};
    const maxP      = {'low': 100,      'medium': 100,        'high': 100};
    return {
      'equbId': id,
      'level': lvl.isEmpty ? 'low' : lvl,
      'name': lvl == 'medium' ? 'Medium Level Equb'
            : lvl == 'high'   ? 'High Level Equb'
                              : 'Low Level Equb',
      'price':               prices[lvl]  ?? 5000.0,
      'netPrize':            prizes[lvl]  ?? 465000.0,
      'adminFee':            fees[lvl]    ?? 35000.0,
      'currentParticipants': 0,
      'maxParticipants':     maxP[lvl]    ?? 100,
      'status': 'active',
      'description': lvl == 'high'
          ? 'Premium Equb for 11k–20k ETB contributors.\nፕሪሚየም እቁብ ለ11,000–20,000 ብር ተሳታፊዎች።'
          : lvl == 'medium'
          ? 'Standard Equb for 6k–10k ETB contributors.\nለ6,000–10,000 ብር ተሳታፊዎች — ሰፊ ድል አበል።'
          : 'Affordable weekly Equb for 1k–5k ETB contributors.\nሳምንታዊ እቁብ ለ1,000–5,000 ብር ተሳታፊዎች።',
      'paymentSchedule': 'Weekly — ሳምንታዊ',
      'drawTime': 'Every Sunday 12:00 PM',
      'riskLevel':      lvl == 'high' ? 'Premium' : lvl == 'medium' ? 'Moderate' : 'Low',
      'targetAudience': lvl == 'high' ? 'VIP Investors'
                      : lvl == 'medium' ? 'Business Owners'
                                       : 'General Public',
    };
  }

  // ── Level colour helpers ──────────────────────────────────────────────────
  String get _lvl   => (_equb?['level'] ?? 'low').toString().toLowerCase();
  Color  get _color => switch (_lvl) { 'medium' => AppColors.medium, 'high' => AppColors.high, _ => AppColors.low };
  Color  get _dark  => switch (_lvl) { 'medium' => const Color(0xFFBF360C), 'high' => const Color(0xFF4A148C), _ => const Color(0xFF0D47A1) };
  String get _img   => 'assets/images/levels/$_lvl.jpg';
  String get _enLabel => switch (_lvl) { 'medium' => 'Medium Level Equb', 'high' => 'High Level Equb', _ => 'Low Level Equb' };
  String get _amLabel => switch (_lvl) { 'medium' => 'መካከለኛ ደረጃ እቁብ', 'high' => 'ከፍተኛ ደረጃ እቁብ', _ => 'ዝቅተኛ ደረጃ እቁብ' };
  String get _emoji   => switch (_lvl) { 'medium' => '⭐', 'high' => '👑', _ => '💰' };

  List<_BPhrase> get _phrases => switch (_lvl) {
    'medium' => const [
      _BPhrase('Medium Level Equb',               'መካከለኛ ደረጃ እቁብ'),
      _BPhrase('6,000 – 10,000 ETB Per Week',     '6,000 – 10,000 ብር ሳምንታዊ ክፍያ'),
      _BPhrase('Net Prize up to 930,000 ETB',     'ድል አበል እስከ 930,000 ብር'),
      _BPhrase('Fair Wheel Draw • Verified',      'ፍትሃዊ ዕጣ • ሁሉም ውሂብ ተጠብቋል'),
    ],
    'high' => const [
      _BPhrase('High Level Equb',                 'ከፍተኛ ደረጃ እቁብ'),
      _BPhrase('11,000 – 20,000 ETB Per Week',    '11,000 – 20,000 ብር ሳምንታዊ'),
      _BPhrase('Net Prize up to 1,800,000 ETB',   'ድል አበል እስከ 1,800,000 ብር'),
      _BPhrase('VIP Pool • Secured • Verified',   'ቪአይፒ • ደህንነቱ ያለ • ተረጋግጧል'),
    ],
    _ => const [
      _BPhrase('Low Level Equb',                  'ዝቅተኛ ደረጃ እቁብ'),
      _BPhrase('1,000 – 5,000 ETB Per Week',      '1,000 – 5,000 ብር ሳምንታዊ ክፍያ'),
      _BPhrase('Net Prize up to 465,000 ETB',     'ድል አበል እስከ 465,000 ብር'),
      _BPhrase('Fair Draw • 1-to-1 Verified',     'ፍትሃዊ ዕጣ • 1-ለ-1 ማረጋገጫ'),
    ],
  };

  // ── Back navigation ───────────────────────────────────────────────────────
  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/equbs');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAmharic = AppConstants.currentLanguage == 'am';

    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _goBack,
          ),
          title: Text(isAmharic ? 'ዝርዝር ጫናዎ…' : 'Loading…'),
        ),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              isAmharic ? 'ዝርዝር በመጫን ላይ…' : 'Loading Equb details…',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ]),
        ),
      );
    }

    if (_equb == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _goBack,
          ),
          title: const Text('Not Found'),
        ),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text('Equb not found', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    final price   = ((_equb!['price']    as num?)?.toDouble()) ?? 0;
    final prize   = ((_equb!['netPrize'] as num?)?.toDouble()) ?? 0;
    final fee     = ((_equb!['adminFee'] as num?)?.toDouble()) ?? 0;
    final current = _participants.length > 0 ? _participants.length : (((_equb!['currentParticipants'] as num?)?.toInt()) ?? 0);
    final max     = ((_equb!['maxParticipants'] as num?)?.toInt()) ?? 100;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: AppBar(backgroundColor: _dark, elevation: 0),
      ),
      body: Column(
        children: [
          // ── Hero banner ──────────────────────────────────────────────────
          _HeroSection(
            vsync: this,
            img: _img,
            color: _color,
            dark: _dark,
            emoji: _emoji,
            levelLabel: isAmharic ? _amLabel : _enLabel,
            phrases: _phrases,
            onBack: _goBack,
          ),

          // ── Tab selector ─────────────────────────────────────────────────
          Material(
            color: Colors.white,
            elevation: 2,
            child: TabBar(
              controller: _tabController,
              labelColor: _color,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: _color,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.info_outline_rounded, size: 15),
                    const SizedBox(width: 4),
                    Text(isAmharic ? 'ዝርዝር' : 'Details'),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.motion_photos_on_rounded, size: 15),
                    const SizedBox(width: 4),
                    Text(isAmharic ? 'ዕጣ መንኮራኩር' : 'Draw Circle'),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.emoji_events_outlined, size: 15),
                    const SizedBox(width: 4),
                    Text(isAmharic ? 'ዕጣ ታሪክ' : 'History'),
                  ]),
                ),
              ],
            ),
          ),

          // ── Tab body ─────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 0 — Details
                _DetailsTab(
                  equb: _equb!,
                  color: _color,
                  current: current,
                  max: max,
                  price: price,
                  prize: prize,
                  fee: fee,
                  isAmharic: isAmharic,
                  level: _lvl,
                  onPay: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PaymentScreen(
                        initialLevel: _lvl,
                        equbId: widget.equbId,
                        amount: price,
                      ),
                    ),
                  ),
                ),
                // Tab 1 — Live Draw Wheel Circle Algorithm
                _LiveWheelTab(
                  key: _wheelKey,
                  participants: _participants,
                  levelName: isAmharic ? _amLabel : _enLabel,
                  color: _color,
                  isAmharic: isAmharic,
                ),
                // Tab 2 — Winner History
                _DrawHistoryTab(
                  draws: _draws,
                  max: max,
                  color: _color,
                  isAmharic: isAmharic,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BPhrase — bilingual text pair
// ─────────────────────────────────────────────────────────────────────────────
class _BPhrase {
  final String en, am;
  const _BPhrase(this.en, this.am);
}

// ─────────────────────────────────────────────────────────────────────────────
// _HeroSection
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSection extends StatefulWidget {
  final TickerProvider vsync;
  final String img, emoji, levelLabel;
  final Color color, dark;
  final List<_BPhrase> phrases;
  final VoidCallback onBack;

  const _HeroSection({
    super.key,
    required this.vsync,
    required this.img,
    required this.emoji,
    required this.levelLabel,
    required this.color,
    required this.dark,
    required this.phrases,
    required this.onBack,
  });

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: widget.vsync,
      duration: const Duration(milliseconds: 550),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
    _schedule();
  }

  void _schedule() {
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      _ctrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _idx = (_idx + 1) % widget.phrases.length);
        _ctrl.forward();
        _schedule();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phrase = widget.phrases[_idx];
    final mainText = phrase.am;
    final subText  = phrase.en;

    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [widget.dark, widget.color, widget.dark],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Positioned(right: -20, top: -20,
            child: Container(width: 110, height: 110,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07)))),
          Positioned(left: -15, bottom: -15,
            child: Container(width: 80, height: 80,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06)))),

          Positioned(
            top: 8,
            left: 4,
            child: SafeArea(
              minimum: const EdgeInsets.only(top: 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onBack,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.38),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 56, 20),
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 4),
                    Text(
                      widget.levelLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mainText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                        letterSpacing: 0.1,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        shadows: const [Shadow(color: Colors.black45, blurRadius: 3)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.phrases.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: i == _idx ? 20 : 6,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _idx
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LiveWheelTab — Frontend Live Wheel Circle Tab
// ─────────────────────────────────────────────────────────────────────────────
class _LiveWheelTab extends StatefulWidget {
  final List<Map<String, dynamic>> participants;
  final String levelName;
  final Color color;
  final bool isAmharic;

  const _LiveWheelTab({
    super.key,
    required this.participants,
    required this.levelName,
    required this.color,
    required this.isAmharic,
  });

  @override
  State<_LiveWheelTab> createState() => _LiveWheelTabState();
}

class _LiveWheelTabState extends State<_LiveWheelTab> {
  final GlobalKey _wheelWidgetKey = GlobalKey();

  void spinToTargetIndex(int idx, {Map<String, dynamic>? precalculatedWinner}) {
    final dynamic st = _wheelWidgetKey.currentState;
    if (st != null) {
      try {
        st.spinToTargetIndex(idx, precalculatedWinner: precalculatedWinner);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAmharic = widget.isAmharic;
    final eligible = widget.participants.where((p) {
      final hw = p['hasWon'];
      final st = (p['status'] ?? 'active').toString().toLowerCase();
      return !(hw == true || hw == 'true' || hw == 1 || st == 'selected' || st == 'won');
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── Live Stream Sync Header Badge ──────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isAmharic
                        ? '🔴 ቀጥታ ዥረት የተያያዘ — አስተዳዳሪ ሲያዞር በራስ-ሰር ይዞራል'
                        : '🔴 LIVE DRAW SYNC — Auto spins when admin triggers draw',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Registered Users Count Chips ────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _chip(
                Icons.people_alt_rounded,
                isAmharic ? 'የተመዘገቡ' : 'Registered',
                '${widget.participants.length}',
                AppColors.primary,
              ),
              _chip(
                Icons.casino_rounded,
                isAmharic ? 'ተወዳዳሪ' : 'Eligible',
                '${eligible.length}',
                Colors.green.shade700,
              ),
              _chip(
                Icons.emoji_events_rounded,
                isAmharic ? 'ያሸነፉ' : 'Winners',
                '${widget.participants.length - eligible.length}',
                Colors.amber.shade800,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Equb Draw Wheel Circle Component ─────────────────────────────
          EqubDrawWheel(
            key: _wheelWidgetKey,
            participants: widget.participants,
            accentColor: widget.color,
            levelName: widget.levelName,
            disabled: true, // Disables manual spin button on user frontend (Admin control only)
            onWinnerSelected: (idx) {
              // Action handled on winner select
            },
          ),

          const SizedBox(height: 24),

          // ── Registered Circle Members List Title ─────────────────────────
          Row(
            children: [
              Container(width: 4, height: 18,
                  decoration: BoxDecoration(color: widget.color,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text(
                isAmharic ? 'በመንኮራኩሩ ላይ ያሉ አባላት' : 'Registered Members on Wheel',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: widget.color,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (widget.participants.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                isAmharic ? 'እስካሁን የተመዘገበ አባል የለም።' : 'No registered participants yet.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.participants.length,
              itemBuilder: (ctx, i) {
                final p = widget.participants[i];
                final name = (p['fullName'] ?? p['firstName'] ?? p['username'] ?? 'Member').toString();
                final uid = (p['uniqueId'] ?? p['userId'] ?? p['id'] ?? '').toString();
                final phone = (p['phoneNumber'] ?? p['phone'] ?? '').toString();
                final hw = p['hasWon'];
                final st = (p['status'] ?? 'active').toString().toLowerCase();
                final hasWon = (hw == true || hw == 'true' || hw == 1 || st == 'selected' || st == 'won');

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasWon ? Colors.amber.shade300 : AppColors.divider,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: hasWon ? Colors.amber.shade100 : widget.color.withOpacity(0.12),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: hasWon ? Colors.amber.shade900 : widget.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        decoration: hasWon ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(
                      'ID: $uid ${phone.isNotEmpty ? "• $phone" : ""}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasWon ? Colors.amber.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasWon ? Colors.amber.shade300 : Colors.green.shade300,
                        ),
                      ),
                      child: Text(
                        hasWon
                            ? (isAmharic ? '🏆 አሸናፊ' : '🏆 Winner')
                            : (isAmharic ? '✅ ተወዳዳሪ' : '✅ Eligible'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: hasWon ? Colors.amber.shade900 : Colors.green.shade800,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, String val, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(val, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: c)),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailsTab
// ─────────────────────────────────────────────────────────────────────────────
class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> equb;
  final Color color;
  final int current, max;
  final double price, prize, fee;
  final bool isAmharic;
  final String level;
  final VoidCallback onPay;

  const _DetailsTab({
    required this.equb,
    required this.color,
    required this.current,
    required this.max,
    required this.price,
    required this.prize,
    required this.fee,
    required this.isAmharic,
    required this.level,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(children: [
            _stat(Icons.payments_rounded,
                isAmharic ? 'ሳምንታዊ ክፍያ' : 'Weekly Entry',
                '${_f(price)} ETB', color),
            const SizedBox(width: 8),
            _stat(Icons.emoji_events_rounded,
                isAmharic ? 'ድል አበል' : 'Net Prize',
                '${_f(prize)} ETB', Colors.amber.shade700),
            const SizedBox(width: 8),
            _stat(Icons.group_rounded,
                isAmharic ? 'ቦታዎች' : 'Slots',
                '$current / $max', AppColors.primary),
          ]),

          const SizedBox(height: 18),

          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(isAmharic ? 'ተሳታፊዎች' : 'Participants',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text('$current / $max',
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: max > 0 ? current / max : 0,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${max - current} ${isAmharic ? "ቦታዎች ይቀራሉ" : "slots remaining"}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),

          const SizedBox(height: 20),
          _sectionTitle(isAmharic ? 'ስለ ደረጃው' : 'About This Level', color),
          const SizedBox(height: 8),
          Text(
            equb['description']?.toString() ?? '',
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary,
                height: 1.65),
          ),

          const SizedBox(height: 20),
          _sectionTitle(isAmharic ? 'ዝርዝር' : 'Specifications', color),
          const SizedBox(height: 10),
          _specRow(Icons.payments_rounded,
              isAmharic ? 'ሳምንታዊ ክፍያ' : 'Weekly Entry',
              '${_f(price)} ETB', color),
          _specRow(Icons.emoji_events_rounded,
              isAmharic ? 'ጠቅ. ድል አበል' : 'Net Prize',
              '${_f(prize)} ETB', Colors.amber.shade700),
          _specRow(Icons.admin_panel_settings_rounded,
              isAmharic ? 'አስ. ክፍያ' : 'Admin Fee',
              '${_f(fee)} ETB (${level == "high" ? "10%" : level == "medium" ? "7%" : "5%"})',
              Colors.grey.shade600),
          _specRow(Icons.calendar_month_rounded,
              isAmharic ? 'ዕጣ ጊዜ' : 'Schedule',
              equb['paymentSchedule']?.toString() ?? 'Weekly', color),
          _specRow(Icons.access_time_rounded,
              isAmharic ? 'ሰዓት' : 'Draw Time',
              equb['drawTime']?.toString() ?? 'Every Sunday', color),
          _specRow(Icons.shield_outlined,
              isAmharic ? 'አደጋ ደረጃ' : 'Risk Level',
              equb['riskLevel']?.toString() ?? 'Low', color),
          _specRow(Icons.people_alt_rounded,
              isAmharic ? 'ዒላማ ቡድን' : 'Target Audience',
              equb['targetAudience']?.toString() ?? 'General Public', color),
          _specRow(Icons.verified_rounded,
              isAmharic ? 'ሁኔታ' : 'Status',
              (equb['status']?.toString() ?? 'active').toUpperCase(),
              equb['status'] == 'active' ? Colors.green.shade700 : Colors.red),

          const SizedBox(height: 20),
          _sectionTitle(isAmharic ? 'እቁቡ እንዴት ይሰራል?' : 'How It Works', color),
          const SizedBox(height: 10),
          _ruleItem('1', Icons.badge_rounded,
              isAmharic ? '1-ለ-1 ብሔራዊ መታወቂያ' : '1-to-1 ID Verification',
              isAmharic
                  ? 'ሁሉም አባሎች በልዩ መታወቂያ ብቻ ይመዘገባሉ። ድርብ ምዝገባ አይፈቀድም።'
                  : 'Each member registers once with a unique ID. Duplicates not allowed.'),
          _ruleItem('2', Icons.payments_rounded,
              isAmharic ? 'ሳምንታዊ ክፍያ' : 'Weekly Contribution',
              isAmharic
                  ? 'ሳምንቱን ክፍያ ይፈጽሙ — ደረሰኝ ለደረጃ አስተዳዳሪ ያቀርቡ።'
                  : 'Pay weekly and upload your bank receipt for admin verification.'),
          _ruleItem('3', Icons.casino_rounded,
              isAmharic ? 'ፍትሃዊ ዕጣ' : 'Automated Wheel Draw',
              isAmharic
                  ? 'አሸናፊ ዕጣ ሥዕሉ (Wheel) ዙር ያወጣዋል — ሁሉም ተሳታፊ እኩል ዕድል አለው።'
                  : 'Winners selected by live wheel spin — every eligible member has equal chance.'),
          _ruleItem('4', Icons.history_rounded,
              isAmharic ? 'አሸናፊ ወደ ፊት አይሳተፍም' : 'Winners Excluded from Future Draws',
              isAmharic
                  ? 'ያሸነፈ ሰው ቀጣዩን ዕጣ አይሳተፍም — ሁሉም ሰው ዕድሉ ይደርሰዋል።'
                  : 'Past winners excluded — ensuring everyone gets a fair turn.'),
          _ruleItem('5', Icons.lock_rounded,
              isAmharic ? 'ሁሉም ሪከርዶች ቋሚ ሆነው ይቀምጣሉ' : 'All Records Stored Permanently',
              isAmharic
                  ? 'ሁሉም ሪከርዶች Google Cloud Firestore ላይ ቋሚ ሆነው ይቀምጣሉ።'
                  : 'All draws, payments and members are permanently stored in Google Cloud Firestore.'),

          const SizedBox(height: 20),
          _sectionTitle(isAmharic ? '🔒 የግልነት ፖሊሲ' : '🔒 Privacy Policy', color),
          const SizedBox(height: 8),
          Text(
            isAmharic
                ? 'የእርስዎ ግል መረጃ (ስም፣ ስልክ፣ ኢሜይል) ከሶስተኛ አካል ጋር አይጋራም። '
                  'ሁሉም ውሂብ Google Cloud Firestore ላይ ቋሚ ሆነው ይቀምጣሉ። '
                  'ለጥያቄዎች: support@onlineequb.et'
                : 'Your personal data (name, phone, email) is never shared with third parties. '
                  'All data is stored securely in Google Cloud Firestore and only the assigned '
                  'Level Admin can access member records. Questions: support@onlineequb.et',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: onPay,
              icon: const Icon(Icons.payments_rounded, color: Colors.white, size: 22),
              label: Text(
                isAmharic
                    ? '💳 ክፍያ ፈጽሙ / ደረሰኝ ያስገቡ'
                    : '💳 Pay Contribution / Submit Receipt',
                style: const TextStyle(
                    color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t, Color c) => Row(children: [
    Container(width: 4, height: 18,
        decoration: BoxDecoration(color: c,
            borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(t, style: TextStyle(fontWeight: FontWeight.bold,
        fontSize: 16, color: c)),
  ]);

  Widget _specRow(IconData icon, String label, String value, Color c) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: Text(label,
            style: const TextStyle(fontSize: 13,
                color: AppColors.textSecondary))),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600))),
      ]),
    );

  Widget _ruleItem(String num, IconData icon, String title, String body) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle),
          child: Center(child: Text(num,
              style: const TextStyle(fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 5),
            Expanded(child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 13))),
          ]),
          const SizedBox(height: 3),
          Text(body, style: const TextStyle(fontSize: 12,
              color: AppColors.textSecondary, height: 1.45)),
        ])),
      ]),
    );

  Widget _stat(IconData icon, String label, String value, Color c) =>
    Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withOpacity(0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900,
              fontSize: 12, color: c)),
          Text(label, style: const TextStyle(fontSize: 10,
              color: AppColors.textSecondary),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// _DrawHistoryTab
// ─────────────────────────────────────────────────────────────────────────────
class _DrawHistoryTab extends StatelessWidget {
  final List<dynamic> draws;
  final int max;
  final Color color;
  final bool isAmharic;
  const _DrawHistoryTab({
    required this.draws,
    required this.max,
    required this.color,
    required this.isAmharic,
  });

  @override
  Widget build(BuildContext context) {
    if (draws.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.casino_outlined, size: 64,
                  color: color.withOpacity(0.35)),
              const SizedBox(height: 16),
              Text(
                isAmharic ? 'እስካሁን ዕጣ አልተካሄደም' : 'No draws held yet',
                style: const TextStyle(
                    fontSize: 16, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                isAmharic
                    ? 'ሳምንታዊ አሸናፊዎች እዚህ ሲቀጥሉ ይታያሉ።'
                    : 'Weekly winners will appear here once draws begin.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            Expanded(child: Text(
              '${draws.length} ${isAmharic ? "ዙሮች" : "rounds complete"}',
              style: TextStyle(fontSize: 12, color: color,
                  fontWeight: FontWeight.w600))),
            Text(
              '${max - draws.length} ${isAmharic ? "ቀሪ" : "remaining"}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max > 0 ? draws.length / max : 0,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 7,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: draws.length,
            itemBuilder: (_, i) {
              final d = draws[i] as Map<String, dynamic>;
              final drawNum = d['drawNumber'] as int? ?? (i + 1);
              final name  = d['winnerName']  as String? ?? '—';
              final phone = d['winnerPhone'] as String? ?? '';
              final prz   = (d['prizeAmount'] as num?)?.toDouble() ?? 0;
              final date  = d['drawDate'] as String? ?? d['createdAt'] as String? ?? '';
              final remaining = max - drawNum;
              final isLatest  = i == 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isLatest
                        ? color.withOpacity(0.5)
                        : AppColors.divider,
                    width: isLatest ? 1.8 : 1,
                  ),
                  boxShadow: isLatest
                      ? [BoxShadow(
                          color: color.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 3))]
                      : null,
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    radius: 22,
                    child: Text('#$drawNum',
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  title: Row(children: [
                    Expanded(child: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14))),
                    if (isLatest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isAmharic ? 'ቅርብ' : 'Latest',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ]),
                  subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (phone.isNotEmpty)
                      Text(phone, style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                    Row(children: [
                      const Icon(Icons.calendar_today,
                          size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(date, style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                      const SizedBox(width: 10),
                      const Icon(Icons.group,
                          size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        remaining >= 0
                            ? '$remaining ${isAmharic ? "ቀሪ" : "left"}'
                            : (isAmharic ? 'ተጠናቅቋል' : 'complete'),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                    ]),
                  ]),
                  trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                    Text('${_f(prz)} ETB',
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    Text(isAmharic ? 'ድል አበል' : 'prize',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary)),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _f(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}
