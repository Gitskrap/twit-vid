import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../diagnostics/privacy_diagnostics.dart';

/// Every new application process starts muted. The choice is intentionally
/// session-only: previous sound-on usage must never autoplay loudly on launch.
class VideoAudioNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => setMuted(!state);
  void mute() => setMuted(true);

  void setMuted(bool muted) {
    if (state == muted) return;
    state = muted;
    PrivacyDiagnostics.instance.record(muted
        ? DiagnosticEvent.audioMuted : DiagnosticEvent.audioUnmuted);
  }
}

final videoMutedProvider =
    NotifierProvider<VideoAudioNotifier, bool>(VideoAudioNotifier.new);
