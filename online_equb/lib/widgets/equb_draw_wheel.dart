import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../services/sound_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EqubDrawWheel
//
// Supports 1 – 200+ eligible participants.
//
// Rendering strategy:
//   ≤ 50  participants → full firstName + #ID text drawn inside each slice
//   51-150             → slot number only drawn in each slice (bold, large)
//                        + scrollable participant legend below the wheel
//   151+               → same as 51-150; wheel diameter auto-expands to 520px
//                        so slices stay visually distinguishable
//
// Voice:
//   • Spinning: "እቁቡ ለውጥ ነው — Ethiopian Equb draw is spinning!"  (all levels)
//   • Winner : "አሸናፊው <name> — ID <id> ነው!"  repeated 3 times  (all levels)
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
    this.disabled = false,
    this.accentColor = const Color(0xFFD4AF37),
    this.levelName = '',
  });

  @override
  State<EqubDrawWheel> createState() => _EqubDrawWheelState();
}

class _EqubDrawWheelState extends State<EqubDrawWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  late ConfettiController _confettiController;
  final Random _rng = Random.secure();

  bool _spinning = false;
  double _currentAngle = 0.0;
  double _lastTickAngle = 0.0;
  Map<String, dynamic>? _winner;

  // ── lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      // More spins → more dramatic; never shorter than 5s
      duration: const Duration(seconds: 6),
    );
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 6));
    SoundService.init(); // warm up TTS early
  }

  @override
  void dispose() {
    SoundService.stop();
    _rotationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _eligible => widget.participants
      .where((p) =>
          p['hasWon'] != true &&
          (p['status'] ?? 'active').toString() == 'active')
      .toList();

  static String _pid(Map<String, dynamic> p) =>
      (p['userId'] ?? p['id'] ?? p['participantId'] ?? '').toString();

  // Wheel diameter: grows for large participant counts so slices stay visible
  double get _wheelDiameter {
    final n = _eligible.length;
    if (n > 150) return 520;
    if (n > 80) return 460;
    if (n > 40) return 400;
    return 360;
  }

  // ── spin ────────────────────────────────────────────────────────────────

  Future<void> _spin() async {
    final eligible = _eligible;
    if (_spinning || widget.disabled || eligible.isEmpty) return;

    // Start spinning announcement immediately (fire-and-forget)
    SoundService.speakSpinningAnnouncement(levelName: widget.levelName);

    setState(() {
      _spinning = true;
      _winner = null;
    });

    // Ask parent for the winner index (server / local algorithm)
    final targetFullIndex = await widget.onSpinRequested?.call();

    // Map to visual index in eligible list
    int targetVisual;
    if (targetFullIndex != null &&
        targetFullIndex >= 0 &&
        targetFullIndex < widget.participants.length) {
      final tPid = _pid(widget.participants[targetFullIndex]);
      final vi = eligible.indexWhere((p) => _pid(p) == tPid);
      targetVisual = vi >= 0 ? vi : _rng.nextInt(eligible.length);
    } else {
      targetVisual = _rng.nextInt(eligible.length);
    }

    // Compute end angle so pointer (at top = −π/2) lands on target slice centre
    final count = eligible.length;
    final sliceAngle = (2 * pi) / count;
    final sliceCentre = (targetVisual + 0.5) * sliceAngle;
    final targetWheelAngle = (3 * pi / 2) - sliceCentre;
    final turns = 7 + _rng.nextInt(5); // 7–11 full rotations
    final norm = _currentAngle % (2 * pi);
    final delta = (targetWheelAngle - norm + 2 * pi) % (2 * pi);
    final endAngle = _currentAngle + turns * 2 * pi + delta;

    _lastTickAngle = _currentAngle;

    final anim = Tween<double>(begin: _currentAngle, end: endAngle)
        .animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.easeOutCubic,
    ));

    void tick() {
      if (!mounted) return;
      final travelled = (anim.value - _lastTickAngle).abs();
      if (travelled >= sliceAngle) {
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

    final selected = eligible[targetVisual];
    setState(() {
      _currentAngle = endAngle % (2 * pi);
      _winner = selected;
      _spinning = false;
    });

    _confettiController.play();
    SoundService.playTickSound();

    // Sound is handled by _showWinnerDialog in level_dashboard_screen
    // which has the full level label — no duplicate call here.

    final origIdx =
        widget.participants.indexWhere((p) => _pid(p) == _pid(selected));
    widget.onWinnerSelected
        ?.call(origIdx >= 0 ? origIdx : targetFullIndex ?? 0);
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final eligible = _eligible;
    final d = _wheelDiameter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _header(),
        const SizedBox(height: 6),

        // ── Wheel + confetti + pointer ──────────────────────────────────
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
                numberOfParticles: 40,
                colors: const [
                  Color(0xFF009A44), Color(0xFFFED100),
                  Color(0xFFD7141A), Colors.amber, Colors.white,
                ],
              ),
            ),

            // Spinning wheel canvas
            SizedBox(
              width: d,
              height: d,
              child: Transform.rotate(
                angle: _currentAngle,
                child: CustomPaint(
                  size: Size(d, d),
                  painter: _WheelPainter(eligible: eligible, diameter: d),
                ),
              ),
            ),

            // Centre spin button (fixed, does not rotate)
            GestureDetector(
              onTap: (eligible.isEmpty || widget.disabled || _spinning)
                  ? null
                  : _spin,
              child: _centreButton(),
            ),

            // Top arrow pointer
            Positioned(
              top: 2,
              child: CustomPaint(
                size: const Size(40, 46),
                painter: _PointerPainter(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        _goldBar(),
        const SizedBox(height: 8),

        // Winner banner (shown immediately after spin)
        if (_winner != null) _winnerBanner(),

        // Stats row
        _statsRow(eligible),

        const SizedBox(height: 8),

        // Participant legend (shown when 51+ users — slices too small for names)
        if (eligible.length > 50) _participantLegend(eligible),

        const SizedBox(height: 10),

        // Spin button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (eligible.isEmpty || widget.disabled || _spinning)
                ? null
                : _spin,
            icon: _spinning
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 24),
            label: Text(
              _spinning
                  ? 'እጣው በመሽከርከር ላይ ነው…  Spinning…'
                  : eligible.isEmpty
                      ? 'ምንም ብቁ ተሳታፊ የለም — No eligible participants'
                      : 'እጣ አውጣ — Spin the Wheel  (${eligible.length})',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: const Color(0xFF009A44),
              disabledBackgroundColor: Colors.grey.shade400,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 5,
            ),
          ),
        ),
      ],
    );
  }

  // ── sub-widgets ──────────────────────────────────────────────────────────

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [
          Color(0xFF2D1600),
          Color(0xFF8B6508),
          Color(0xFF2D1600),
        ]),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0xFFFFD700), blurRadius: 8, spreadRadius: 0)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _flagBadge(),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.levelName.isNotEmpty
                  ? 'Ethiopian Equb Draw — ${widget.levelName}'
                  : 'በኢትዮጵያ ብቻ — Ethiopian Equb Draw',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.6,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4)
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _flagBadge(),
        ],
      ),
    );
  }

  Widget _flagBadge() => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
          gradient: const SweepGradient(
              colors: [Color(0xFF009A44), Color(0xFFFED100), Color(0xFFD7141A), Color(0xFF009A44)]),
        ),
        child: const Center(child: Icon(Icons.star, color: Colors.blue, size: 11)),
      );

  Widget _centreButton() {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFD700), Color(0xFF009A44), Color(0xFF003D1C)],
          stops: [0.15, 0.65, 1.0],
        ),
        border: Border.all(color: const Color(0xFFFFD700), width: 3),
        boxShadow: [
          BoxShadow(
              color: Colors.amber.withOpacity(0.7),
              blurRadius: 16,
              spreadRadius: 2),
          const BoxShadow(
              color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _spinning
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.autorenew_rounded,
                  color: Colors.white, size: 32),
          const SizedBox(height: 2),
          Text(
            _spinning ? 'ሽክርክር' : 'እጣ አውጣ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _winnerBanner() {
    final p = _winner!;
    final name =
        (p['fullName'] ?? p['firstName'] ?? 'Winner').toString().trim();
    final id = (p['uniqueId'] ?? p['userId'] ?? p['id'] ?? '—').toString();
    final phone = (p['phoneNumber'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF003D1C), Color(0xFF009A44)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD700), width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
                color: Color(0xFFFFD700), shape: BoxShape.circle),
            child: const Icon(Icons.emoji_events,
                color: Color(0xFF003D1C), size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎉 አሸናፊው ተመርጧል!  Winner Selected!',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20)),
                const SizedBox(height: 2),
                Text(
                  'ID: $id${phone.isNotEmpty ? '   📞 $phone' : ''}',
                  style: const TextStyle(
                      color: Color(0xFFBBDDCC), fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: Colors.white70, size: 22),
            tooltip: 'ዝጋ',
            onPressed: () {
              SoundService.stop();
              setState(() => _winner = null);
            },
          ),
        ],
      ),
    );
  }

  Widget _statsRow(List<Map<String, dynamic>> eligible) {
    final total = widget.participants.length;
    final won = widget.participants.where((p) => p['hasWon'] == true).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.accentColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('ጠቅላላ\nTotal', '$total', widget.accentColor),
          _divider(),
          _stat('ብቁ\nEligible', '${eligible.length}', const Color(0xFF009A44)),
          _divider(),
          _stat('አሸናፊዎች\nWinners', '$won', const Color(0xFFD7141A)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  height: 1.2)),
        ],
      );

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: Colors.grey.shade200,
      );

  Widget _goldBar() => Container(
        height: 20,
        width: 260,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Colors.amber.shade800.withOpacity(0.0),
            Colors.amber.shade500,
            Colors.amber.shade800.withOpacity(0.0),
          ]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
              10,
              (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFB8860B)]),
                    ),
                  )),
        ),
      );

  /// Scrollable list of participants shown when 51+ users (slices too small)
  // Palette is duplicated here so the legend can use it without an instance
  static const List<Color> _legendPalette = [
    Color(0xFF009A44),
    Color(0xFFFED100),
    Color(0xFF1E1611),
    Color(0xFFD7141A),
  ];

  /// Scrollable list of participants shown when 51+ users (slices too small)
  Widget _participantLegend(List<Map<String, dynamic>> eligible) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            const Icon(Icons.people_alt_rounded,
                size: 18, color: Color(0xFF009A44)),
            const SizedBox(width: 6),
            Text(
              'ተሳታፊዎች ዝርዝር — Participants List  (${eligible.length})',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF009A44)),
            ),
          ]),
        ),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: eligible.length,
            itemBuilder: (_, i) {
              final p = eligible[i];
              final name =
                  (p['firstName'] ?? p['fullName'] ?? 'User ${i + 1}')
                      .toString()
                      .trim()
                      .split(' ')
                      .first;
              final id = (p['uniqueId'] ?? _pid(p)).toString().trim();
              final sliceColors = _legendPalette;
              final color = sliceColors[i % sliceColors.length];
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: color == const Color(0xFFFED100)
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '#$id',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wheel Painter
// ─────────────────────────────────────────────────────────────────────────────
class _WheelPainter extends CustomPainter {
  final List<Map<String, dynamic>> eligible;
  final double diameter;

  const _WheelPainter({required this.eligible, required this.diameter});

  // Ethiopian palette — 4-colour cycle
  static const List<Color> _palette = [
    Color(0xFF009A44), // Green
    Color(0xFFFED100), // Gold/Yellow
    Color(0xFF1E1611), // Dark
    Color(0xFFD7141A), // Red
  ];

  static String _pid(Map<String, dynamic> p) =>
      (p['userId'] ?? p['id'] ?? p['participantId'] ?? '').toString();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final outer = size.width / 2;
    final rim = outer - 4;       // inner edge of the golden rim
    final wheel = outer - 18;    // actual slice radius

    // ── Golden rim ────────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      outer,
      Paint()
        ..shader = const RadialGradient(colors: [
          Color(0xFFFFEA80),
          Color(0xFFB8860B),
          Color(0xFFFFD700),
        ]).createShader(Rect.fromCircle(center: center, radius: outer)),
    );

    // Rim dark groove
    canvas.drawCircle(
      center,
      rim,
      Paint()
        ..color = const Color(0xFF0A0700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Rim studs
    final studPaint = Paint()..color = const Color(0xFF1A1A1A);
    for (int s = 0; s < 28; s++) {
      final a = (2 * pi / 28) * s;
      canvas.drawCircle(
        Offset(cx + (outer - 9) * cos(a), cy + (outer - 9) * sin(a)),
        3.0,
        studPaint,
      );
    }

    final count = max(1, eligible.length);
    final sliceAngle = 2 * pi / count;

    // Decide text rendering mode
    // tiny = > 50 participants — just show slot number
    final bool tinyMode = count > 50;

    for (int i = 0; i < count; i++) {
      final startAngle = i * sliceAngle;
      final color = _palette[i % _palette.length];
      final textColor =
          color == const Color(0xFFFED100) ? Colors.black : Colors.white;

      // Slice
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: wheel),
        startAngle,
        sliceAngle,
        true,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );

      // Gold divider line
      final divW = count > 100
          ? 0.3
          : count > 60
              ? 0.6
              : count > 30
                  ? 1.0
                  : 1.8;
      canvas.drawLine(
        center,
        Offset(cx + wheel * cos(startAngle), cy + wheel * sin(startAngle)),
        Paint()
          ..color = const Color(0xFFFFD700)
          ..strokeWidth = divW,
      );

      // ── Text inside slice ──────────────────────────────────────────────
      canvas.save();
      canvas
        ..translate(cx, cy)
        ..rotate(startAngle + sliceAngle / 2);

      if (tinyMode) {
        // Show slot number only (bold, scaled to slice size)
        final slotSize = min(14.0, max(7.0, wheel * sliceAngle * 0.55));
        _paintText(
          canvas,
          '${i + 1}',
          TextStyle(
            color: textColor,
            fontSize: slotSize,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                  color: Colors.black.withOpacity(0.5), blurRadius: 2)
            ],
          ),
          wheel * 0.62,
        );
      } else {
        // Full name + ID
        final p = eligible[i];
        final rawFirst =
            (p['firstName'] ?? p['fullName'] ?? '').toString().trim();
        final firstName =
            rawFirst.isNotEmpty ? rawFirst.split(' ').first : 'U${i + 1}';
        final rawId =
            (p['uniqueId'] ?? _pid(p)).toString().trim();
        final idStr = rawId.isNotEmpty ? '#$rawId' : '#${i + 1}';

        // Font size: scale with available arc length
        final arcLen = wheel * sliceAngle;
        final nameSize = min(12.0, max(6.5, arcLen * 0.22));
        final idSize = nameSize * 0.85;

        _paintText(
          canvas,
          firstName,
          TextStyle(
            color: textColor,
            fontSize: nameSize,
            fontWeight: FontWeight.bold,
            shadows: color == const Color(0xFFFED100)
                ? []
                : [
                    Shadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 2)
                  ],
          ),
          wheel * 0.68,
        );

        _paintText(
          canvas,
          idStr,
          TextStyle(
            color: color == const Color(0xFFFED100)
                ? const Color(0xFF222200)
                : const Color(0xFFFFD700),
            fontSize: idSize,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(
                  color: Colors.black.withOpacity(0.5), blurRadius: 2)
            ],
          ),
          wheel * 0.40,
        );
      }

      canvas.restore();
    }

    // Inner gold ring (border around centre button)
    canvas.drawCircle(
      center,
      wheel * 0.32,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
  }

  void _paintText(
      Canvas canvas, String text, TextStyle style, double radius) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(
        canvas, Offset(radius - tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.eligible.length != eligible.length ||
      old.diameter != diameter ||
      (eligible.isNotEmpty &&
          old.eligible.isNotEmpty &&
          _pid(old.eligible.first) != _pid(eligible.first));
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Pointer Arrow
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

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF1A1A), Color(0xFF8B0000)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
