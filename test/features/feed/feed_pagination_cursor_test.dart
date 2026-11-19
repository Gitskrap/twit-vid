import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/feed_provider.dart';

Tweet video(String id, int duration) => Tweet(
  id: id,
  text: '#Nature',
  userHandle: '@creator',
  mediaUrls: ['https://video.twimg.com/$id.mp4'],
  isVideo: true,
  durationMs: duration,
);

void main() {
  test('refresh clears a stale exhausted cursor instead of reusing page one',
      () {
    final before = FeedState(tweets: [video('a', 30000)],
        cursorBottom: 'old-cursor');
    final loading = before.copyWith(isRefreshing: true);
    expect(loading.cursorBottom, 'old-cursor');

    final refreshed = loading.copyWith(
      cursorBottom: null,
      replaceCursor: true,
      isRefreshing: false,
    );
    expect(refreshed.cursorBottom, isNull);
    expect(refreshed.tweets.single.id, 'a');
  });

  test('new valid cursor is retained while old pagination is retired', () {
    final state = FeedState(tweets: [video('a', 30000)],
        cursorBottom: 'cursor-1');
    expect(state.copyWith(
      cursorBottom: 'cursor-2', replaceCursor: true,
    ).cursorBottom, 'cursor-2');
    expect(state.copyWith(isLoadingMore: true).cursorBottom, 'cursor-1');
  });

  test('home feed continues enforcing strictly more than 15 seconds', () {
    final state = FeedState(tweets: [
      video('short', 15000),
      video('long', 15001),
    ]);
    expect(state.tweets.map((v) => v.id), ['long']);
  });
}
