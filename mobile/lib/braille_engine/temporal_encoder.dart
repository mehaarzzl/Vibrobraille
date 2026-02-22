class BrailleHapticPattern {
  final List<int> timings;
  final List<int> amplitudes;

  BrailleHapticPattern(this.timings, this.amplitudes);
}

class TemporalEncoder {
  int dotDuration; // ms
  int interDotDelay; // ms
  int interCharDelay; // ms
  double amplitudeScale;

  TemporalEncoder({
    this.dotDuration = 100,
    this.interDotDelay = 50,
    this.interCharDelay = 300,
    this.amplitudeScale = 1.0,
  });

  /// Encodes a single Braille character (list of dots) into haptic timings and amplitudes.
  /// Dots are 1-6.
  BrailleHapticPattern encodeCharacter(List<int> dots) {
    if (dots.isEmpty) {
      // Space or unknown
      return BrailleHapticPattern([interCharDelay], [0]);
    }

    List<int> sortedDots = List.from(dots)..sort();
    List<int> timings = [];
    List<int> amplitudes = [];

    for (int i = 0; i < sortedDots.length; i++) {
      // Vibrate for dotDuration
      timings.add(dotDuration);
      amplitudes.add((255 * amplitudeScale).toInt());

      // If not the last dot, add inter-dot delay
      if (i < sortedDots.length - 1) {
        timings.add(interDotDelay);
        amplitudes.add(0);
      }
    }

    // Add inter-character delay at the end
    timings.add(interCharDelay);
    amplitudes.add(0);

    return BrailleHapticPattern(timings, amplitudes);
  }

  /// Encodes a full string into a single large waveform.
  BrailleHapticPattern encodeText(List<List<int>> translatedText) {
    List<int> allTimings = [];
    List<int> allAmplitudes = [];

    for (var dots in translatedText) {
      var pattern = encodeCharacter(dots);
      allTimings.addAll(pattern.timings);
      allAmplitudes.addAll(pattern.amplitudes);
    }

    return BrailleHapticPattern(allTimings, allAmplitudes);
  }
}
