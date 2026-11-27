import '../../core/models/tweet.dart';
import 'local_recommendation_profile.dart';

/// The player owns the current index. Existing clips must stay in the exact
/// same order while new recommendations are appended to the end.
List<Tweet> appendFreshVideos(
  Iterable<Tweet> existing,
  Iterable<Tweet> candidates, {
  Set<String> viewedIds = const <String>{},
  int? maxAdded,
}) {
  final output = List<Tweet>.from(existing);
  final ids = output.map((t) => t.id).toSet();
  final mediaKeys = output
      .map((t) => t.mediaKey)
      .whereType<String>()
      .where((key) => key.isNotEmpty)
      .toSet();
  final mediaUrls = output
      .where((t) => t.mediaUrls.isNotEmpty)
      .map((t) => _stableMediaPath(t.mediaUrls.first))
      .toSet();

  var added = 0;
  for (final candidate in diversifyAuthors(candidates, previous: output)) {
    if (!candidate.isVideo || candidate.mediaUrls.isEmpty ||
        (candidate.durationMs != null && candidate.durationMs! <= 15000) ||
        viewedIds.contains(candidate.id) || ids.contains(candidate.id)) {
      continue;
    }
    final key = candidate.mediaKey;
    final media = _stableMediaPath(candidate.mediaUrls.first);
    if ((key != null && key.isNotEmpty && mediaKeys.contains(key)) ||
        mediaUrls.contains(media)) continue;

    ids.add(candidate.id);
    if (key != null && key.isNotEmpty) mediaKeys.add(key);
    mediaUrls.add(media);
    output.add(candidate);
    added++;
    if (maxAdded != null && added >= maxAdded) break;
  }
  return output;
}

String _stableMediaPath(String url) {
  // Uri.replace(query: null) preserves the original query. Strip the
  // expiring signature explicitly so the same media is not shown twice.
  return url.split(RegExp(r'[?#]')).first;
}

/// Only used for the on-device fallback when there are no local creator
/// subscriptions. Do not fill the personalized home with arbitrary cached
/// content from past searches.
List<Tweet> cachedVideosMatchingTopics(
  Iterable<Tweet> candidates,
  Iterable<String> personalizedTopics,
) {
  final topics = personalizedTopics
      .map((topic) => topic.replaceFirst(RegExp(r'^#+'), '').toLowerCase())
      .where((topic) => topic.length >= 2)
      .toSet();
  if (topics.isEmpty) return const <Tweet>[];

  return candidates.where((video) {
    if (!video.isVideo || video.mediaUrls.isEmpty ||
        (video.durationMs != null && video.durationMs! <= 15000)) return false;
    final matches = captionHashtags(video.text);
    matches.addAll(captionKeywords(video.text));
    return matches.intersection(topics).isNotEmpty;
  }).toList();
}

/// Checks a UI transition by IDs only in memory. No ID is exported by the
/// event logger: callers record only a fixed success/failure event type.
bool dislikeAdvancedToAnotherVideo(
  List<Tweet> before,
  List<Tweet> after,
  String rejectedId,
  int originalIndex,
) {
  if (before.isEmpty || after.isEmpty || originalIndex < 0 ||
      originalIndex >= before.length ||
      before[originalIndex].id != rejectedId) return false;
  if (after.any((tweet) => tweet.id == rejectedId)) return false;
  final index = originalIndex.clamp(0, after.length - 1);
  return after[index].id != rejectedId;
}

/// Reorder new candidates only. Prefer authors not shown in the last four
/// slots; if supply is narrow, retain playable videos rather than starve.
List<Tweet> diversifyAuthors(Iterable<Tweet> candidates, {
  Iterable<Tweet> previous = const <Tweet>[],
}) {
  String author(Tweet t) => t.userHandle.replaceFirst('@', '').toLowerCase();
  final remaining = candidates.toList();
  final result = <Tweet>[];
  final recent = previous.toList().reversed.take(6).toList().reversed
      .map(author).toList();
  while (remaining.isNotEmpty) {
    var best = 0;
    var bestPenalty = 100000;
    for (var i = 0; i < remaining.length; i++) {
      final a = author(remaining[i]);
      final count = recent.where((v) => v == a).length;
      final adjacent = recent.isNotEmpty && recent.last == a ? 10 : 0;
      final penalty = count * 3 + adjacent;
      if (penalty < bestPenalty) {
        best = i;
        bestPenalty = penalty;
        if (penalty == 0) break;
      }
    }
    final chosen = remaining.removeAt(best);
    result.add(chosen);
    recent.add(author(chosen));
    if (recent.length > 6) recent.removeAt(0);
  }
  return result;
}
