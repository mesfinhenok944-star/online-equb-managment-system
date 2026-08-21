import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';

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
  late Animation<double> _spinAnimation;
  late ConfettiController _confettiController;
  final Random _random = Random.secure();

  bool _spinning = false;
  double _currentAngle = 0.0;
  double _lastTickAngle = 0.0;
  Map<String, dynamic>? _selectedParticipant;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 4));
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _eligibleParticipants {
    return widget.participants.where((p) {
      final status = (p['status'] ?? 'active').toString();
      final hasWon = p['hasWon'] == true;
      return !hasWon && status == 'active';
    }).toList();
  }

  Future<void> _startSpin() async {
    final eligible = _eligibleParticipants;
    if (_spinning || widget.disabled || eligible.isEmpty) return;

    setState(() {
      _spinning = true;
      _selectedParticipant = null;
    });

    int? targetFullIndex = await widget.onSpinRequested?.call();

    // Map target to index in eligible list
    int targetVisualIndex = 0;
    if (targetFullIndex != null && targetFullIndex < widget.participants.length) {
      final targetUser = widget.participants[targetFullIndex];
      final targetId = (targetUser['userId'] ?? targetUser['id'] ?? targetUser['participantId']).toString();
      targetVisualIndex = eligible.indexWhere((p) =>
          (p['userId'] ?? p['id'] ?? p['participantId']).toString() == targetId);
      if (targetVisualIndex < 0) targetVisualIndex = 0;
    } else {
      targetVisualIndex = _random.nextInt(eligible.length);
    }

    final count = eligible.length;
    final sliceAngle = 2 * pi / count;

    // Calculate target angle so pointer at top (angle -pi/2) hits the target slice center
    final sliceCenter = (targetVisualIndex + 0.5) * sliceAngle;
    final targetFinalAngleOnWheel = (3 * pi / 2) - sliceCenter;

    // Additional full rotations (6 to 10 full turns for dramatic effect)
    final fullTurns = 6 + _random.nextInt(4);
    final totalRotation = (2 * pi * fullTurns) + (targetFinalAngleOnWheel - (_currentAngle % (2 * pi)));
    final startAngle = _currentAngle;
    final endAngle = _currentAngle + totalRotation;

    _lastTickAngle = startAngle;

    _spinAnimation = Tween<double>(begin: startAngle, end: endAngle).animate(
      CurvedAnimation(
        parent: _rotationController,
        curve: Curves.easeOutCubic,
      ),
    );

    void animListener() {
      if (!mounted) return;
      final angleDelta = (_spinAnimation.value - _lastTickAngle).abs();
      // Tick sound every slice boundary
      if (angleDelta >= sliceAngle) {
        _lastTickAngle = _spinAnimation.value;
        SystemSound.play(SystemSoundType.click);
      }
      setState(() {
        _currentAngle = _spinAnimation.value;
      });
    }

    _rotationController.addListener(animListener);
    _rotationController.reset();

    await _rotationController.forward();

    _rotationController.removeListener(animListener);

    if (!mounted) return;

    final selected = eligible[targetVisualIndex];
    setState(() {
      _currentAngle = endAngle % (2 * pi);
      _selectedParticipant = selected;
      _spinning = false;
    });

    _confettiController.play();
    SystemSound.play(SystemSoundType.click);

    final originalIndex = widget.participants.indexWhere((p) =>
        (p['userId'] ?? p['id'] ?? p['participantId']).toString() ==
        (selected['userId'] ?? selected['id'] ?? selected['participantId']).toString());

    widget.onWinnerSelected?.call(originalIndex >= 0 ? originalIndex : targetFullIndex ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _eligibleParticipants;

    return Column(
      children: [
        // Ethiopian Golden Header Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3E1F00), Color(0xFF8B6508), Color(0xFF3E1F00)],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Colors.amber,
                blurRadius: 10,
                spreadRadius: 1,
              )
            ],
            border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEthiopianFlagBadge(),
              const SizedBox(width: 10),
              Text(
                'በኢትዮጵያ ብቻ',
                style: TextStyle(
                  color: const Color(0xFFFFD700),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.2,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildEthiopianFlagBadge(),
            ],
          ),
        ),

        // Stack with Confetti, Top Arrow, Wheel, Center Button
        Stack(
          alignment: Alignment.center,
          children: [
            // Confetti Overlay
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [
                  Colors.green,
                  Colors.yellow,
                  Colors.red,
                  Colors.amber,
                  Colors.white
                ],
              ),
            ),

            // Golden Wheel Canvas
            SizedBox(
              width: 320,
              height: 320,
              child: Transform.rotate(
                angle: _currentAngle,
                child: CustomPaint(
                  size: const Size(320, 320),
                  painter: _EthiopianBingoWheelPainter(
                    eligible: eligible,
                  ),
                ),
              ),
            ),

            // Center Golden-Green Spin Button
            GestureDetector(
              onTap: (eligible.isEmpty || widget.disabled || _spinning)
                  ? null
                  : _startSpin,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFFFFD700),
                      Color(0xFF009A44),
                      Color(0xFF004D25)
                    ],
                    stops: [0.2, 0.7, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.8),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                    const BoxShadow(
                      color: Colors.black45,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    )
                  ],
                  border: Border.all(color: const Color(0xFFFFD700), width: 3),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _spinning
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                          : const Icon(
                              Icons.autorenew_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                      const SizedBox(height: 2),
                      Text(
                        _spinning ? 'ሽክርክር' : 'እጣ አውጣ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 2)
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top Pointer Arrow (Points down to top edge of wheel)
            Positioned(
              top: 0,
              child: CustomPaint(
                size: const Size(36, 40),
                painter: _TopPointerPainter(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Bottom Golden Coins Deck Graphic
        _buildGoldCoinsFooter(),

        const SizedBox(height: 12),

        // Winner Announcement Card
        if (_selectedParticipant != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF004D25), Color(0xFF009A44)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                )
              ],
              border: Border.all(color: const Color(0xFFFFD700), width: 2),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0xFFFFD700),
                  child: Icon(Icons.emoji_events, color: Color(0xFF004D25), size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🎉 አሸናፊው ተመርጧል!',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedParticipant!['fullName'] ??
                            _selectedParticipant!['firstName'] ??
                            'Selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'ID: ${_selectedParticipant!['uniqueId'] ?? _selectedParticipant!['userId'] ?? '-'} | ${_selectedParticipant!['phoneNumber'] ?? ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Summary Text
        Text(
          eligible.isEmpty
              ? 'ምንም ብቁ ተሳታፊ አልተገኘም (No eligible participants)'
              : '${eligible.length} ብቁ ተሳታፊዎች ተመዝግበዋል',
          style: TextStyle(
            color: Colors.grey.shade800,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 12),

        // Action Spin Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (eligible.isEmpty || widget.disabled || _spinning)
                ? null
                : _startSpin,
            icon: _spinning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.play_circle_fill, color: Colors.white),
            label: Text(
              _spinning
                  ? 'እጣው በመሽከርከር ላይ ነው...'
                  : eligible.isEmpty
                      ? 'ተሳታፊዎች የሉም'
                      : 'እጣ አውጣ (Spin Wheel)',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: const Color(0xFF009A44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEthiopianFlagBadge() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
        gradient: const SweepGradient(
          colors: [Colors.green, Colors.yellow, Colors.red, Colors.green],
        ),
      ),
      child: const Center(
        child: Icon(Icons.star, color: Colors.blue, size: 10),
      ),
    );
  }

  Widget _buildGoldCoinsFooter() {
    return Container(
      height: 24,
      width: 280,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade700.withOpacity(0.0),
            Colors.amber.shade500,
            Colors.amber.shade700.withOpacity(0.0),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          12,
          (index) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
              ),
              border: Border.all(color: Colors.amber.shade100, width: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Wheel Painter for Ethiopian Golden Wheel
// ─────────────────────────────────────────────────────────────────────────────
class _EthiopianBingoWheelPainter extends CustomPainter {
  final List<Map<String, dynamic>> eligible;

  _EthiopianBingoWheelPainter({required this.eligible});

  // Ethiopian motif wheel slice palette
  static const List<Color> _sliceColors = [
    Color(0xFF009A44), // Emerald Green
    Color(0xFFFED100), // Ethiopian Yellow/Gold
    Color(0xFF1F1A17), // Deep Bronze / Dark Saffron
    Color(0xFFD7141A), // Ethiopian Crimson Red
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final wheelRadius = outerRadius - 16;

    // 1. Outer Golden Rim
    final rimPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFD700), Color(0xFF8B6508), Color(0xFFD4AF37)],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, rimPaint);

    // Dark inner groove
    final groovePaint = Paint()
      ..color = const Color(0xFF120C04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, outerRadius - 8, groovePaint);

    // Outer studs/dots on golden rim
    final studPaint = Paint()..color = const Color(0xFF1A1A1A);
    const studCount = 24;
    for (int i = 0; i < studCount; i++) {
      final angle = (2 * pi / studCount) * i;
      final studCenter = Offset(
        center.dx + (outerRadius - 8) * cos(angle),
        center.dy + (outerRadius - 8) * sin(angle),
      );
      canvas.drawCircle(studCenter, 3.5, studPaint);
    }

    final count = max(1, eligible.length);
    final sliceAngle = 2 * pi / count;

    // 2. Draw Pie Slices
    for (int i = 0; i < count; i++) {
      final startAngle = i * sliceAngle;
      final color = _sliceColors[i % _sliceColors.length];

      final slicePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: wheelRadius),
        startAngle,
        sliceAngle,
        true,
        slicePaint,
      );

      // Slice Divider Line
      final dividerPaint = Paint()
        ..color = const Color(0xFFFFD700)
        ..strokeWidth = 1.5;
      final lineEnd = Offset(
        center.dx + wheelRadius * cos(startAngle),
        center.dy + wheelRadius * sin(startAngle),
      );
      canvas.drawLine(center, lineEnd, dividerPaint);

      // 3. Draw Bingo Text inside Slice (First Name & Unique ID)
      if (eligible.isNotEmpty) {
        final participant = eligible[i];
        final rawName = (participant['firstName'] ?? participant['fullName'] ?? '').toString().trim();
        final firstName = rawName.isNotEmpty ? rawName.split(' ').first : 'User ${i + 1}';
        final rawId = (participant['uniqueId'] ?? participant['userId'] ?? '').toString().trim();
        final idStr = rawId.isNotEmpty ? 'ID:#$rawId' : '#${i + 1}';

        canvas.save();
        final textAngle = startAngle + (sliceAngle / 2);
        canvas.translate(center.dx, center.dy);
        canvas.rotate(textAngle);

        final textColor = (color == const Color(0xFFFED100)) ? Colors.black : Colors.white;

        // Line 1: First Name
        final nameSpan = TextSpan(
          text: firstName,
          style: TextStyle(
            color: textColor,
            fontSize: count > 14 ? 8 : (count > 8 ? 10 : 12),
            fontWeight: FontWeight.bold,
            shadows: color == const Color(0xFFFED100)
                ? []
                : [const Shadow(color: Colors.black, blurRadius: 4)],
          ),
        );

        final namePainter = TextPainter(
          text: nameSpan,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();

        // Line 2: Unique ID Badge
        final idSpan = TextSpan(
          text: idStr,
          style: TextStyle(
            color: (color == const Color(0xFFFED100)) ? Colors.black87 : const Color(0xFFFFD700),
            fontSize: count > 14 ? 7 : (count > 8 ? 9 : 10),
            fontWeight: FontWeight.w800,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 2)],
          ),
        );

        final idPainter = TextPainter(
          text: idSpan,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();

        // Radial offset positioning
        final nameRadius = wheelRadius * 0.70;
        final idRadius = wheelRadius * 0.48;

        namePainter.paint(
          canvas,
          Offset(nameRadius - (namePainter.width / 2), -namePainter.height / 2),
        );

        idPainter.paint(
          canvas,
          Offset(idRadius - (idPainter.width / 2), -idPainter.height / 2),
        );

        canvas.restore();
      }
    }

    // Inner Gold Ring
    final innerGoldRing = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, wheelRadius * 0.36, innerGoldRing);
  }

  @override
  bool shouldRepaint(covariant _EthiopianBingoWheelPainter oldDelegate) {
    return oldDelegate.eligible != eligible;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Pointer Arrow Painter
// ─────────────────────────────────────────────────────────────────────────────
class _TopPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(size.width / 2, size.height); // Bottom point pointing to wheel
    path.lineTo(0, 0); // Top left
    path.lineTo(size.width, 0); // Top right
    path.close();

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFD7141A), Color(0xFF8B0000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final borderPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
