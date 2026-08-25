import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SoundService  —  Smart bilingual TTS for the Ethiopian Equb wheel algorithm.
//
// SPINNING (all levels, plays once):
//   "እቁቡ እየዞረ ነው — አሸናፊ እየተፈለገ ነው…"
//   [gap]
//   "The equb wheel is spinning — choosing the winner…"
//   [gap]
//   "ሁሉም ዝግጁ ይሁኑ!"
//   [gap]
//   "Get ready everyone!"
//
// WINNER (loops until Close button tapped):
//   "🎉 አሸናፊ ተመርጧል!"
//   [gap]
//   "አሸናፊው [FullName] ነው"
//   [gap]
//   "መታወቂያ ቁጥር [ID]"
//   [long gap]
//   "Congratulations! The winner has been selected!"
//   [gap]
//   "The winner is [FullName]"
//   [gap]
//   "Unique ID [ID]"
//   [long gap]
//   ↺ repeats until stop() is called (Close button)
//
// Platforms:
//   Android/iOS → flutter_tts  (am-ET preferred, en-US fallback)
//   Linux       → Google TTS via Python3 + pw-play / spd-say fallback
//   Web         → flutter_tts  (en-US)
// ─────────────────────────────────────────────────────────────────────────────
class SoundService {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready   = false;
  static bool _inited  = false;
  static bool _looping = false;   // true while winner announcement loops
  static Timer? _loopTimer;

  // ── Initialise ────────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    if (!kIsWeb && Platform.isLinux) {
      _ready = false;
      return;
    }

    try {
      // Try Amharic first; fall back to English
      for (final lang in ['am-ET', 'am', 'en-US']) {
        final ok = await _tts.isLanguageAvailable(lang);
        if (ok == true) {
          await _tts.setLanguage(lang);
          break;
        }
      }
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.1);
      await _tts.setSpeechRate(0.40);
      _ready = true;
      _tts.setCompletionHandler(() {});
    } catch (e) {
      debugPrint('[SoundService] init: $e');
    }
  }

  // ── Tick click (wheel slice boundary) ─────────────────────────────────────
  static void playTickSound() {
    try { SystemSound.play(SystemSoundType.click); } catch (_) {}
  }

  // ── Spinning announcement (all levels, plays once, fire-and-forget) ───────
  /// Same 4 phrases for every equb level.
  static Future<void> speakSpinningAnnouncement({String levelName = ''}) async {
    // levelName is accepted but not spoken — universal phrases for all levels
    final script = [
      'እቁቡ እየዞረ ነው . አሸናፊ እየተፈለገ ነው',
      'The equb wheel is spinning . choosing the winner',
      'ሁሉም ዝግጁ ይሁኑ',
      'Get ready everyone',
    ].join(' , , ');   // double-comma = natural TTS pause between phrases

    await _speak(script, rate: 0.42);
  }

  // ── Winner announcement (loops until stop() is called) ───────────────────
  /// Announces Amharic first, gap, then English.
  /// Loops continuously until [stop()] is called via the Close button.
  static Future<void> speakWinnerAnnouncement({
    required String fullName,
    required String uniqueId,
    String levelName = '',
  }) async {
    // Use winner data as-is — spoken exactly as stored in Firestore
    final name = fullName.trim().isEmpty ? 'አሸናፊ' : fullName.trim();
    final id   = uniqueId.trim().isEmpty ? '—'    : uniqueId.trim();

    // ── Amharic block ──────────────────────────────────────────────────────
    final amBlock = [
      'አሸናፊ ተመርጧል',
      'አሸናፊው $name ነው',
      'መታወቂያ ቁጥር $id',
    ].join(' , ');

    // ── English block ──────────────────────────────────────────────────────
    final enBlock = [
      'Congratulations . The winner has been selected',
      'The winner is $name',
      'Unique ID $id',
    ].join(' , ');

    // One full round: Amharic → long gap → English → very long gap
    final oneRound = '$amBlock . . . . $enBlock . . . . . .';

    // Stop any previous audio first, then start looping
    await stop();
    _looping = true;

    // 3 rounds immediately (≈ 60 s coverage), then loop via timer / completion handler
    final threeRounds = '$oneRound $oneRound $oneRound';

    if (!kIsWeb && Platform.isLinux) {
      _speakLinux(threeRounds, slow: true);
      _loopTimer = Timer.periodic(const Duration(seconds: 55), (_) {
        if (_looping) _speakLinux(threeRounds, slow: true);
      });
    } else {
      if (!_inited) await init();
      if (_ready) {
        await _tts.stop();
        await _tts.setVolume(1.0);
        await _tts.setPitch(1.15);
        await _tts.setSpeechRate(0.34);

        // When each 3-round chunk finishes, start the next one if still looping
        _tts.setCompletionHandler(() {
          if (_looping && _ready) {
            _tts.speak(threeRounds);
          }
        });

        await _tts.speak(threeRounds);
      }
    }
  }

  // ── Stop all audio and cancel the loop ────────────────────────────────────
  static Future<void> stop() async {
    _looping = false;
    _loopTimer?.cancel();
    _loopTimer = null;

    if (!kIsWeb && Platform.isLinux) {
      try { await Process.run('pkill', ['-f', 'pw-play']);    } catch (_) {}
      try { await Process.run('pkill', ['-f', 'equb_voice']); } catch (_) {}
      try { await Process.run('spd-say', ['-S']);             } catch (_) {}
    }

    try {
      if (_ready) {
        _tts.setCompletionHandler(() {}); // clear chaining handler
        await _tts.stop();
      }
    } catch (_) {}
  }

  // ── Amharic level name helper ─────────────────────────────────────────────
  static String _amLevel(String levelName) {
    final l = levelName.toLowerCase();
    if (l.contains('high')   || l.contains('ከፍ')) return 'ከፍተኛ ደረጃ';
    if (l.contains('medium') || l.contains('መካ')) return 'መካከለኛ ደረጃ';
    if (l.contains('low')    || l.contains('ዝቅ')) return 'ዝቅተኛ ደረጃ';
    return 'እቁብ';
  }

  // ── Internal speak helper ─────────────────────────────────────────────────
  static Future<void> _speak(String text, {double rate = 0.40}) async {
    if (!kIsWeb && Platform.isLinux) {
      _speakLinux(text);
      return;
    }
    try {
      if (!_inited) await init();
      if (!_ready) return;
      await _tts.stop();
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(rate);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[SoundService] _speak: $e');
    }
  }

  // ── Linux TTS: Google TTS → pw-play → spd-say fallback ───────────────────
  static void _speakLinux(String text, {bool slow = false}) {
    final safe = text
        .replaceAll('\\', '\\\\')
        .replaceAll('"',  '\\"')
        .replaceAll("'",  "\\'")
        .replaceAll('\n', ' ');
    final speed = slow ? '0.55' : '0.75';

    final pyScript = '''
import urllib.request, urllib.parse, subprocess

text = """$safe"""
speed = "$speed"
tmp = '/tmp/equb_voice_announce.mp3'
try:
    url = ('https://translate.google.com/translate_tts'
           '?ie=UTF-8'
           '&q=' + urllib.parse.quote(text[:200]) +
           '&tl=am&client=tw-ob&ttsspeed=' + speed)
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=10) as r, open(tmp, 'wb') as f:
        f.write(r.read())
    subprocess.run(['pw-play', tmp], timeout=90)
except Exception:
    try:
        rate = '-25' if speed == '0.55' else '-10'
        subprocess.run(['spd-say', '-r', rate, '-w', text[:500]], timeout=90)
    except Exception:
        pass
''';

    try {
      Process.run('python3', ['-c', pyScript]);
    } catch (e) {
      debugPrint('[SoundService] Linux TTS: $e');
    }
  }
}
