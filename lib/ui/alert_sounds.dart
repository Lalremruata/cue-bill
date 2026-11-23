import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The two alert sounds, quietest first, so a louder tone can win when several fire at once.
enum AlertTone {
  /// A chime, repeated for 5 seconds.
  warning('sounds/warning.wav', Duration(seconds: 5)),

  /// An alarm, repeated for 30 seconds.
  timeUp('sounds/time_up.wav', Duration(seconds: 30));

  const AlertTone(this.asset, this.length);

  final String asset;

  /// How long the sound keeps looping.
  final Duration length;
}

/// Plays the bundled alert sounds on every platform.
///
/// Flutter's own `SystemSound.alert` is silent on Android and iOS, so the sounds are bundled
/// in `assets/sounds/`. On Android they play on the alarm stream, so a counter tablet with
/// its media volume turned down still rings.
///
/// Each sound loops for its [AlertTone.length]. A new alert restarts the sound, except that a
/// warning never cuts off an alarm that is still ringing.
class AlertSounds {
  /// Swap in a fake in tests, which have no audio plugin.
  static AlertSounds instance = AlertSounds();

  AudioPlayer? _player;
  AlertTone? _playing;
  Timer? _stopTimer;

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.alarm,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback, options: const {AVAudioSessionOptions.duckOthers}),
  );

  Future<void> play(AlertTone tone) async {
    final playing = _playing;
    if (playing != null && playing.index > tone.index) return;
    _stopTimer?.cancel();
    _playing = tone;
    _stopTimer = Timer(tone.length, stop);
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(tone.asset), ctx: _context);
    } catch (e) {
      debugPrint('Alert sound failed: $e');
      _stopTimer?.cancel();
      _playing = null;
      // Still beeps on desktop.
      SystemSound.play(SystemSoundType.alert);
    }
  }

  /// Silences the current sound early.
  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    _playing = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
