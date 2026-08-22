import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/sound_service.dart';

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
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _startSpin();
  }

  @override
  void dispose() {
    _running = false;
    SoundService.stop();
    super.dispose();
  }

  Future<void> _startSpin() async {
    final n = widget.participants.length;
    final rand = Random();
    final target = rand.nextInt(n);
    final rotations = 4 + rand.nextInt(4); // 4..7 full cycles
    final totalSteps = rotations * n + target;

    // Speak spinning audio in Amharic
    SoundService.speakSpinningAnnouncement();

    // Delay from fast to slow (ms)
    const minDelay = 40;
    const maxDelay = 300;

    for (var step = 0; step < totalSteps && _running; step++) {
      final t = step / (totalSteps - 1);
      final eased = t * t; // ease-out-like behavior
      final delayMs = (minDelay + (maxDelay - minDelay) * eased).toInt();

      await Future.delayed(Duration(milliseconds: delayMs));
      if (!mounted) return;
      SoundService.playClickSound();
      setState(() {
        _current = (step + 1) % n;
      });
    }

    if (!mounted) return;
    // Ensure final index is the chosen target
    final finalIndex = target % n;
    setState(() {
      _current = finalIndex;
      _finished = true;
    });

    final winner = widget.participants[_current];
    final winnerName = (winner['fullName'] ?? winner['name'] ?? winner['firstName'] ?? '').toString();
    final winnerId = (winner['uniqueId'] ?? winner['userId'] ?? winner['id'] ?? '').toString();

    // Announce winner 3 times in Amharic
    SoundService.speakWinnerRepeatedThreeTimes(fullName: winnerName, uniqueId: winnerId);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.participants[_current];
    final display =
        (current['fullName'] ?? current['name'] ?? 'Unnamed').toString();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.white,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _finished ? '🎉 አሸናፊ (Winner)' : 'እጣ በመውጣት ላይ (Spinning...)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.grey),
            onPressed: () {
              SoundService.stop();
              Navigator.of(context).pop(_finished ? widget.participants[_current] : null);
            },
            tooltip: 'ዝጋ (Close)',
          ),
        ],
      ),
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
          Text(display, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            'ID: ${current['uniqueId'] ?? current['userId'] ?? '-'}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            _finished ? 'አሸናፊው ተመርጧል!' : 'አሸናፊ በመምረጥ ላይ ነው...',
            style: TextStyle(
              color: _finished ? Colors.green : Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _finished
                ? () {
                    SoundService.stop();
                    Navigator.of(context).pop(widget.participants[_current]);
                  }
                : null,
            style: ElevatedButton.styleFrom(backgroundColor: widget.color),
            child: Text(_finished ? 'ዝጋ (Close)' : 'እባክዎን ይቆዩ (Please wait)'),
          ),
        ),
      ],
    );
  }
}
