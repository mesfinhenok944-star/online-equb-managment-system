import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../services/sound_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EqubDrawWheel
//
// Free-random-selection draw wheel for Ethiopian Equb system.
//
// KEY RULES (per user request):
//   • FREE random selection — cryptographically secure, no weighting.
//   • Winner is excluded from ALL future rounds (hasWon = true).
//   • Works for Low, Medium, High equb levels with 1 – 200+ participants.
//   • Supports 100+ users: large canvas (up to 600px), slot-number mode
//     for >50 users with a scrollable legend panel below the wheel.
//
// VOICE (exact Amharic text):
//   Spinning : "አሸናፊዉን ለመምረጥ እቁቡ እየዞረ ነው አሁን በመዞር ላይ ነው"
//   Winner   : "አሸናፊው [FullName] — [ID]"  (loops until Close tapped)
//
// ROTATION:
//   8–12 full turns → easeOutCubic → pointer lands on winner slice.
//   Tick sound plays at each slice boundary during spin.
// ─────────────────────────────────────────────────────────────────────────────

class EqubDrawWheel extends StatefulWidget {
  final List<Map<String, dynamic>> participants;
  final Future<int?> Function()? onSpinRequested;
  final ValueChanged<int>? onWinnerSelected;
  final bool disabled;
  final Color accentColor;
  final String levelName;

  const EqubDrawWheel({
    super.key,
    required this.participants,
    this.onSpinRequested,
    this.onWinnerSelected,
    this.disabled  = false,
    this.accentColor = const Color(0xFFD4AF37),
    this.levelName = '',
  });

  @override
  State<EqubDrawWheel> createState() => _EqubDrawWheelState();
}

class _EqubDrawWheelState extends State<EqubDrawWheel>
    with SingleTickerProviderStateMixin {

  late AnimationController _rotationController;
  late ConfettiController   _confettiController;
  final Random _rng = Random.secure();

  bool   _spinning = false;
  double _currentAngle  = 0.0;
  double _lastTickAngle = 0.0;
  Map<String, dynamic>? _winner;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _confettiController = ConfettiController(duration: const Duration(seconds: 6));
    SoundService.init();
  }

  @override
  void dispose() {
    SoundService.stop();
    _rotationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  bool _isWinner(Map<String, dynamic> p) {
    final hw = p['hasWon'];
    if (hw == true || hw == 'true' || hw == 1) return true;
    final st = (p['status'] ?? '').toString().toLowerCase();
    if (st == 'selected' || st == 'won' || st == 'winner') return true;
    return false;
  }

  /// Eligible = active and has NOT won before
  List<Map<String, dynamic>> get _eligible => widget.participants
      .where((p) {
        if (_isWinner(p)) return false;
        final st = (p['status'] ?? 'active').toString().toLowerCase();
        return st == 'active';
      })
      .toList();

  static String _pid(Map<String, dynamic> p) =>
      (p['userId'] ?? p['id'] ?? p['participantId'] ?? '').toString();

  /// Wheel diameter scales with participant count so slices remain visible
  double get _wheelDiameter {
    final n = _eligible.length;
    if (n > 150) return 600; // largest — up to 200+ users
    if (n > 100) return 540;
    if (n > 60)  return 480;
    if (n > 30)  return 420;
    return 360;
  }

  // ── SPIN ──────────────────────────────────────────────────────────────────

  // ── SPIN ──────────────────────────────────────────────────────────────────

  /// Public method to spin the wheel externally (for real-time admin sync or direct target)
  Future<void> spinToTargetIndex(int targetVisualIndex, {Map<String, dynamic>? precalculatedWinner}) async {
    final eligible = _eligible;
    if (_spinning || eligible.isEmpty) return;

    // ── Start Amharic/English spinning announcement immediately ──────────
    SoundService.speakSpinningAnnouncement(levelName: widget.levelName);

    setState(() { _spinning = true; _winner = null; });

    int targetVisual = (targetVisualIndex >= 0 && targetVisualIndex < eligible.length)
        ? targetVisualIndex
        : _rng.nextInt(eligible.length);

    final count      = eligible.length;
    final sliceAngle = (2 * pi) / count;
    final sliceCentre  = (targetVisual + 0.5) * sliceAngle;
    final targetAngle  = (3 * pi / 2) - sliceCentre;
    final turns = 18 + _rng.nextInt(8); // 18–26 full rotations for dramatic spin effect
    final norm  = _currentAngle % (2 * pi);
    final delta = (targetAngle - norm + 2 * pi) % (2 * pi);
    final endAngle = _currentAngle + turns * 2 * pi + delta;

    _lastTickAngle = _currentAngle;

    final anim = Tween<double>(begin: _currentAngle, end: endAngle)
        .animate(CurvedAnimation(
          parent: _rotationController,
          curve: Curves.easeOutCubic,
        ));

    void tick() {
      if (!mounted) return;
      if ((anim.value - _lastTickAngle).abs() >= sliceAngle) {
        _lastTickAngle = anim.value;
        SoundService.playTickSound();
      }
      setState(() => _currentAngle = anim.value);
    }

    _rotationController
      ..removeListener(tick)
      ..addListener(tick)
      ..reset();

    await _rotationController.forward();
    _rotationController.removeListener(tick);

    if (!mounted) return;

    final selected = precalculatedWinner ?? eligible[targetVisual];
    setState(() {
      _currentAngle = endAngle % (2 * pi);
      _winner  = selected;
      _spinning = false;
    });

    _confettiController.play();
    SoundService.playTickSound();

    final winnerName = (selected['fullName'] ?? selected['name'] ?? selected['firstName'] ?? 'Winner').toString();
    final winnerUniqueId = (selected['uniqueId'] ?? selected['userId'] ?? selected['id'] ?? '').toString();
    SoundService.speakWinnerAnnouncement(
      fullName: winnerName,
      uniqueId: winnerUniqueId,
      levelName: widget.levelName,
    );

    // ── Notify parent with the eligible list index ───────────────────────
    widget.onWinnerSelected?.call(targetVisual);
  }

  Future<void> _spin() async {
    final eligible = _eligible;
    if (_spinning || widget.disabled || eligible.isEmpty) return;

    // ── Ask parent for winner index inside eligible list ─────────────────
    final targetEligibleIndex = await widget.onSpinRequested?.call();

    // ── Map to visual slot in eligible list ──────────────────────────────
    int targetVisual;
    if (targetEligibleIndex != null &&
        targetEligibleIndex >= 0 &&
        targetEligibleIndex < eligible.length) {
      targetVisual = targetEligibleIndex;
    } else {
      targetVisual = _rng.nextInt(eligible.length);
    }

    await spinToTargetIndex(targetVisual);
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final eligible = _eligible;
    final d = _wheelDiameter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [

        // ── Header banner ───────────────────────────────────────────────
        _buildHeader(),
        const SizedBox(height: 8),

        // ── Wheel + pointer + confetti ──────────────────────────────────
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Confetti
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                numberOfParticles: 60,
                colors: const [
                  Color(0xFF009A44), Color(0xFFFED100),
                  Color(0xFFD7141A), Colors.amber, Colors.white,
                ],
              ),
            ),

            // Wheel canvas
            SizedBox(
              width:  d,
              height: d,
              child: Transform.rotate(
                angle: _currentAngle,
                child: CustomPaint(
                  size: Size(d, d),
                  painter: _WheelPainter(eligible: eligible, diameter: d),
                ),
              ),
            ),

            // Centre spin button (does not rotate)
            GestureDetector(
              onTap: (eligible.isEmpty || widget.disabled || _spinning) ? null : _spin,
              child: _buildCentreButton(),
            ),

            // Top pointer arrow
            Positioned(
              top: 2,
              child: CustomPaint(
                size: const Size(44, 50),
                painter: _PointerPainter(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        _buildGoldBar(),
        const SizedBox(height: 8),

        // ── Winner banner ───────────────────────────────────────────────
        if (_winner != null) _buildWinnerBanner(),

        // ── Stats row ───────────────────────────────────────────────────
        _buildStatsRow(eligible),
        const SizedBox(height: 10),

        // ── Legend (when > 50 users, slices too small for names) ────────
        if (eligible.length > 50) _buildLegend(eligible),
        const SizedBox(height: 10),

        // ── Spin button ─────────────────────────────────────────────────
        _buildSpinButton(eligible),
        const SizedBox(height: 6),

        // Exclusion info
        if (widget.participants.any((p) => p['hasWon'] == true))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '✅ ${widget.participants.where((p) => p['hasWon'] == true).length} '
              'ተሳታፊ(ዎች) አሸንፈዋል — አዲሱ ዙር ${eligible.length} ብቁ ተሳታፊዎችን ያካትታል',
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF009A44),
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [
          Color(0xFF2D1600), Color(0xFF8B6508), Color(0xFF2D1600),
        ]),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x66FFD700), blurRadius: 8)
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _flagBadge(),
        const SizedBox(width: 10),
        Flexible(child: Text(
          widget.levelName.isNotEmpty
              ? 'የኢትዮጵያ እቁብ — ${widget.levelName} ደረጃ ዕጣ'
              : 'የኢትዮጵያ ዲጂታል እቁብ ዕጣ',
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 0.5,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        )),
        const SizedBox(width: 10),
        _flagBadge(),
      ]),
    );
  }

  Widget _flagBadge() => Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
          gradient: const SweepGradient(colors: [
            Color(0xFF009A44), Color(0xFFFED100),
            Color(0xFFD7141A), Color(0xFF009A44),
          ]),
        ),
        child: const Center(child: Icon(Icons.star, color: Colors.blue, size: 11)),
      );

  Widget _buildCentreButton() {
    return Container(
      width: 96, height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFD700), Color(0xFF009A44), Color(0xFF003D1C)],
          stops: [0.15, 0.65, 1.0],
        ),
        border: Border.all(color: const Color(0xFFFFD700), width: 3),
        boxShadow: [
          BoxShadow(color: Colors.amber.withOpacity(0.6), blurRadius: 18, spreadRadius: 2),
          const BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _spinning
            ? const SizedBox(width: 28, height: 28,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : Icon(widget.disabled ? Icons.verified_user_rounded : Icons.autorenew_rounded, color: Colors.white, size: 34),
        const SizedBox(height: 2),
        Text(
          _spinning ? 'ሽክርክር' : (widget.disabled ? 'ዲጂታል እቁብ' : 'እጣ አውጣ'),
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11,
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
      ]),
    );
  }

  Widget _buildWinnerBanner() {
    final p    = _winner!;
    final name = (p['fullName'] ?? p['firstName'] ?? 'Winner').toString().trim();
    final id   = (p['uniqueId'] ?? p['userId'] ?? p['id'] ?? '—').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF003D1C), Color(0xFF009A44)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD700), width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(color: Color(0xFFFFD700), shape: BoxShape.circle),
          child: const Icon(Icons.emoji_events, color: Color(0xFF003D1C), size: 34),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            '🎉 አሸናፊ ተመርጧል!',
            style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
          // "አሸናፊው [FullName]"
          Text(
            'አሸናፊው $name',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // "መታወቂያ ቁጥር [ID]"
          Text(
            'መታወቂያ ቁጥር $id',
            style: const TextStyle(color: Color(0xFFBBDDCC), fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ])),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
          tooltip: 'ዝጋ',
          onPressed: () {
            SoundService.stop();
            setState(() => _winner = null);
          },
        ),
      ]),
    );
  }

  Widget _buildStatsRow(List<Map<String, dynamic>> eligible) {
    final total   = widget.participants.length;
    final winners = widget.participants.where((p) => p['hasWon'] == true).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.accentColor.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _stat('ጠቅላላ\nTotal',     '$total',           widget.accentColor),
        _vDivider(),
        _stat('ብቁ ተሳታፊዎች\nEligible', '${eligible.length}', const Color(0xFF009A44)),
        _vDivider(),
        _stat('አሸናፊዎች\nWinners',  '$winners',          const Color(0xFFD7141A)),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(children: [
    Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
    Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.2)),
  ]);

  Widget _vDivider() => Container(width: 1, height: 40, color: Colors.grey.shade200);

  Widget _buildGoldBar() => Container(
    height: 22, width: 280,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        Colors.amber.shade800.withOpacity(0.0),
        Colors.amber.shade500,
        Colors.amber.shade800.withOpacity(0.0),
      ]),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(12, (i) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        width: 14, height: 14,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFB8860B)]),
        ),
      )),
    ),
  );

  Widget _buildSpinButton(List<Map<String, dynamic>> eligible) {
    if (widget.disabled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: _spinning ? Colors.red.shade900 : const Color(0xFF003D1C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: (_spinning ? Colors.red : Colors.green).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_spinning)
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            else
              const Icon(Icons.lock_rounded, color: Color(0xFFFFD700), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _spinning
                    ? '🔴 ቀጥታ ዕጣ በሥራ ላይ ነው — አስተዳዳሪው እጣ እያወጣ ነው…'
                    : '🔒 ዕጣ የሚወጣው በአስተዳዳሪው ብቻ ነው (${eligible.length} ብቁ ተሳታፊዎች)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final canSpin = eligible.isNotEmpty && !_spinning;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: canSpin ? _spin : null,
        icon: _spinning
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 26),
        label: Text(
          _spinning
              ? 'አሸናፊዉን ለመምረጥ እቁቡ እየዞረ ነው . አሁን በመዞር ላይ ነው…'
              : eligible.isEmpty
                  ? 'ምንም ብቁ ተሳታፊ የለም'
                  : 'እጣ አውጣ  (${eligible.length} ብቁ ተሳታፊዎች)',
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 58),
          backgroundColor: const Color(0xFF009A44),
          disabledBackgroundColor: Colors.grey.shade400,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 5,
        ),
      ),
    );
  }

  // ── Participant legend (51+ users: slices too small for text) ─────────────
  static const List<Color> _legendPalette = [
    Color(0xFF009A44), Color(0xFFFED100), Color(0xFF1E1611), Color(0xFFD7141A),
  ];

  Widget _buildLegend(List<Map<String, dynamic>> eligible) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Icon(Icons.people_alt_rounded, size: 18, color: Color(0xFF009A44)),
          const SizedBox(width: 6),
          Flexible(child: Text(
            'ተሳታፊዎች ዝርዝር  (${eligible.length})',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF009A44)),
          )),
        ]),
      ),
      Container(
        height: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: eligible.length,
          itemBuilder: (_, i) {
            final p    = eligible[i];
            final name = (p['fullName'] ?? p['firstName'] ?? 'User ${i+1}')
                .toString().trim().split(' ').first;
            final id   = (p['uniqueId'] ?? _pid(p)).toString().trim();
            final color = _legendPalette[i % _legendPalette.length];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Text('${i+1}',
                    style: TextStyle(
                      color: color == const Color(0xFFFED100) ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 11,
                    )),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
                Text('#$id',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wheel Painter
// Ethiopian 4-colour palette, supports 1–200+ slices.
// >50 participants → slot number only (font auto-scales with arc length)
// ≤50 participants → name + ID text in each slice
// ─────────────────────────────────────────────────────────────────────────────

class _WheelPainter extends CustomPainter {
  final List<Map<String, dynamic>> eligible;
  final double diameter;

  const _WheelPainter({required this.eligible, required this.diameter});

  static const List<Color> _palette = [
    Color(0xFF009A44), // Green
    Color(0xFFFED100), // Gold
    Color(0xFF1E1611), // Dark
    Color(0xFFD7141A), // Red
  ];

  static String _pid(Map<String, dynamic> p) =>
      (p['userId'] ?? p['id'] ?? p['participantId'] ?? '').toString();

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width / 2;
    final cy     = size.height / 2;
    final center = Offset(cx, cy);
    final outer  = size.width / 2;
    final rim    = outer - 4;
    final wheel  = outer - 20; // actual slice radius

    // ── Golden rim ────────────────────────────────────────────────────────
    canvas.drawCircle(
      center, outer,
      Paint()..shader = const RadialGradient(colors: [
        Color(0xFFFFEA80), Color(0xFFB8860B), Color(0xFFFFD700),
      ]).createShader(Rect.fromCircle(center: center, radius: outer)),
    );
    canvas.drawCircle(
      center, rim,
      Paint()
        ..color = const Color(0xFF0A0700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Rim studs
    for (int s = 0; s < 32; s++) {
      final a = (2 * pi / 32) * s;
      canvas.drawCircle(
        Offset(cx + (outer - 9) * cos(a), cy + (outer - 9) * sin(a)),
        2.8,
        Paint()..color = const Color(0xFF1A1A1A),
      );
    }

    final count      = max(1, eligible.length);
    final sliceAngle = 2 * pi / count;
    final tinyMode   = count > 50; // show slot# only when > 50 participants

    for (int i = 0; i < count; i++) {
      final startAngle = i * sliceAngle;
      final color      = _palette[i % _palette.length];
      final textColor  = color == const Color(0xFFFED100) ? Colors.black : Colors.white;

      // Slice fill
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: wheel),
        startAngle, sliceAngle, true,
        Paint()..color = color..style = PaintingStyle.fill,
      );

      // Divider line (thinner for very many slices)
      final divW = count > 120 ? 0.2 : count > 60 ? 0.5 : count > 30 ? 1.0 : 1.8;
      canvas.drawLine(
        center,
        Offset(cx + wheel * cos(startAngle), cy + wheel * sin(startAngle)),
        Paint()..color = const Color(0xFFFFD700)..strokeWidth = divW,
      );

      // ── Text inside slice ──────────────────────────────────────────────
      canvas.save();
      canvas..translate(cx, cy)..rotate(startAngle + sliceAngle / 2);

      if (tinyMode) {
        // Slot number only — auto-sized so it fits
        final fontSize = min(13.0, max(6.0, wheel * sliceAngle * 0.50));
        _txt(canvas, '${i + 1}',
            TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2)],
            ),
            wheel * 0.62);
      } else {
        // First name + #ID
        final p         = eligible[i];
        final rawFirst  = (p['firstName'] ?? p['fullName'] ?? '').toString().trim();
        final firstName = rawFirst.isNotEmpty ? rawFirst.split(' ').first : 'U${i+1}';
        final rawId     = (p['uniqueId'] ?? _pid(p)).toString().trim();
        final idStr     = rawId.isNotEmpty ? '#$rawId' : '#${i+1}';
        final arcLen    = wheel * sliceAngle;
        final nameSize  = min(12.0, max(6.5, arcLen * 0.22));
        final idSize    = nameSize * 0.82;

        _txt(canvas, firstName,
            TextStyle(
              color: textColor,
              fontSize: nameSize,
              fontWeight: FontWeight.bold,
              shadows: color == const Color(0xFFFED100)
                  ? []
                  : [Shadow(color: Colors.black.withOpacity(0.6), blurRadius: 2)],
            ),
            wheel * 0.68);

        _txt(canvas, idStr,
            TextStyle(
              color: color == const Color(0xFFFED100)
                  ? const Color(0xFF222200)
                  : const Color(0xFFFFD700),
              fontSize: idSize,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2)],
            ),
            wheel * 0.40);
      }

      canvas.restore();
    }

    // Centre ring (border for spin button)
    canvas.drawCircle(
      center, wheel * 0.31,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
  }

  void _txt(Canvas canvas, String text, TextStyle style, double radius) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, Offset(radius - tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.eligible.length != eligible.length ||
      old.diameter != diameter ||
      (eligible.isNotEmpty && old.eligible.isNotEmpty &&
          _pid(old.eligible.first) != _pid(eligible.first));
}

// ─────────────────────────────────────────────────────────────────────────────
// Top pointer arrow
// ─────────────────────────────────────────────────────────────────────────────

class _PointerPainter extends CustomPainter {
  const _PointerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end:   Alignment.bottomCenter,
        colors: [Color(0xFFFF1A1A), Color(0xFF8B0000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(path,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
