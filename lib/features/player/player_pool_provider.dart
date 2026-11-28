import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'video_audio_provider.dart';
import '../diagnostics/privacy_diagnostics.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerInstance {
  final Player player;
  final VideoController controller;

  PlayerInstance(this.player, this.controller);

  void dispose() {
    // Media-kit documentation says VideoController might not need explicit dispose
    // if Player is disposed, but it's safer to check and follow best practices
    // especially for native resources.
    player.dispose();
  }
}

class PlayerPoolNotifier extends Notifier<Map<String, PlayerInstance>> {
  @override
  Map<String, PlayerInstance> build() {
    // One setting for all pooled videos. A fresh process always starts muted,
    // even when the previous application session played with sound on.
    ref.listen(videoMutedProvider, (before, muted) {
      for (final instance in state.values) {
        unawaited(_applyVolume(instance.player, muted));
      }
    });
    ref.onDispose(() {
      for (final instance in state.values) {
        instance.dispose();
      }
    });
    return {};
  }

  void warmup(String id, String url, {bool isLandscape = false}) {
    if (state.containsKey(id)) return;

    final player = Player();
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    // Must mute before opening media: no audible first frame at app launch.
    final muted = ref.read(videoMutedProvider);
    unawaited(_prepare(player, url, muted));

    state = {...state, id: PlayerInstance(player, controller)};
  }

  Future<void> _applyVolume(Player player, bool muted) async {
    try {
      await player.setVolume(muted ? 0 : 100);
    } catch (_) {
      PrivacyDiagnostics.instance.record(DiagnosticEvent.audioApplyFailed);
    }
  }

  Future<void> _prepare(Player player, String url, bool muted) async {
    try {
      await player.setVolume(muted ? 0 : 100);
      await player.open(Media(url), play: false);
      if (ref.mounted) await _applyVolume(player, ref.read(videoMutedProvider));
    } catch (_) {
      // The visible player has its own timeout/retry. A disposed or failed
      // speculative player must never throw an unhandled async exception.
    }
  }

  void cleanupExcept(Set<String> activeIds) {
    final newState = <String, PlayerInstance>{};
    var didRemove = false;
    for (final entry in state.entries) {
      if (activeIds.contains(entry.key)) {
        newState[entry.key] = entry.value;
      } else {
        entry.value.dispose();
        didRemove = true;
      }
    }
    if (didRemove) state = newState;
  }
}

final playerPoolProvider =
    NotifierProvider<PlayerPoolNotifier, Map<String, PlayerInstance>>(
  PlayerPoolNotifier.new,
);
