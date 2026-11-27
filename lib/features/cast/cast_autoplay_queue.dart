import '../../core/models/tweet.dart';

/// Picks the next eligible item without repeating clips that have been cast
/// during this session. The ordering follows the active screen's playlist.
Tweet? nextCastVideo(
  String currentId,
  Iterable<Tweet> playlist,
  Set<String> alreadyCast,
) {
  final items = playlist.toList();
  if (items.isEmpty) return null;
  final currentIndex = items.indexWhere((item) => item.id == currentId);
  if (currentIndex < 0) return null;
  for (var i = currentIndex + 1; i < items.length; i++) {
    final item = items[i];
    if (alreadyCast.contains(item.id) ||
        !item.isVideo ||
        item.mediaUrls.isEmpty ||
        (item.durationMs != null && item.durationMs! <= 15000)) {
      continue;
    }
    return item;
  }
  return null;
}

/// A stale finish during LOAD or before the new session has actually played
/// must not advance the queue.
bool isConfirmedCastFinish({
  required bool loading,
  required bool confirmedPlaying,
  required int? expectedSession,
  required int reportedSession,
  required bool idle,
  required bool finished,
}) => !loading && confirmedPlaying && expectedSession != null &&
    expectedSession == reportedSession && idle && finished;
