import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/core/database/entities.dart';
import 'package:xflow/features/feed/fresh_video_queue.dart';
import 'package:xflow/features/feed/local_video_filter.dart';
import 'package:xflow/features/feed/similar_video_discovery.dart';

Tweet clip(String id, String caption, {
  String? mediaKey,
  String? url,
  int? durationMs = 25000,
}) => Tweet(
  id: id, text: caption, userHandle: '@creator',
  isVideo: true, mediaKey: mediaKey, durationMs: durationMs,
  mediaUrls: [url ?? 'https://video.twimg.com/$id.mp4'],
);

void main() {
  test('keeps already visible video order and appends genuinely fresh items',
      () {
    final initial = [
      clip('a', '#Sport'),
      clip('b', '#Nature'),
      clip('c', '#Cyclisme'),
    ];
    final candidate = [
      clip('d', '#Nature'),
      clip('b', '#Nature duplicate'),
      clip('e', '#Sport'),
    ];
    final merged = appendFreshVideos(initial, candidate);
    expect(merged.map((v) => v.id), ['a', 'b', 'c', 'd', 'e']);
    expect(merged.take(3).map((v) => v.id),
        initial.map((v) => v.id));
  });

  test('excludes previously watched IDs across app sessions', () {
    final merged = appendFreshVideos(
      [clip('a', '#Nature')],
      [clip('b', '#Nature'), clip('c', '#Sport')],
      viewedIds: {'b'},
    );
    expect(merged.map((v) => v.id), ['a', 'c']);
  });

  test('deduplicates same media key or stable URL despite signed query', () {
    final merged = appendFreshVideos(
      [clip('a', '#Nature', mediaKey: 'shared',
          url: 'https://video.twimg.com/shared.mp4?token=old')],
      [
        clip('b', '#Nature', mediaKey: 'shared',
            url: 'https://video.twimg.com/b.mp4'),
        clip('c', '#Nature', mediaKey: 'other',
            url: 'https://video.twimg.com/shared.mp4?token=new'),
        clip('d', '#Nature'),
      ],
    );
    expect(merged.map((v) => v.id), ['a', 'd']);
  });

  test('strictly 15-second clips cannot enter home feed', () {
    final merged = appendFreshVideos([], [
      clip('short', '#Sport', durationMs: 15000),
      clip('long', '#Sport', durationMs: 15001),
    ]);
    expect(merged.map((v) => v.id), ['long']);
  });

  test('local personalized cache never admits unrelated topics', () {
    final pool = [
      clip('nature', 'Magnifique course #Nature'),
      clip('film', 'Film #Horror'),
      clip('cycling', 'Randonnée #Cyclisme'),
      clip('short', '#Nature', durationMs: 14999),
    ];
    final selected =
        cachedVideosMatchingTopics(pool, const ['nature', 'cyclisme']);
    expect(selected.map((v) => v.id), ['nature', 'cycling']);
    expect(cachedVideosMatchingTopics(pool, const []), isEmpty);
  });

  test('dislike transition is verified without recording either ID', () {
    final before = [
      clip('a', '#Nature'), clip('b', '#Cyclisme'), clip('c', '#Sport'),
    ];
    final after = [before[0], before[2]];
    expect(dislikeAdvancedToAnotherVideo(before, after, 'b', 1), true);
    expect(dislikeAdvancedToAnotherVideo(before, before, 'b', 1), false);
    expect(dislikeAdvancedToAnotherVideo([before[1]], [], 'b', 0), false);
  });

  test('sparse subscription batch still includes one recommendation', () {
    final result = mixRelatedVideos([clip('followed', '#Sport')],
      [clip('discovered', '#Sport')]);
    expect(result.map((v) => v.id), ['followed', 'discovered']);
  });

  test('sorting subscriptions does not invalidate home queue', () {
    final one = Subscription(id:'a', screenName:'@Alice', name:'Alice');
    final two = Subscription(id:'b', screenName:'bob', name:'Bob');
    final original = localSubscriptionSignature([one, two]);
    expect(localSubscriptionSignature([two, one]), original);
    expect(localSubscriptionSignature([
      Subscription(id:'x', screenName:'ALICE', name:'Changed display'),
      two,
    ]), original);
    expect(localSubscriptionSignature([one]), isNot(original));
  });
}
