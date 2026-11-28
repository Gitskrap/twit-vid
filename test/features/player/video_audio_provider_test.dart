import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:xflow/features/player/widgets/video_audio_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/player/video_audio_provider.dart';

void main() {
  testWidgets('shared control toggles sound across recreated screens', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Widget screen(Key key) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: VideoAudioButton(key: key))),
    );
    await tester.pumpWidget(screen(const ValueKey('search')));
    expect(find.byTooltip('Activer le son'), findsOneWidget);
    await tester.tap(find.byTooltip('Activer le son'));
    await tester.pumpAndSettle();
    expect(container.read(videoMutedProvider), false);
    await tester.pumpWidget(screen(const ValueKey('liked')));
    expect(find.byTooltip('Couper le son'), findsOneWidget);
    await tester.tap(find.byTooltip('Couper le son'));
    await tester.pumpAndSettle();
    expect(container.read(videoMutedProvider), true);
  });

  test('every new app provider container starts muted', () {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    expect(first.read(videoMutedProvider), isTrue);
    first.read(videoMutedProvider.notifier).toggle();
    expect(first.read(videoMutedProvider), isFalse);

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(restarted.read(videoMutedProvider), isTrue);
    restarted.read(videoMutedProvider.notifier).mute();
    expect(restarted.read(videoMutedProvider), isTrue);
  });
}
