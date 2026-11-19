import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A deliberately closed vocabulary: callers cannot pass video IDs, account
/// names, URLs, hashtags, query text, exception messages or other strings.
/// This is independent of AppLogger (which may contain private raw X data).
enum DiagnosticEvent {
  tabVideos,
  tabSubscriptions,
  tabHashtags,
  searchOpened,
  searchStarted,
  searchFound,
  searchEmpty,
  searchCacheFallback,
  searchFailed,
  hashtagOpened,
  hashtagLoaded,
  hashtagEmpty,
  hashtagFailed,
  videoAdvanced,
  videoDisliked,
  videoLiked,
  dislikeAdvanceRequested,
  dislikeAdvanceConfirmed,
  dislikeAdvanceNoNext,
  videoPlaybackCompleted,
  videoPlaybackRetry,
  videoPlaybackFailed,
  videoSkippedTooShort,
  videoDurationUnknown,
  feedInitialLoad,
  feedRefreshStarted,
  feedRefreshCompleted,
  feedLoadMoreStarted,
  feedLoadMoreCompleted,
  feedLoadEmpty,
  feedLoadFailed,
  feedRefreshCoalesced,
  feedNoFreshCandidates,
  feedLoadCooldown,
  feedRepeatedCandidatesFiltered,
  castPickerOpened,
  castPlayStarted,
  castPlaySucceeded,
  castPlayFailed,
  castVideoFinished,
  castAutoNextStarted,
  castAutoNextSucceeded,
  castAutoNextEmpty,
  castAutoNextFailed,
  castDisconnected,
  castStopped,
  updateCheckStarted,
  updateCheckCompleted,
  updateCheckFailed,
}

/// ONLY an event enum and an optional aggregate count are accepted. An event
/// cannot encode a user-visible item identity, even as a hashed identifier.
class DiagnosticEntry {
  const DiagnosticEntry({
    required this.elapsedMs,
    required this.event,
    this.countBucket,
  });

  final int elapsedMs;
  final DiagnosticEvent event;
  final String? countBucket;

  Map<String, Object> toJson() => {
    'elapsed_ms': elapsedMs,
    'event': event.name,
    if (countBucket != null) 'count_bucket': countBucket!,
  };
}

String countBucket(int count) {
  if (count <= 0) return 'zero';
  if (count < 5) return 'one_to_four';
  if (count < 20) return 'five_to_nineteen';
  return 'twenty_plus';
}

/// No background collection: recording starts ONLY after an explicit tap.
/// All events live in volatile memory until the user explicitly exports them.
class PrivacyDiagnostics extends ChangeNotifier {
  PrivacyDiagnostics._();

  static final PrivacyDiagnostics instance = PrivacyDiagnostics._();

  final List<DiagnosticEntry> _entries = [];
  Stopwatch? _stopwatch;
  bool _recording = false;
  int _droppedEvents = 0;
  String? _finishedReport;

  static const int maxEvents = 4000;
  bool get isRecording => _recording;
  int get eventCount => _entries.length;
  int get droppedEvents => _droppedEvents;
  bool get hasReport => _finishedReport != null;
  String? get finishedReport => _finishedReport;

  void start() {
    _stopwatch?.stop();
    _entries.clear();
    _droppedEvents = 0;
    _finishedReport = null;
    _stopwatch = Stopwatch()..start();
    _recording = true;
    notifyListeners();
  }

  void record(DiagnosticEvent event, {int? resultCount}) {
    if (!_recording) return;
    if (_entries.length >= maxEvents) {
      _droppedEvents++;
      return;
    }
    _entries.add(DiagnosticEntry(
      elapsedMs: _stopwatch?.elapsedMilliseconds ?? 0,
      event: event,
      countBucket: resultCount == null ? null : countBucket(resultCount),
    ));
    // Notify only the diagnostics screen, not every widget in the app.
    notifyListeners();
  }

  String stop() {
    _stopwatch?.stop();
    _recording = false;
    final duration = _stopwatch?.elapsedMilliseconds ?? 0;
    final totals = <String, int>{};
    for (final entry in _entries) {
      totals.update(entry.event.name, (v) => v + 1, ifAbsent: () => 1);
    }
    _finishedReport = const JsonEncoder.withIndent('  ').convert({
      'format': 'twit_vid_anonymous_diagnostics_v1',
      'app_version': '0.28.0',
      'elapsed_seconds': duration ~/ 1000,
      'event_count': _entries.length,
      'events_dropped_due_to_limit': _droppedEvents,
      'privacy': {
        'content_identifiers_included': false,
        'account_names_included': false,
        'subscriptions_included': false,
        'hashtags_included': false,
        'search_terms_included': false,
        'urls_included': false,
        'raw_errors_included': false,
        'absolute_timestamps_included': false,
      },
      'summary': totals,
      'timeline': _entries.map((entry) => entry.toJson()).toList(),
    });
    notifyListeners();
    return _finishedReport!;
  }

  void erase() {
    _stopwatch?.stop();
    _stopwatch = null;
    _recording = false;
    _entries.clear();
    _droppedEvents = 0;
    _finishedReport = null;
    notifyListeners();
  }

  @visibleForTesting
  List<DiagnosticEntry> get testEntries => List.unmodifiable(_entries);
}
