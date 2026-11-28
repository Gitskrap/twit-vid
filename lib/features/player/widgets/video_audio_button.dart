import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../video_audio_provider.dart';

/// Shared local sound control, deliberately outside screen-specific headers.
class VideoAudioButton extends ConsumerWidget {
  const VideoAudioButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = ref.watch(videoMutedProvider);
    return IconButton.filledTonal(
      tooltip: muted ? 'Activer le son' : 'Couper le son',
      onPressed: () => ref.read(videoMutedProvider.notifier).toggle(),
      icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
    );
  }
}
