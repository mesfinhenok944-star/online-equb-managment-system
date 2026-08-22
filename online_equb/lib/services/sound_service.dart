import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Amharic & Multi-Platform Text-To-Speech and Audio Service for Equb Draw Algorithm
class SoundService {
  static final FlutterTts _tts = FlutterTts();
  static bool _ttsSupported = false;
  static bool _initialized = false;

  /// Initialize TTS settings for Amharic audio output
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Desktop Linux uses python Google TTS & PipeWire audio player (pw-play)
    if (!kIsWeb && Platform.isLinux) {
      _ttsSupported = false;
      return;
    }

    try {
      final available = await _tts.isLanguageAvailable("am-ET");
      if (available == true) {
        await _tts.setLanguage("am-ET");
        _ttsSupported = true;
      } else {
        final amAvailable = await _tts.isLanguageAvailable("am");
        if (amAvailable == true) {
          await _tts.setLanguage("am");
          _ttsSupported = true;
        } else {
          await _tts.setLanguage("en-US");
          _ttsSupported = true;
        }
      }
      await _tts.setSpeechRate(0.30); // Slow & clear speech speed
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('[SoundService Init Warning] $e');
      _ttsSupported = false;
    }
  }

  /// Play rotation click feedback sound
  static void playClickSound() {
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  /// Speak spinning announcement during wheel rotation (Repeated 3 times slowly in Amharic):
  /// "እቁቡ ለውጥ ነው አሁን በመዞር ላይ ነው።"
  static Future<void> speakSpinningAnnouncement() async {
    const textSingleAm = "እቁቡ ለውጥ ነው አሁን በመዞር ላይ ነው።";
    const textTripleAm = "$textSingleAm . $textSingleAm . $textSingleAm.";

    // 1. Linux Desktop: Native Google TTS via Python & PipeWire audio player
    if (!kIsWeb && Platform.isLinux) {
      try {
        await _playLinuxAmharicAudio(textTripleAm);
        return;
      } catch (e) {
        debugPrint('[SoundService Linux Audio Error] $e');
        try {
          await Process.run('spd-say', ['-r', '-20', textTripleAm]);
          return;
        } catch (_) {}
      }
    }

    // 2. FlutterTTS for Android / iOS / Web
    try {
      await init();
      if (_ttsSupported) {
        await _tts.stop();
        await _tts.setSpeechRate(0.32);
        await _tts.speak(textTripleAm);
      }
    } catch (e) {
      debugPrint('[SoundService Spinning Speech Warning] $e');
    }
  }

  /// Speak winner full name and ID loudly REPEATED 3 TIMES SLOWLY in Amharic:
  /// "አሸናፊው [FULL_NAME] መታወቂያ ቁጥር [WINNER_ID] ነው!" (Repeated 3 times)
  static Future<void> speakWinnerRepeatedThreeTimes({
    required String fullName,
    required String uniqueId,
  }) async {
    final cleanName = fullName.trim().isEmpty ? 'ተሳታፊ' : fullName.trim();
    final cleanId = uniqueId.trim().isEmpty ? '-' : uniqueId.trim();

    final sentenceAm = "አሸናፊው $cleanName መታወቂያ ቁጥር $cleanId ነው።";
    final tripleAnnouncementAm = "$sentenceAm . $sentenceAm . $sentenceAm.";

    // 1. Linux Desktop: Native Google TTS via Python & PipeWire audio player
    if (!kIsWeb && Platform.isLinux) {
      try {
        await _playLinuxAmharicAudio(tripleAnnouncementAm);
        return;
      } catch (e) {
        debugPrint('[SoundService Linux Audio Error] $e');
        try {
          await Process.run('spd-say', ['-r', '-25', tripleAnnouncementAm]);
          return;
        } catch (_) {}
      }
    }

    // 2. FlutterTTS for Android / iOS / Web
    try {
      await init();
      if (_ttsSupported) {
        await _tts.stop();
        await _tts.setSpeechRate(0.30); // Slow rate for clear winner details
        await _tts.speak(tripleAnnouncementAm);
      }
    } catch (e) {
      debugPrint('[SoundService Winner Speech Warning] $e');
    }
  }

  /// Execute Amharic Audio Speech Synthesis on Linux using Python & PipeWire / ALSA player
  static Future<void> _playLinuxAmharicAudio(String text) async {
    final pyScript = '''
import urllib.request, urllib.parse, os, subprocess, sys
text = """$text"""
try:
    url = 'https://translate.google.com/translate_tts?ie=UTF-8&q=' + urllib.parse.quote(text) + '&tl=am&client=tw-ob'
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    tmp_file = '/tmp/equb_voice_play.mp3'
    with urllib.request.urlopen(req) as resp, open(tmp_file, 'wb') as f:
        f.write(resp.read())
    subprocess.run(['pw-play', tmp_file], check=False)
except Exception as e:
    subprocess.run(['spd-say', text], check=False)
''';
    await stop();
    await Process.run('python3', ['-c', pyScript]);
  }

  /// Immediately stop any ongoing audio speech output
  static Future<void> stop() async {
    if (!kIsWeb && Platform.isLinux) {
      try {
        await Process.run('pkill', ['-f', 'pw-play']);
        await Process.run('pkill', ['-f', 'equb_voice_play']);
        await Process.run('spd-say', ['-S']);
      } catch (_) {}
    }
    try {
      if (_ttsSupported) {
        await _tts.stop();
      }
    } catch (_) {}
  }
}
