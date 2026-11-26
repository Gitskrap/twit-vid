import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A deliberately closed vocabulary: callers cannot pass video IDs, account
/// names, URLs, hashtags, query text, exception messages or other strings.
/// This is independent of AppLogger (which may contain private raw X data).
enum DiagnosticEvent {
  tabVideos,
  tabSubscriptions,
  tabHashtags,
  tabLiked,
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
  videoPlaybackStarted,
  videoStartupTimeout,
  videoPlayerStreamError,
  videoAdvanceWaitingForReserve,
  feedReserveSample,
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

/// ONLY an event enum and optional aggregate count and duration are accepted. An event
/// cannot encode a user-visible item identity, even as a hashed identifier.
class DiagnosticEntry {
  const DiagnosticEntry({
    required this.elapsedMs,
    required this.event,
    this.countBucket,
    this.durationBucket,
  });

  final int elapsedMs;
  final DiagnosticEvent event;
  final String? countBucket;
  final String? durationBucket;

  Map<String, Object> toJson() => {
    'elapsed_ms': elapsedMs,
    'event': event.name,
    if (countBucket != null) 'count_bucket': countBucket!,
    if (durationBucket != null) 'duration_bucket': durationBucket!,
  };
}

String countBucket(int count) {
  if (count <= 0) return 'zero';
  if (count < 5) return 'one_to_four';
  if (count < 20) return 'five_to_nineteen';
  return 'twenty_plus';
}

String durationBucket(int ms) {
  if (ms < 250) return 'under_250ms';
  if (ms < 1000) return '250ms_to_1s';
  if (ms < 3000) return '1s_to_3s';
  if (ms < 6000) return '3s_to_6s';
  return '6s_plus';
}

/// Rolling local-only journal. The private storage uses timestamps to
/// recover recent events after a restart; exports contain relative time only.
class PrivacyDiagnostics extends ChangeNotifier {
  PrivacyDiagnostics._({int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _startedAt = (clock ?? (() => DateTime.now().millisecondsSinceEpoch))();

  static final PrivacyDiagnostics instance = PrivacyDiagnostics._();

  @visibleForTesting
  factory PrivacyDiagnostics.forTest(int Function() clock) =>
      PrivacyDiagnostics._(clock: clock);

  static const int maxEvents = 4000;
  static const int windowMs = 5 * 60 * 1000;
  static const _storageKey = 'anonymous_diagnostic_rolling_v1';
  final int Function() _clock;
  int _startedAt;
  final _entries = ListQueue<DiagnosticEntry>();
  final _evictions = ListQueue<int>();
  SharedPreferences? _prefs;
  Timer? _maintenance;
  Timer? _pendingWrite;

  bool get isRecording => true;
  int get eventCount {
    _prune(_clock());
    return _entries.length;
  }
  int get droppedEvents {
    _prune(_clock());
    return _evictions.length;
  }

  Future<void> initialize() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_storageKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is List) {
          final now = _clock();
          final recovered = <DiagnosticEntry>[];
          for (final row in data) {
            if (row is! Map) continue;
            final time = row['t'];
            final name = row['event'];
            if (time is! int || time < now - windowMs || time > now) continue;
            final matches = DiagnosticEvent.values.where((e) => e.name == name);
            if (matches.isEmpty) continue;
            final count = row['count_bucket'];
            final duration = row['duration_bucket'];
            recovered.add(DiagnosticEntry(
              elapsedMs: time,
              event: matches.first,
              countBucket: const {'zero', 'one_to_four', 'five_to_nineteen',
                'twenty_plus'}.contains(count) ? count as String : null,
              durationBucket: const {'under_250ms', '250ms_to_1s', '1s_to_3s',
                '3s_to_6s', '6s_plus'}.contains(duration) ? duration as String : null,
            ));
          }
          final merged = [...recovered, ..._entries]
            ..sort((a, b) => a.elapsedMs.compareTo(b.elapsedMs));
          _entries..clear()..addAll(merged);
          if (_entries.isNotEmpty && _entries.first.elapsedMs < _startedAt) {
            _startedAt = _entries.first.elapsedMs;
          }
        }
      }
      _prune(_clock());
      while (_entries.length > maxEvents) {
        _entries.removeFirst();
      }
      await flush();
      _maintenance = Timer.periodic(const Duration(seconds: 5), (_) {
        final removed = _prune(_clock());
        if (removed) {
          _scheduleWrite();
          notifyListeners();
        }
      });
    } catch (_) {
      // Diagnostics must never prevent the application from opening.
    }
  }

  bool _prune(int now) {
    final cutoff = now - windowMs;
    var changed = false;
    while (_entries.isNotEmpty && _entries.first.elapsedMs < cutoff) {
      _entries.removeFirst();
      changed = true;
    }
    while (_evictions.isNotEmpty && _evictions.first < cutoff) {
      _evictions.removeFirst();
    }
    return changed;
  }

  void _scheduleWrite() {
    if (_prefs == null || _pendingWrite?.isActive == true) return;
    _pendingWrite = Timer(const Duration(seconds: 1), () {
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _pendingWrite?.cancel();
    _pendingWrite = null;
    final prefs = _prefs;
    if (prefs == null) return;
    _prune(_clock());
    try {
      await prefs.setString(_storageKey, jsonEncode([
        for (final e in _entries) {
          't': e.elapsedMs,
          'event': e.event.name,
          if (e.countBucket != null) 'count_bucket': e.countBucket,
          if (e.durationBucket != null) 'duration_bucket': e.durationBucket,
        }
      ]));
    } catch (_) {
      // Keep the in-memory journal usable if storage is unavailable.
    }
  }

  void record(DiagnosticEvent event, {int? resultCount, int? durationMs}) {
    final now = _clock();
    _prune(now);
    while (_entries.length >= maxEvents) {
      _entries.removeFirst();
      _evictions.addLast(now);
      if (_evictions.length > maxEvents) _evictions.removeFirst();
    }
    _entries.addLast(DiagnosticEntry(
      elapsedMs: now,
      event: event,
      countBucket: resultCount == null ? null : countBucket(resultCount),
      durationBucket: durationMs == null ? null : durationBucket(durationMs),
    ));
    _scheduleWrite();
    notifyListeners();
  }

  /// Export a fresh snapshot without stopping or clearing the journal.
  String snapshot() {
    final now = _clock();
    _prune(now);
    final origin = now - windowMs > _startedAt ? now - windowMs : _startedAt;
    final totals = <String, int>{};
    for (final entry in _entries) {
      totals.update(entry.event.name, (v) => v + 1, ifAbsent: () => 1);
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'twit_vid_anonymous_diagnostics_v1',
      'app_version': '0.31.0',
      'window_seconds': 300,
      'elapsed_seconds': ((now - origin).clamp(0, windowMs)) ~/ 1000,
      'event_count': _entries.length,
      'events_dropped_due_to_limit': _evictions.length,
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
      'timeline': [
        for (final entry in _entries)
          {...entry.toJson(), 'elapsed_ms': (entry.elapsedMs - origin).clamp(0, windowMs)}
      ],
    });
  }

  Future<void> erase() async {
    _entries.clear();
    _evictions.clear();
    _startedAt = _clock();
    notifyListeners();
    await flush();
  }

  @override
  void dispose() {
    _maintenance?.cancel();
    _pendingWrite?.cancel();
    super.dispose();
  }
}
