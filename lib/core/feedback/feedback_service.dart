import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum Sfx {
  tap('tap.wav'),
  correct('correct.wav'),
  wrong('wrong.wav'),
  tick('tick.wav'),
  go('go.wav'),
  combo('combo.wav'),
  finish('finish.wav');

  const Sfx(this.file);
  final String file;
}

/// Plays sound effects and haptics, honouring the user's settings. Audio
/// problems (missing codec, muted device...) never interrupt gameplay.
class FeedbackService {
  FeedbackService({this.enableAudio = true});

  final bool enableAudio;
  final Map<Sfx, AudioPool> _pools = {};
  bool soundOn = true;
  bool hapticsOn = true;

  Future<void> preload() async {
    if (!enableAudio) return;
    try {
      // Mix with the user's music instead of pausing it.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
    } catch (e) {
      debugPrint('Audio context not set: $e');
    }
    for (final s in Sfx.values) {
      try {
        _pools[s] = await AudioPool.createFromAsset(
          path: 'sounds/${s.file}',
          maxPlayers: 3,
          playerMode: kIsWeb ? PlayerMode.mediaPlayer : PlayerMode.lowLatency,
        );
      } catch (e) {
        debugPrint('Could not load ${s.file}: $e');
      }
    }
  }

  void play(Sfx sfx, {double volume = 0.8}) {
    if (!soundOn) return;
    final pool = _pools[sfx];
    if (pool == null) return;
    pool.start(volume: volume).catchError((Object e) {
      debugPrint('Sound ${sfx.name} failed: $e');
      return () async {};
    });
  }

  void tapHaptic() {
    if (hapticsOn) HapticFeedback.selectionClick();
  }

  void correct({bool combo = false}) {
    play(combo ? Sfx.combo : Sfx.correct);
    if (hapticsOn) HapticFeedback.lightImpact();
  }

  void wrong() {
    play(Sfx.wrong);
    if (hapticsOn) HapticFeedback.heavyImpact();
  }

  void countdownTick() {
    play(Sfx.tick);
    if (hapticsOn) HapticFeedback.selectionClick();
  }

  void go() {
    play(Sfx.go);
    if (hapticsOn) HapticFeedback.mediumImpact();
  }

  void finish() {
    play(Sfx.finish);
    if (hapticsOn) HapticFeedback.mediumImpact();
  }
}
