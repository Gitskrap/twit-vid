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
  for (final candidate in candidates) {
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
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  // Video URLs may carry expiring query params. No URLs reach diagnostics.
  return uri.replace(query: null, fragment: null).toString();
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
    if (!video.isVideo || video.mediaUrls.isEmpty) return false;
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
