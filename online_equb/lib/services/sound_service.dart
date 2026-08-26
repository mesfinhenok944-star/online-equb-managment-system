import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SoundService  —  Smart bilingual Amharic+English TTS for Equb wheel.
//
// SPINNING  (plays once when wheel starts rotating):
//   "[Level] እጣ ዕጣ ሽክርክሩ ጀምሯል!"
//   "እቁቡ እየዞረ ነው . . . አሸናፊ እየተፈለገ ነው"
//   "ሁሉም ዝግጁ ይሁኑ!"
//   ──── gap ────
//   "[Level] equb draw wheel is now spinning!"
//   "The equb is rotating . . . choosing the winner"
//   "Get ready everyone!"
//
// WINNER  (loops continuously until Close button tapped):
//   ── Round (Amharic) ──────────────────────────────────────────────────────
//   "🎉 [Level] እጣ አሸናፊ ተመርጧል!"
//   "አሸናፊው [FullName] ነው"
//   "የተሳታፊ መታወቂያ ቁጥር [UniqueID]"
//   "እንኳን ደስ አለዎ [FullName]!"
//   ──── long gap ────
//   ── Round (English) ──────────────────────────────────────────────────────
//   "Congratulations! [Level] equb winner has been selected!"
//   "The winner is [FullName]"
//   "Participant ID [UniqueID]"
//   "Well done [FullName]!"
//   ──── very long gap → repeats from top ────
//
// Platforms:
//   Android / iOS → flutter_tts  (am-ET preferred, en-US fallback)
//   Linux desktop → Google TTS REST → pw-play, spd-say fallback
//   Web           → flutter_tts  (en-US)
// ─────────────────────────────────────────────────────────────────────────────

class SoundService {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready    = false;
  static bool _inited   = false;
  static bool _looping  = false;
  static Timer? _loopTimer;
  static String? _loopScript; // kept so restart after completion works

  // ── Amharic level name ────────────────────────────────────────────────────
  static String _amLevel(String levelName) {
    final l = levelName.toLowerCase();
    if (l.contains('high')   || l.contains('ከፍ'))  return 'ከፍተኛ ደረጃ';
    if (l.contains('medium') || l.contains('መካ'))  return 'መካከለኛ ደረጃ';
    if (l.contains('low')    || l.contains('ዝቅ'))  return 'ዝቅተኛ ደረጃ';
    return 'እቁብ ደረጃ';
  }

  // ── English level name ────────────────────────────────────────────────────
  static String _enLevel(String levelName) {
    final l = levelName.toLowerCase();
    if (l.contains('high'))   return 'High Level';
    if (l.contains('medium')) return 'Medium Level';
    if (l.contains('low'))    return 'Low Level';
    return 'Equb';
  }

  // ── Initialise TTS engine ─────────────────────────────────────────────────
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    if (!kIsWeb && Platform.isLinux) {
      _ready = false; // Linux uses Python script
      return;
    }

    try {
      // Prefer Amharic; fall back to English
      bool langSet = false;
      for (final lang in ['am-ET', 'am', 'en-US', 'en']) {
        try {
          final ok = await _tts.isLanguageAvailable(lang);
          if (ok == true) {
            await _tts.setLanguage(lang);
            langSet = true;
            debugPrint('[SoundService] TTS language: $lang');
            break;
          }
        } catch (_) {}
      }
      if (!langSet) await _tts.setLanguage('en-US');

      await _tts.setVolume(1.0);
      await _tts.setPitch(1.05);
      await _tts.setSpeechRate(0.38);
      _ready = true;
      _tts.setCompletionHandler(() {});
    } catch (e) {
      debugPrint('[SoundService] init error: $e');
    }
  }

  // ── Tick sound (wheel slice boundary) ─────────────────────────────────────
  static void playTickSound() {
    try { SystemSound.play(SystemSoundType.click); } catch (_) {}
  }

  // ── SPINNING announcement (once, fire-and-forget) ─────────────────────────
  // Plays immediately when the wheel starts rotating.
  // Includes the level name so the audience knows which level is drawing.
  static Future<void> speakSpinningAnnouncement({String levelName = ''}) async {
    final am = _amLevel(levelName);
    final en = _enLevel(levelName);

    // Amharic phrases , gap , English phrases
    final script = [
      // ── Amharic ──────────────────────────────────────────────────
      '$am . እጣ ሽክርክሩ ጀምሯል',
      'እቁቡ እየዞረ ነው . . . አሸናፊ እየተፈለገ ነው',
      'ሁሉም ዝግጁ ይሁኑ',
      // ── gap ───────────────────────────────────────────────────────
      '. . .',
      // ── English ──────────────────────────────────────────────────
      '$en equb draw wheel is now spinning',
      'The equb is rotating . . . choosing the winner now',
      'Get ready everyone',
    ].join(' , ');

    await _speak(script, rate: 0.42);
  }

  // ── WINNER announcement (loops until stop()) ───────────────────────────────
  // Speaks the actual winner's full name and unique ID loudly in both
  // Amharic and English.  Repeats continuously until the admin taps Close.
  static Future<void> speakWinnerAnnouncement({
    required String fullName,
    required String uniqueId,
    String levelName = '',
  }) async {
    final name = fullName.trim().isEmpty ? 'አሸናፊ'   : fullName.trim();
    final id   = uniqueId.trim().isEmpty ? 'ያልታወቀ' : uniqueId.trim();
    final am   = _amLevel(levelName);
    final en   = _enLevel(levelName);

    // ── Amharic announcement block ─────────────────────────────────
    final amBlock = [
      '$am እጣ አሸናፊ ተመርጧል',
      'አሸናፊው $name ነው',
      'የተሳታፊ መታወቂያ ቁጥር $id',
      'እንኳን ደስ አለዎ $name',
    ].join(' , ');

    // ── English announcement block ─────────────────────────────────
    final enBlock = [
      'Congratulations . $en equb winner has been selected',
      'The winner is $name',
      'Participant ID $id',
      'Well done $name',
    ].join(' , ');

    // One complete round: Amharic → long pause → English → very long pause
    final oneRound = '$amBlock . . . . . $enBlock . . . . . . . .';

    // Store for completion-handler chaining
    _loopScript = oneRound;

    // Stop previous audio cleanly
    await stop();
    _looping = true;

    if (!kIsWeb && Platform.isLinux) {
      // Linux: Python TTS, periodic timer for looping
      _speakLinux(oneRound, slow: true);
      _loopTimer = Timer.periodic(const Duration(seconds: 50), (_) {
        if (_looping) _speakLinux(oneRound, slow: true);
      });
    } else {
      if (!_inited) await init();
      if (_ready) {
        await _tts.stop();
        await _tts.setVolume(1.0);
        await _tts.setPitch(1.1);
        await _tts.setSpeechRate(0.33); // slightly slower = more dramatic

        // Chain: when one round finishes start the next if still looping
        _tts.setCompletionHandler(() {
          if (_looping && _ready && _loopScript != null) {
            _tts.speak(_loopScript!);
          }
        });

        await _tts.speak(oneRound);
      }
    }
  }

  // ── Stop all audio and cancel loop ────────────────────────────────────────
  static Future<void> stop() async {
    _looping    = false;
    _loopScript = null;
    _loopTimer?.cancel();
    _loopTimer = null;

    if (!kIsWeb && Platform.isLinux) {
      try { await Process.run('pkill', ['-f', 'pw-play']);    } catch (_) {}
      try { await Process.run('pkill', ['-f', 'equb_voice']); } catch (_) {}
      try { await Process.run('spd-say', ['-S']);             } catch (_) {}
    }

    try {
      if (_ready) {
        _tts.setCompletionHandler(() {}); // detach loop
        await _tts.stop();
      }
    } catch (_) {}
  }

  // ── Internal speak (mobile / web) ─────────────────────────────────────────
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

  // ── Linux TTS: Google TTS REST → pw-play → spd-say ───────────────────────
  static void _speakLinux(String text, {bool slow = false}) {
    final safe = text
        .replaceAll('\\', '\\\\')
        .replaceAll('"',  '\\"')
        .replaceAll("'",  "\\'")
        .replaceAll('\n', ' ');
    final speed = slow ? '0.55' : '0.75';

    final py = '''
import urllib.request, urllib.parse, subprocess

text = """$safe"""
tmp  = '/tmp/equb_voice.mp3'
try:
    url = ('https://translate.google.com/translate_tts'
           '?ie=UTF-8&tl=am&client=tw-ob'
           '&ttsspeed=$speed'
           '&q=' + urllib.parse.quote(text[:200]))
    req = urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=10) as r, open(tmp,'wb') as f:
        f.write(r.read())
    subprocess.run(['pw-play', tmp], timeout=90)
except Exception:
    try:
        rate = '-25' if '$speed' == '0.55' else '-10'
        subprocess.run(['spd-say','-r',rate,'-w',text[:500]], timeout=90)
    except Exception:
        pass
''';
    try { Process.run('python3', ['-c', py]); }
    catch (e) { debugPrint('[SoundService] Linux TTS: $e'); }
  }
}
