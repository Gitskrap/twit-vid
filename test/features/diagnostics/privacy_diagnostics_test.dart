import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/diagnostics/privacy_diagnostics.dart';

void main() {
  final recorder = PrivacyDiagnostics.instance;

  setUp(() => recorder.erase());
  tearDown(() => recorder.erase());

  test('no recording happens before explicit consent', () {
    recorder.record(DiagnosticEvent.searchStarted);
    expect(recorder.eventCount, 0);
    expect(recorder.hasReport, false);
  });

  test('records only generic typed events and time relative to start', () {
    recorder.start();
    recorder.record(DiagnosticEvent.tabVideos);
    recorder.record(DiagnosticEvent.searchStarted);
    recorder.record(DiagnosticEvent.searchFound, resultCount: 17);
    recorder.record(DiagnosticEvent.castAutoNextSucceeded);
    final report = jsonDecode(recorder.stop()) as Map<String, dynamic>;
    expect(report['format'], 'twit_vid_anonymous_diagnostics_v1');
    expect(report['event_count'], 4);
    expect(report['summary']['searchStarted'], 1);
    final events = report['timeline'] as List<dynamic>;
    expect(events[2]['count_bucket'], 'five_to_nineteen');
    for (final event in events) {
      expect((event as Map).keys,
          everyElement(isIn({'elapsed_ms', 'event', 'count_bucket', 'duration_bucket'})));
      expect(event['elapsed_ms'], greaterThanOrEqualTo(0));
      expect(DiagnosticEvent.values.map((e) => e.name),
          contains(event['event']));
    }
  });

  test('never exports X data, URLs, searches, account handles or hashed IDs',
      () {
    recorder.start();
    recorder.record(DiagnosticEvent.hashtagOpened);
    recorder.record(DiagnosticEvent.searchCacheFallback);
    recorder.record(DiagnosticEvent.videoLiked);
    recorder.record(DiagnosticEvent.videoDisliked);
    recorder.record(DiagnosticEvent.feedLoadMoreCompleted, resultCount: 100);
    final report = recorder.stop();
    for (final forbidden in [
      'tweet_id', 'video_id', 'user_handle', 'handle', 'screenName',
      'accountId', 'postId', 'username', 'subscriptions', 'hashtag_text',
      'search_query', 'searchTerm', 'cookie', 'access_token', 'http://',
      'https://', 'sha256', 'tweet_text', 'caption', 'mediaUrls',
      'timestamp_utc', '@privateAccount', '#privateInterest',
    ]) {
      // 'subscriptions_included' is a false privacy declaration, not data.
      if (forbidden == 'subscriptions') continue;
      expect(report.contains(forbidden), false, reason: forbidden);
    }
    final json = jsonDecode(report) as Map<String, dynamic>;
    expect(json['privacy']['account_names_included'], false);
    expect(json['privacy']['subscriptions_included'], false);
    expect(json['privacy']['hashtags_included'], false);
    expect(json['privacy']['search_terms_included'], false);
    expect(json['privacy']['urls_included'], false);
    expect(json['privacy']['raw_errors_included'], false);
    expect(json['privacy']['absolute_timestamps_included'], false);
    expect(json['timeline'][4]['count_bucket'], 'twenty_plus');
  });

  test('starting a new session and erasing purge the previous report', () {
    recorder.start();
    recorder.record(DiagnosticEvent.videoPlaybackFailed);
    recorder.stop();
    expect(recorder.hasReport, true);

    recorder.start();
    expect(recorder.hasReport, false);
    expect(recorder.eventCount, 0);
    recorder.record(DiagnosticEvent.tabHashtags);
    final json = jsonDecode(recorder.stop()) as Map<String, dynamic>;
    expect(json['summary'].containsKey('videoPlaybackFailed'), false);
    expect(json['summary']['tabHashtags'], 1);
    recorder.erase();
    expect(recorder.isRecording, false);
    expect(recorder.hasReport, false);
  });

  test('events are bounded to protect performance and report size', () {
    recorder.start();
    for (var i = 0; i < PrivacyDiagnostics.maxEvents + 5; i++) {
      recorder.record(DiagnosticEvent.videoAdvanced);
    }
    expect(recorder.eventCount, PrivacyDiagnostics.maxEvents);
    expect(recorder.droppedEvents, 5);
    final data = jsonDecode(recorder.stop()) as Map<String, dynamic>;
    expect(data['timeline'], hasLength(PrivacyDiagnostics.maxEvents));
    expect(data['events_dropped_due_to_limit'], 5);
  });

  test('playback latency and reserve remain bucketed and anonymous', () {
    recorder.start();
    recorder.record(DiagnosticEvent.videoPlaybackStarted, durationMs: 732);
    recorder.record(DiagnosticEvent.feedReserveSample, resultCount: 27);
    final report = jsonDecode(recorder.stop()) as Map<String, dynamic>;
    expect(report['app_version'], '0.30.0');
    expect(report['timeline'][0]['duration_bucket'], '250ms_to_1s');
    expect(report['timeline'][1]['count_bucket'], 'twenty_plus');
    expect(report['timeline'][0].containsKey('duration_ms'), false);
    expect(durationBucket(6000), '6s_plus');
  });

  test('count bucketing does not disclose exact result totals', () {
    expect(countBucket(-1), 'zero');
    expect(countBucket(0), 'zero');
    expect(countBucket(1), 'one_to_four');
    expect(countBucket(4), 'one_to_four');
    expect(countBucket(5), 'five_to_nineteen');
    expect(countBucket(19), 'five_to_nineteen');
    expect(countBucket(20), 'twenty_plus');
  });
}
