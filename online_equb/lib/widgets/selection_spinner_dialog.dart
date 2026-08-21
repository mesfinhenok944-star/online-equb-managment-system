import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Shows a modal dialog that visually "spins" through the provided
/// participants and stops at a randomly chosen one. Returns the selected
/// participant map, or null if dialog was dismissed.
Future<Map<String, dynamic>?> showSelectionSpinnerDialog(
  BuildContext context,
  List<Map<String, dynamic>> participants,
  Color color,
) {
  if (participants.isEmpty) return Future.value(null);

  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return _SelectionSpinner(participants: participants, color: color);
    },
  );
}

class _SelectionSpinner extends StatefulWidget {
  final List<Map<String, dynamic>> participants;
  final Color color;

  const _SelectionSpinner({required this.participants, required this.color});

  @override
  State<_SelectionSpinner> createState() => _SelectionSpinnerState();
}

class _SelectionSpinnerState extends State<_SelectionSpinner> {
  int _current = 0;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _startSpin();
  }

  @override
  void dispose() {
    _running = false;
    super.dispose();
  }

  Future<void> _startSpin() async {
    final n = widget.participants.length;
    final rand = Random();
    final target = rand.nextInt(n);
    final rotations = 4 + rand.nextInt(4); // 4..7 full cycles
    final totalSteps = rotations * n + target;

    // Delay from fast to slow (ms)
    const minDelay = 40;
    const maxDelay = 300;

    for (var step = 0; step < totalSteps && _running; step++) {
      final t = step / (totalSteps - 1);
      final eased = t * t; // ease-out-like behavior
      final delayMs = (minDelay + (maxDelay - minDelay) * eased).toInt();

      await Future.delayed(Duration(milliseconds: delayMs));
      if (!mounted) return;
      setState(() {
        _current = (step + 1) % n;
      });
    }

    if (!mounted) return;
    // Ensure final index is the chosen target
    final finalIndex = target % n;
    setState(() => _current = finalIndex);

    // Small pause before closing so user sees the result
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).pop(widget.participants[_current]);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.participants[_current];
    final display =
        (current['fullName'] ?? current['name'] ?? 'Unnamed').toString();

    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Running Draw'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: widget.color,
            child: Text(display.isNotEmpty ? display[0].toUpperCase() : 'U',
                style: const TextStyle(color: Colors.white, fontSize: 28)),
          ),
          const SizedBox(height: 12),
          Text(display, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Selecting a winner...',
              style: TextStyle(color: Colors.black54)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: null, // disable cancel while spinning
            child: const Text('Please wait')),
      ],
    );
  }
}
