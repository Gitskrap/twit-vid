import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xflow/features/diagnostics/privacy_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late int now;
  late PrivacyDiagnostics recorder;

  setUp(() {
    now = 1700000000000;
    recorder = PrivacyDiagnostics.forTest(() => now);
  });
  tearDown(() => recorder.dispose());

  Map<String, dynamic> report() =>
      jsonDecode(recorder.snapshot()) as Map<String, dynamic>;

  test('automatic recording without starting a session', () {
    recorder.record(DiagnosticEvent.searchStarted);
    expect(recorder.isRecording, true);
    expect(report()['event_count'], 1);
    expect(report()['app_version'], '0.34.0');
  });

  test('exports only the last five minutes using relative timestamps', () {
    recorder.record(DiagnosticEvent.videoPlaybackFailed);
    now += 1000;
    recorder.record(DiagnosticEvent.tabVideos);
    now += 299000;
    recorder.record(DiagnosticEvent.searchFound, resultCount: 17);
    now += 1000;
    final data = report();
    expect(data['elapsed_seconds'], 300);
    expect(data['window_seconds'], 300);
    expect(data['summary'].containsKey('videoPlaybackFailed'), false);
    expect(data['timeline'][0]['elapsed_ms'], 0);
    expect(data['timeline'][1]['elapsed_ms'], 299000);
    expect(data['timeline'][1]['count_bucket'], 'five_to_nineteen');
  });

  test('export does not stop or clear recording; erase resumes automatically', () async {
    recorder.record(DiagnosticEvent.videoLiked);
    expect(report()['event_count'], 1);
    recorder.record(DiagnosticEvent.videoAdvanced);
    expect(report()['event_count'], 2);
    await recorder.erase();
    expect(report()['event_count'], 0);
    recorder.record(DiagnosticEvent.tabLiked);
    expect(report()['summary']['tabLiked'], 1);
  });

  test('bounded journal keeps the newest events', () {
    recorder.record(DiagnosticEvent.videoPlaybackFailed);
    for (var i = 0; i < PrivacyDiagnostics.maxEvents; i++) {
      recorder.record(DiagnosticEvent.videoAdvanced);
    }
    final data = report();
    expect(data['event_count'], PrivacyDiagnostics.maxEvents);
    expect(data['events_dropped_due_to_limit'], 1);
    expect(data['summary'].containsKey('videoPlaybackFailed'), false);
  });

  test('typed anonymous entries only; no absolute timestamps', () {
    recorder.record(DiagnosticEvent.videoPlaybackStarted, durationMs: 732);
    recorder.record(DiagnosticEvent.feedReserveSample, resultCount: 27);
    final data = report();
    expect(data['timeline'][0]['duration_bucket'], '250ms_to_1s');
    expect(data['timeline'][1]['count_bucket'], 'twenty_plus');
    for (final e in data['timeline']) {
      expect((e as Map).keys, everyElement(isIn({
        'elapsed_ms', 'event', 'count_bucket', 'duration_bucket'
      })));
    }
    final raw = recorder.snapshot();
    expect(raw.contains(now.toString()), false);
    for (final value in (data['privacy'] as Map).values) {
      expect(value, false);
    }
  });

  test('recent events survive a restart but expired ones do not', () async {
    SharedPreferences.setMockInitialValues({});
    await recorder.initialize();
    recorder.record(DiagnosticEvent.videoPlaybackFailed);
    now += 200000;
    recorder.record(DiagnosticEvent.videoAdvanced);
    await recorder.flush();
    now += 110000;
    final restarted = PrivacyDiagnostics.forTest(() => now);
    try {
      await restarted.initialize();
      final data = jsonDecode(restarted.snapshot()) as Map<String, dynamic>;
      expect(data['event_count'], 1);
      expect(data['summary']['videoAdvanced'], 1);
      expect(data['summary'].containsKey('videoPlaybackFailed'), false);
      await restarted.erase();
    } finally {
      restarted.dispose();
    }
  });

  test('download consumes only saved events and preserves concurrent events', () async {
    recorder.record(DiagnosticEvent.tabVideos);
    final location = await recorder.downloadAndClear((report) async {
      expect(jsonDecode(report)['event_count'], 1);
      recorder.record(DiagnosticEvent.tabLiked);
      return 'Downloads/twit-vid-anonyme.json';
    });
    expect(location, contains('twit-vid-anonyme.json'));
    expect(report()['event_count'], 1);
    expect(report()['summary']['tabLiked'], 1);
  });

  test('successful export clears persistent storage across restart', () async {
    SharedPreferences.setMockInitialValues({});
    await recorder.initialize();
    recorder.record(DiagnosticEvent.tabVideos);
    await recorder.flush();
    await recorder.downloadAndClear((_) async => 'Downloads/report.json');
    final restarted = PrivacyDiagnostics.forTest(() => now);
    try {
      await restarted.initialize();
      expect(restarted.eventCount, 0);
    } finally {
      restarted.dispose();
    }
  });

  test('failed download retains all events', () async {
    recorder.record(DiagnosticEvent.tabVideos);
    await expectLater(recorder.downloadAndClear((_) async {
      throw StateError('disk full');
    }), throwsStateError);
    expect(report()['event_count'], 1);
  });

  test('idle journal ages out even without new events', () {
    recorder.record(DiagnosticEvent.videoAdvanced);
    now += 300001;
    expect(report()['event_count'], 0);
  });
}
