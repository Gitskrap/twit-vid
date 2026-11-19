import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/tweet.dart';

Tweet recommended(String id, String caption) => Tweet(
  id: id, text: caption, userHandle: '@discovered',
  mediaUrls: ['https://video.twimg.com/$id.mp4'],
  mediaKey: id, isVideo: true, durationMs: 30000,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('first viewed recommendation is cached and never proposed again',
      () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    final first = recommended('1900000000000008101', '#Nature');
    final second = recommended('1900000000000008102', '#Cyclisme');
    // The initial personalized recommendation is not cached yet.
    await Repository.markMediaAsPlayed(first.id, video: first);
    await Repository.insertCachedMedia([second]);

    final viewed = await Repository.getViewedVideoIds();
    expect(viewed, contains(first.id));
    expect(viewed, isNot(contains(second.id)));

    final newCandidates = await Repository.getCachedMediaCandidates(
      10, avoidWatchedContent: true,
      filters: const {MediaFilter.video},
      allowedHandles: null,
    );
    expect(newCandidates.map((v) => v.id), isNot(contains(first.id)));
    expect(newCandidates.map((v) => v.id), contains(second.id));
  });

  test('meaningfully watched but not marked played must also stay excluded',
      () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    final viewed = recommended('1900000000000008201', '#Sport');
    final fresh = recommended('1900000000000008202', '#Nature');
    await Repository.insertCachedMedia([viewed, fresh]);
    await Repository.recordMeaningfulVideoWatch(viewed);
    final candidates = await Repository.getCachedMediaCandidates(
      10, avoidWatchedContent: true,
      filters: const {MediaFilter.video},
      allowedHandles: null,
    );
    expect(candidates.map((v) => v.id), isNot(contains(viewed.id)));
    expect(candidates.map((v) => v.id), contains(fresh.id));
  });
}
