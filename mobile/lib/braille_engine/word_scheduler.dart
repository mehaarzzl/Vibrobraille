import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'braille_translator.dart';
import 'temporal_encoder.dart';

class WordScheduler {
  final BrailleTranslator translator;
  final TemporalEncoder encoder;
  final Function(String) onWordRendered;
  final FlutterTts tts = FlutterTts();

  static const platform = MethodChannel('com.vibrobraille/haptics');

  WordScheduler({
    required this.translator,
    required this.encoder,
    required this.onWordRendered,
  }) {
    _initTts();
  }

  void _initTts() async {
    await tts.setLanguage("en-US");
    await tts.setSpeechRate(0.5);
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);
  }

  /// Processes a single word: translates, encodes, vibrates, and speaks.
  Future<void> scheduleWord(String word) async {
    onWordRendered(word);

    // 1. Speak the word
    tts.speak(word);

    final dots = translator.translate(word);
    final pattern = encoder.encodeText(dots);

    // Calculate total duration for debugging
    final totalDuration = pattern.timings.fold(0, (sum, t) => sum + t);
    print(
        "🌊 Haptic Pattern for '$word': ${pattern.timings.length} steps, ${totalDuration}ms total");

    try {
      await platform.invokeMethod('vibrateWaveform', {
        'timings': pattern.timings,
        'amplitudes': pattern.amplitudes,
      });
    } on PlatformException catch (e) {
      print("Haptic error: ${e.message}");
    }
  }

  /// Long buzz for sentence end (~700ms).
  Future<void> scheduleSentenceEnd() async {
    try {
      await platform.invokeMethod('vibrateWaveform', {
        'timings': [700],
        'amplitudes': [255],
      });
    } on PlatformException catch (e) {
      print("Haptic error: ${e.message}");
    }
  }

  /// Double long buzz for paragraph end.
  Future<void> scheduleParagraphEnd() async {
    try {
      await platform.invokeMethod('vibrateWaveform', {
        'timings': [500, 200, 500],
        'amplitudes': [255, 0, 255],
      });
    } on PlatformException catch (e) {
      print("Haptic error: ${e.message}");
    }
  }
}
