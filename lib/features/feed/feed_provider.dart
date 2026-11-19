import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/client/twitter_client.dart';
import '../../core/client/twitter_account.dart';
import '../../core/client/account_provider.dart';
import '../../core/client/public_x_client.dart';
import '../../core/models/tweet.dart';
import '../../core/database/repository.dart';
import '../../core/client/discovery_engine.dart';
import '../../core/utils/app_logger.dart';
import '../diagnostics/privacy_diagnostics.dart';
import '../settings/settings_provider.dart';
import '../subscriptions/subscription_list_screen.dart';
import 'local_video_filter.dart';
import 'similar_video_discovery.dart';
import 'local_recommendation_profile.dart';
import 'fresh_video_queue.dart';
import 'local_video_reactions_provider.dart';
import 'hashtag_provider.dart';
import 'hashtag_blacklist_provider.dart';
import '../../core/models/local_video_reaction.dart';
import '../player/player_pool_provider.dart';

final twitterClientProvider = Provider((ref) => TwitterClient());

class FeedState {
  final List<Tweet> tweets;
  final String? cursorBottom;
  final bool isLoadingMore;
  final bool isRefreshing;

  FeedState({
    required List<Tweet> tweets,
    this.cursorBottom,
    this.isLoadingMore = false,
    this.isRefreshing = false,
  }) : tweets = List<Tweet>.unmodifiable(
          tweets.where((tweet) => tweet.isVideo &&
              tweet.mediaUrls.isNotEmpty &&
              // Missing durations are verified before rendering the video.
              (tweet.durationMs == null || tweet.durationMs! > 15000)),
        );

  FeedState copyWith({
    List<Tweet>? tweets,
    String? cursorBottom,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return FeedState(
      tweets: tweets ?? this.tweets,
      cursorBottom: cursorBottom ?? this.cursorBottom,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

class FeedNotifier extends AsyncNotifier<FeedState> {
  static int _publicSubscriptionOffset = 0;
  final _discoveryCursorByTopic = <String, String?>{};
  final _discoveryFromPublic = <String, bool>{};
  final _discoverySeen = <String>{};
  int _topicRotation = 0;
  final _topicRetryAfter = <String, DateTime>{};
  bool _refreshInFlight = false;
  DateTime? _loadMoreRetryAfter;

  /// Read-only fallback when X does not return videos for followed accounts.
  /// FxEmbed never receives the user's X cookies or tokens.
  Future<TweetResponse> _fetchPublicSubscriptions(int maxVideos) async {
    final subscriptions = ref.read(subscriptionListProvider).allSubscriptions;
    if (subscriptions.isEmpty) return TweetResponse(tweets: []);
    final limit = subscriptions.length < 5 ? subscriptions.length : 5;
    final selected = [
      for (var i = 0; i < limit; i++)
        subscriptions[(_publicSubscriptionOffset + i) % subscriptions.length]
    ];
    _publicSubscriptionOffset =
        (_publicSubscriptionOffset + limit) % subscriptions.length;

    final publicClient = PublicXClient();
    final pages = await Future.wait(selected.map((sub) async {
      try {
        return await publicClient.userVideos(sub.screenName, count: 20);
      } catch (error) {
        AppLogger.log('Public videos unavailable for @${sub.screenName}: $error');
        return TweetResponse(tweets: []);
      }
    }));
    final unique = <String, Tweet>{};
    for (final page in pages) {
      for (final tweet in page.tweets) {
        unique.putIfAbsent(tweet.id, () => tweet);
      }
    }
    final videos = unique.values.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
    return TweetResponse(tweets: videos.take(maxVideos).toList());
  }

  /// Optional discovery: queries topics extracted from actual videos of
  /// locally saved creators. Recommendations never modify the local follow list.
  Future<List<Tweet>> _fetchRelatedVideos(
    List<Tweet> examples,
    Set<String> localHandles,
    TwitterClient client,
    Map<String, LocalVideoReaction> reactions,
    Iterable<String> followedHashtags,
    Set<String> blockedHashtags,
  ) async {
    // All four sources influence recommendations: explicit likes, videos
    // meaningfully watched, followed hashtags, and locally saved creators.
    // Watch history remains on-device; X only receives keyword searches.
    final watched = await Repository.getMeaningfullyWatchedVideos();
    if (!ref.mounted) return const [];
    final topics = personalizedVideoTopics(
      examples,
      reactions,
      limit: 4,
      followedHashtags: followedHashtags,
      watchedVideos: watched,
      blockedHashtags: blockedHashtags,
    );
    if (topics.isEmpty) return const [];
    final alreadySeen = await Repository.getViewedVideoIds();
    if (!ref.mounted) return const [];
    final accepted = <String, Tweet>{};
    final authed = TwitterAccount.hasAuthSession(ref.read(accountProvider));
    // Rotate which personal topic is queried first. Each topic keeps a
    // pagination cursor, so successive loads don't fetch page one forever.
    final rotated = [
      ...topics.skip(_topicRotation % topics.length),
      ...topics.take(_topicRotation % topics.length),
    ];
    _topicRotation++;
    for (final topic in rotated) {
      if (!ref.mounted) return const [];
      final retryAfter = _topicRetryAfter[topic];
      if (retryAfter != null && DateTime.now().isBefore(retryAfter)) continue;
      var usePublic = _discoveryFromPublic[topic] ?? !authed;
      var cursor = _discoveryCursorByTopic[topic];
      TweetResponse response = TweetResponse(tweets: []);
      if (!usePublic) {
        try {
          response = await client.fetchTrendingMedia(
            query: topic,
            cursor: cursor,
            sort: FeedSort.latest,
            count: 35,
            filters: const {MediaFilter.video},
            timeoutSeconds: 9,
            reportErrors: true,
          ).timeout(const Duration(seconds: 11));
        } catch (error) {
          AppLogger.log('Discovery X query failed for $topic: $error');
        }
        if (response.tweets.isEmpty) {
          usePublic = true;
          cursor = null;
          _discoveryFromPublic[topic] = true;
        }
      }
      if (usePublic) {
        try {
          response = await PublicXClient()
            .searchVideos(topic, cursor: cursor, count: 35)
            .timeout(const Duration(seconds: 12));
        } catch (error) {
          AppLogger.log('Discovery public query failed for $topic: $error');
          continue;
        }
      }
      final next = response.cursorBottom;
      // A known exhausted cursor must not cause the same page to be
      // fetched repeatedly in one feed session.
      final hasNext = next != null && next.isNotEmpty && next != cursor;
      _discoveryCursorByTopic[topic] = hasNext ? next : null;
      if (hasNext) {
        _topicRetryAfter.remove(topic);
      } else {
        _topicRetryAfter[topic] =
            DateTime.now().add(const Duration(minutes: 10));
      }
      for (final video in response.tweets) {
        final author = video.userHandle.replaceFirst('@', '').toLowerCase();
        if (!video.isVideo || video.mediaUrls.isEmpty ||
            (video.durationMs != null && video.durationMs! <= 15000) ||
            localHandles.contains(author) ||
            alreadySeen.contains(video.id) ||
            _discoverySeen.contains(video.id) ||
            excludedByFeedback(video, reactions,
                blockedHashtags: blockedHashtags)) continue;
        accepted.putIfAbsent(video.id,
            () => video.copyWith(source: 'Découverte'));
      }
      if (accepted.length >= 15) break;
    }
    _discoverySeen.addAll(accepted.keys);
    final chosen = accepted.values.take(15).toList();
    // Persist BEFORE exposing results. Otherwise markMediaAsPlayed updates
    // zero rows and recommended clips repeat on the next app launch.
    if (chosen.isNotEmpty) {
      try {
        await Repository.insertCachedMedia(chosen);
      } catch (error) {
        AppLogger.log('Could not persist discovered media: $error');
      }
    }
    return chosen;
  }

  // A bounded number of detailed X requests refreshes visible counters
  // without rate-limiting every vertical swipe.
  final Map<String, DateTime> _checkedEngagementAt = {};
  DateTime? _lastEngagementRequest;
  bool _engagementRequestPending = false;

  /// A cached count is a snapshot; refresh it when the video is viewed.
  Future<bool> refreshVisibleEngagement(String tweetId,
      {bool force = false}) async {
    if (TwitterAccount.currentAccount == null) return false;
    if (_engagementRequestPending) return false;
    final current = state.value;
    if (current == null ||
        !current.tweets.any((tweet) => tweet.id == tweetId)) {
      return false;
    }
    final now = DateTime.now();
    final previouslyChecked = _checkedEngagementAt[tweetId];
    if (!force &&
        previouslyChecked != null &&
        now.difference(previouslyChecked) < const Duration(minutes: 15)) {
      return false;
    }
    if (!force &&
        _lastEngagementRequest != null &&
        now.difference(_lastEngagementRequest!) < const Duration(seconds: 25)) {
      return false;
    }

    _engagementRequestPending = true;
    _lastEngagementRequest = now;
    _checkedEngagementAt[tweetId] = now;
    try {
      final response =
          await ref.read(twitterClientProvider).fetchTweetDetail(tweetId);
      Tweet? fresh;
      for (final candidate in response.tweets) {
        if (candidate.id == tweetId) {
          fresh = candidate;
          break;
        }
      }
      if (fresh == null ||
          (!fresh.favoriteCountKnown &&
              !fresh.replyCountKnown &&
              !fresh.isLikedKnown)) {
        return false;
      }

      final latest = state.value;
      if (latest == null) return false;
      final index = latest.tweets.indexWhere((tweet) => tweet.id == tweetId);
      if (index < 0) return false;
      final previous = latest.tweets[index];

      final merged = previous.copyWith(
        retrievedVia: fresh.retrievedVia,
        favoriteCount: fresh.favoriteCountKnown
            ? fresh.favoriteCount
            : previous.favoriteCount,
        replyCount: fresh.replyCountKnown
            ? fresh.replyCount
            : previous.replyCount,
        isLiked: fresh.isLikedKnown ? fresh.isLiked : previous.isLiked,
        favoriteCountKnown:
            previous.favoriteCountKnown || fresh.favoriteCountKnown,
        replyCountKnown: previous.replyCountKnown || fresh.replyCountKnown,
        isLikedKnown: previous.isLikedKnown || fresh.isLikedKnown,
      );
      final updated = List<Tweet>.from(latest.tweets);
      updated[index] = merged;
      state = AsyncData(latest.copyWith(tweets: updated));
      await Repository.insertCachedMedia([merged]);
      return true;
    } catch (e) {
      AppLogger.log('XFLOW: Could not refresh engagement for $tweetId: $e');
      return false;
    } finally {
      _engagementRequestPending = false;
    }
  }

  List<Tweet> _runDiscoveryPipeline(
    List<Tweet> freshPool,
    List<Tweet> localPool,
    SettingsState settings,
    Map<String, int> playedByUser, {
    int protectedIndex = 0,
    List<Tweet> currentTweets = const [],
  }) {
    final head = currentTweets.take(protectedIndex).toList();
    final headIds = head.map((t) => t.id).toSet();
    final headMedia = head
        .where((t) => t.mediaUrls.isNotEmpty)
        .map((t) => t.mediaUrls.first)
        .toSet();

    // Initialize seen sets using a sliding window of already visible tweets
    final dedupeWindow = currentTweets.length >
            settings.mediaDeduplicationWindow
        ? currentTweets
            .sublist(currentTweets.length - settings.mediaDeduplicationWindow)
        : currentTweets;

    final seenIds = {...headIds, ...dedupeWindow.map((t) => t.id)};
    final seenMediaUrls = {
      ...headMedia,
      ...dedupeWindow
          .where((t) => t.mediaUrls.isNotEmpty)
          .map((t) => t.mediaUrls.first)
    };

    List<Tweet> deduplicate(List<Tweet> pool) {
      return pool.where((t) {
        if (seenIds.contains(t.id)) return false;
        if (t.mediaUrls.isNotEmpty &&
            seenMediaUrls.contains(t.mediaUrls.first)) {
          return false;
        }
        seenIds.add(t.id);
        if (t.mediaUrls.isNotEmpty) seenMediaUrls.add(t.mediaUrls.first);
        return true;
      }).toList();
    }

    final uniqueFresh = deduplicate(freshPool)..shuffle();
    final uniqueLocal = deduplicate(localPool)..shuffle();

    final interleaved = DiscoveryEngine.interleave(
        uniqueFresh, uniqueLocal, settings.freshMixRatio);

    var processed = [...head, ...interleaved];

    if (settings.unseenSubscriptionBoost) {
      processed = DiscoveryEngine.applyUnseenSubscriptionBoost(
        processed,
        playedByUser,
        lookahead: settings.unseenBoostLookahead,
        startIndex: head.length,
      );
    }

    processed = DiscoveryEngine.applySaturation(
      processed,
      threshold: settings.saturationThreshold,
      mediaThreshold: settings.mediaSaturationThreshold,
      windowSize: settings.saturationWindow,
      startIndex: head.length,
      maxSaturationSwaps: settings.maxSaturationSwaps,
      maxPasses: settings.maxSaturationPasses,
    );

    return processed;
  }

  @override
  FutureOr<FeedState> build() async {
    final settings = ref.watch(settingsProvider);
    if (!settings.isInitialized) {
      return FeedState(tweets: [], isRefreshing: true);
    }
    // Do not rebuild the entire asynchronous feed when tapping like/dislike:
    // it previously displayed a loading spinner and interrupted playback.
    final reactions = ref.read(localVideoReactionsProvider).value ??
        const <String, LocalVideoReaction>{};
    final blockedHashtags = ref.watch(hashtagBlacklistProvider).value
        ?.toSet() ?? const <String>{};
    ref.watch(hashtagListProvider);
    // Ignore subscriptions loading flags, search, sort and view counters.
    // Only a change in the normalized local handles rebuilds the feed.
    ref.watch(subscriptionListProvider.select((current) =>
        (current.allSubscriptions
          .map((sub) => sub.screenName.replaceFirst('@', '').toLowerCase())
          .toList()..sort()).join('|')));
    final subscriptions = ref.read(subscriptionListProvider);
    ref.watch(accountProvider);
    final allowedHandles = localVideoHandles(subscriptions.allSubscriptions);
    // A user with likes, hashtags or watched videos can discover videos even
    // before following any creators. Empty subscription sets skip API sync.
    debugPrint(
        'XFLOW: Building FeedNotifier. fetchStrategy: ${settings.fetchStrategy}');

    try {
      // Stage 1: Immediate local candidate retrieval
      final localTagged = await _getLocalCandidates(
          settings, allowedHandles, reactions, blockedHashtags);
      AppLogger.log(
          'XFLOW: Cold start: Retrieved ${localPool.length} local candidates');

      // EARLY MEDIA WARMUP
      if (localTagged.isNotEmpty) {
        final pool = ref.read(playerPoolProvider.notifier);
        for (int i = 0; i < localTagged.length && i < 2; i++) {
          final tweet = localTagged[i];
          if (tweet.isVideo && tweet.mediaUrls.isNotEmpty) {
            pool.warmup(tweet.id, tweet.mediaUrls.first);
          }
        }
      }

      // TRIGGER BACKGROUND SYNC
      Future<void>.delayed(Duration.zero, _refreshInBackground);

      PrivacyDiagnostics.instance.record(
          DiagnosticEvent.feedInitialLoad, resultCount: localTagged.length);
      return FeedState(
        tweets: localTagged,
        cursorBottom: null,
        isRefreshing: localTagged.isEmpty,
      );
    } catch (e, st) {
      debugPrint('XFLOW: Error in build(): $e\n$st');
      return FeedState(tweets: [], isRefreshing: false);
    }
  }

  /// Personal cache fallback when no creator is locally followed.
  Future<List<Tweet>> _getLocalCandidates(
    SettingsState settings,
    Set<String> allowedHandles,
    Map<String, LocalVideoReaction> reactions,
    Set<String> blockedHashtags,
  ) async {
    final pool = await Repository.getCachedMediaCandidates(
      settings.loadBatchSize * settings.dbCandidateMultiplier,
      avoidWatchedContent: true,
      filters: const {MediaFilter.video},
      allowedHandles: allowedHandles.isEmpty ? null : allowedHandles,
    );
    Iterable<Tweet> selected;
    if (allowedHandles.isEmpty) {
      final topics = personalizedVideoTopics(
        const <Tweet>[], reactions, limit: 12,
        followedHashtags:
            ref.read(hashtagListProvider).value ?? const <String>[],
        watchedVideos: await Repository.getMeaningfullyWatchedVideos(),
        blockedHashtags: blockedHashtags,
      );
      selected = cachedVideosMatchingTopics(pool, topics);
    } else {
      selected = onlyLocalSubscriptionVideos(pool, allowedHandles);
    }
    return filterByFeedback(selected, reactions,
        blockedHashtags: blockedHashtags)
        .map((video) => video.copyWith(source: 'Cache')).toList();
  }

  Future<void> refresh() async {
    final currentState = state.value;
    if (currentState == null || _refreshInFlight) return;
    state = AsyncData(currentState.copyWith(isRefreshing: true));
    await _refreshInBackground(resetHead: true);
  }

  Future<void> _refreshInBackground({bool resetHead = false}) async {
    if (_refreshInFlight || !ref.mounted) {
      PrivacyDiagnostics.instance.record(
          DiagnosticEvent.feedRefreshCoalesced);
      return;
    }
    _refreshInFlight = true;
    PrivacyDiagnostics.instance.record(DiagnosticEvent.feedRefreshStarted);
    try {
      await _performBackgroundRefresh(resetHead: resetHead);
    } catch (error) {
      AppLogger.log('Background refresh could not start: $error');
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedLoadFailed);
    } finally {
      _refreshInFlight = false;
      if (ref.mounted) {
        final current = state.value;
        if (current != null && current.isRefreshing) {
          state = AsyncData(current.copyWith(isRefreshing: false));
        }
      }
    }
  }

  Future<void> _performBackgroundRefresh({bool resetHead = false}) async {
    if (!ref.mounted) return;

    final client = ref.read(twitterClientProvider);
    final settings = ref.read(settingsProvider);
    final reactions = ref.read(localVideoReactionsProvider).value ??
        const <String, LocalVideoReaction>{};
    final blockedHashtags = ref.read(hashtagBlacklistProvider).value
        ?.toSet() ?? const <String>{};
    final followedHashtags =
        ref.read(hashtagListProvider).value ?? const <String>[];
    final allowedHandles = localVideoHandles(
        ref.read(subscriptionListProvider).allSubscriptions);
    final viewedIds = await Repository.getViewedVideoIds();
    if (!ref.mounted) return;
    // Discover in parallel with creator API requests, rather than forcing
    // an empty initial feed to wait for both network paths serially.
    final beforeDiscovery = state.value?.tweets ?? const <Tweet>[];
    final discoveryFuture = settings.suggestSimilarVideos
        ? _fetchRelatedVideos(
            beforeDiscovery, allowedHandles, client, reactions,
            followedHashtags, blockedHashtags)
        : Future<List<Tweet>>.value(const <Tweet>[]);
    debugPrint('XFLOW: Background refresh started');

    try {
      // 1. Fetch from API
      // Do not use For You, Following or global trending as home sources.
      // Only author handles explicitly saved inside Twitter vidéo qualify.
      TweetResponse freshResponse = allowedHandles.isEmpty
          ? TweetResponse(tweets: [])
          : await client.fetchSubscribedMedia(
              sort: settings.fetchStrategy == FeedSort.popular
                  ? FeedSort.popular
                  : FeedSort.latest,
              filters: const {MediaFilter.video},
              subBatchSize: settings.syncBatchSize,
              loadBatchSize: settings.initialSyncCount,
              cooldownMinutes: settings.cooldownDuration,
              strictSubscriptionsOnly: true,
              includeNativeRetweets: false,
              useChunkedSubscriptions: settings.useChunkedSubscriptions,
              minFaves: settings.minFavesFilter,
            );

      if (allowedHandles.isNotEmpty && freshResponse.tweets.isEmpty) {
        final publicResponse =
            await _fetchPublicSubscriptions(settings.initialSyncCount);
        if (publicResponse.tweets.isNotEmpty) freshResponse = publicResponse;
      }

      if (!ref.mounted) return;
      final freshPool = filterByFeedback(
          onlyLocalSubscriptionVideos(freshResponse.tweets, allowedHandles)
              .where((video) => !viewedIds.contains(video.id)),
          reactions, blockedHashtags: blockedHashtags);
      final freshTagged = freshPool
          .map((t) => t.copyWith(source: 'API'))
          .toList();

      debugPrint(
          'XFLOW: Background refresh returned ${freshPool.length} fresh tweets');

      if (freshPool.isNotEmpty) {
        await Repository.insertCachedMedia(freshPool);
      }

      // 2. Fetch local pool (now including fresh items)
      final localTagged = await _getLocalCandidates(
          settings, allowedHandles, reactions, blockedHashtags);

      // Display a first useful batch immediately, even while the secondary
      // recommendation query is still in flight. Never replace played pages.
      final ready = ref.read(feedNotifierProvider).value;
      if (ref.mounted && ready != null && ready.tweets.isEmpty) {
        final early = appendFreshVideos(
          const <Tweet>[], [...freshTagged, ...localTagged],
          viewedIds: viewedIds,
        );
        if (early.isNotEmpty) {
          state = AsyncData(ready.copyWith(
              tweets: early, isRefreshing: true));
        }
      }

      final currentAsync = ref.read(feedNotifierProvider);
      if (currentAsync.hasValue) {
        final current = currentAsync.value!;

        final playedByUser = settings.unseenSubscriptionBoost
            ? await Repository.getPlayedCountsByUser()
            : const <String, int>{};

        // PROTECT THE ACTIVE VIDEO: If user is at index 0, protect index 0 from being swapped.
        // We protect up to 2 items to ensure the "next" item also doesn't jump unexpectedly.
        final processed = _runDiscoveryPipeline(
          freshTagged,
          localTagged,
          settings,
          playedByUser,
          protectedIndex: resetHead ? 0 : current.tweets.length,
          currentTweets: resetHead ? [] :
              filterByFeedback(current.tweets, reactions,
                  blockedHashtags: blockedHashtags),
        );

        var related = await discoveryFuture;
        if (related.isEmpty && settings.suggestSimilarVideos &&
            [...freshTagged, ...localTagged].isNotEmpty) {
          related = await _fetchRelatedVideos(
              [...freshTagged, ...localTagged], allowedHandles, client,
              reactions, followedHashtags, blockedHashtags);
        }
        if (!ref.mounted) return;
        // Read the latest state: dislike and swipe may have happened while
        // network requests ran. Never resurrect rejected clips or reorder
        // a page the user is currently watching.
        final latest = ref.read(feedNotifierProvider).value ?? current;
        final latestReactions =
            ref.read(localVideoReactionsProvider).value ?? reactions;
        final base = resetHead ? <Tweet>[] : filterByFeedback(
            latest.tweets, latestReactions,
            blockedHashtags: blockedHashtags);
        final baseIds = base.map((video) => video.id).toSet();
        final newSubscriptions =
            processed.where((video) => !baseIds.contains(video.id)).toList();
        final tail = mixRelatedVideos(newSubscriptions, related);
        final allowedTail = filterByFeedback(tail, latestReactions,
            blockedHashtags: blockedHashtags);
        final merged = appendFreshVideos(base, allowedTail,
            viewedIds: viewedIds);
        // If a manual refresh finds nothing new, don't throw away a
        // perfectly playable current video.
        final mixed = resetHead && merged.isEmpty
            ? filterByFeedback(latest.tweets, latestReactions,
                blockedHashtags: blockedHashtags)
            : merged;
        state = AsyncData(latest.copyWith(
          tweets: mixed,
          cursorBottom: freshResponse.cursorBottom,
          isRefreshing: false,
        ));
        final addedCount = mixed.length - base.length;
        PrivacyDiagnostics.instance.record(
            DiagnosticEvent.feedRefreshCompleted, resultCount: addedCount);
        if (addedCount <= 0) {
          PrivacyDiagnostics.instance.record(
              DiagnosticEvent.feedNoFreshCandidates);
        }
        debugPrint(
            'XFLOW: Feed state updated from background refresh. Total: ${processed.length}');
      }
    } catch (e) {
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedLoadFailed);
      debugPrint('XFLOW: Background refresh error: $e');
      final currentAsync = ref.read(feedNotifierProvider);
      if (currentAsync.hasValue) {
        state = AsyncData(currentAsync.value!.copyWith(isRefreshing: false));
      }
    }
  }

  Future<void> fetchMore() async {
    final currentState = state.value;
    if (currentState == null || currentState.isLoadingMore ||
        _refreshInFlight) return;
    final retryAfter = _loadMoreRetryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedLoadCooldown);
      return;
    }
    PrivacyDiagnostics.instance.record(DiagnosticEvent.feedLoadMoreStarted);

    final settings = ref.read(settingsProvider);
    final reactions = ref.read(localVideoReactionsProvider).value ??
        const <String, LocalVideoReaction>{};
    final blockedHashtags = ref.read(hashtagBlacklistProvider).value
        ?.toSet() ?? const <String>{};
    final followedHashtags =
        ref.read(hashtagListProvider).value ?? const <String>[];
    final allowedHandles = localVideoHandles(
        ref.read(subscriptionListProvider).allSubscriptions);
    if (allowedHandles.isEmpty) {
      state = AsyncData(currentState.copyWith(isLoadingMore: true));
      try {
        final suggestions = settings.suggestSimilarVideos
            ? await _fetchRelatedVideos(const [], allowedHandles,
                ref.read(twitterClientProvider), reactions, followedHashtags,
                blockedHashtags)
            : <Tweet>[];
        if (!ref.mounted) return;
        final latest = state.value ?? currentState;
        final latestReactions =
            ref.read(localVideoReactionsProvider).value ?? reactions;
        final eligible = filterByFeedback(suggestions, latestReactions,
            blockedHashtags: blockedHashtags);
        final merged = appendFreshVideos(latest.tweets, eligible,
            viewedIds: await Repository.getViewedVideoIds());
        if (!ref.mounted) return;
        final added = merged.length - latest.tweets.length;
        state = AsyncData(latest.copyWith(
            tweets: merged, isLoadingMore: false));
        _reportLoadResult(added);
      } catch (error) {
        PrivacyDiagnostics.instance.record(DiagnosticEvent.feedLoadFailed);
        AppLogger.log('Personalized load-more failed: $error');
        if (ref.mounted) {
          final latest = state.value;
          if (latest != null) {
            state = AsyncData(latest.copyWith(isLoadingMore: false));
          }
        }
      }
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final previouslyViewed = await Repository.getViewedVideoIds();
      if (!ref.mounted) return;
      // Request genuinely new recommendations first, before long and often
      // exhausted subscription/API retry loops. This makes scroll-to-next
      // responsive and prevents cache-only recycling.
      if (settings.suggestSimilarVideos) {
        final initialSuggestions = await _fetchRelatedVideos(
          onlyLocalSubscriptionVideos(currentState.tweets, allowedHandles),
          allowedHandles,
          ref.read(twitterClientProvider),
          reactions,
          followedHashtags,
          blockedHashtags,
        );
        if (!ref.mounted) return;
        final present = currentState.tweets.map((t) => t.id).toSet();
        final firstFresh = initialSuggestions
            .where((t) => present.add(t.id))
            .take(settings.loadBatchSize).toList();
        if (firstFresh.length >= 3) {
          final latest = state.value ?? currentState;
          final liveReactions =
              ref.read(localVideoReactionsProvider).value ?? reactions;
          final allowed = filterByFeedback(firstFresh, liveReactions,
              blockedHashtags: blockedHashtags);
          final combined = appendFreshVideos(latest.tweets, allowed,
              viewedIds: previouslyViewed);
          state = AsyncData(latest.copyWith(
            tweets: combined,
            isLoadingMore: false,
          ));
          _reportLoadResult(combined.length - latest.tweets.length);
          return;
        }
      }
      final seenIds = state.value!.tweets.map((t) => t.id).toSet();

      // Use dynamic deduplication window from settings
      final dedupeWindow = state.value!.tweets.length >
              settings.mediaDeduplicationWindow
          ? state.value!.tweets.sublist(
              state.value!.tweets.length - settings.mediaDeduplicationWindow)
          : state.value!.tweets;

      final seenMedia = dedupeWindow
          .where((t) => t.mediaUrls.isNotEmpty)
          .map((t) => t.mediaUrls.first)
          .toSet();

      List<Tweet> allNewTweets = [];
      String? currentCursor = state.value!.cursorBottom;
      final seenCursors = <String>{};
      bool publicFallbackAttempted = false;
      int apiRetries = 0;
      int chunkRotations = 0;
      final maxRetries = settings.apiRetryLimit.clamp(1, 3);

      while (allNewTweets.length < settings.minNewTweetsThreshold &&
          apiRetries < maxRetries &&
          chunkRotations < settings.chunkRotationLimit) {
        // 1. Try to fetch from DB first (refresh pool)
        final dbCandidates = await Repository.getCachedMediaCandidates(
          settings.loadBatchSize * settings.dbCandidateMultiplier,
          avoidWatchedContent: true,
          filters: settings.filters,
          allowedHandles: allowedHandles,
        );

        var localNew = filterByFeedback(
          onlyLocalSubscriptionVideos(dbCandidates, allowedHandles),
          reactions, blockedHashtags: blockedHashtags,
        ).where((t) {
          if (!t.isVideo || t.mediaUrls.isEmpty) return false;
          return !seenIds.contains(t.id) &&
              !previouslyViewed.contains(t.id) &&
              (t.mediaUrls.isEmpty || !seenMedia.contains(t.mediaUrls.first));
        }).toList();

        if (localNew.isNotEmpty) {
          allNewTweets.addAll(
              localNew.where((tweet) => seenIds.add(tweet.id)));
          if (allNewTweets.length >= settings.minNewTweetsThreshold) break;
        }

        // 2. Hit the API
        final client = ref.read(twitterClientProvider);
        if (currentCursor != null) seenCursors.add(currentCursor);

        try {
          final TweetResponse response = await client.fetchSubscribedMedia(
            cursor: currentCursor,
            sort: settings.fetchStrategy == FeedSort.popular
                ? FeedSort.popular
                : FeedSort.latest,
            filters: const {MediaFilter.video},
            subBatchSize: settings.syncBatchSize,
            loadBatchSize: settings.loadBatchSize,
            cooldownMinutes: settings.cooldownDuration,
            strictSubscriptionsOnly: true,
            includeNativeRetweets: false,
            useChunkedSubscriptions: settings.useChunkedSubscriptions,
            minFaves: settings.minFavesFilter,
            maxQueryLength: settings.maxQueryLength,
            timeoutSeconds: settings.apiTimeoutSeconds.clamp(5, 12),
          ).timeout(const Duration(seconds: 14));

          // Once per load-more action, try public videos when native X
          // returns none. Do not loop on the public service indefinitely.
          TweetResponse effectiveResponse = response;
          if (response.tweets.isEmpty && !publicFallbackAttempted) {
            publicFallbackAttempted = true;
            final publicResponse =
                await _fetchPublicSubscriptions(settings.loadBatchSize);
            if (publicResponse.tweets.isNotEmpty) {
              effectiveResponse = publicResponse;
            }
          }

          final localFresh = filterByFeedback(
              onlyLocalSubscriptionVideos(effectiveResponse.tweets,
                  allowedHandles), reactions, blockedHashtags: blockedHashtags);
          final freshUnique = localFresh.where((t) {
            if (!t.isVideo || t.mediaUrls.isEmpty) return false;
            return !seenIds.contains(t.id) &&
                !previouslyViewed.contains(t.id) &&
                (t.mediaUrls.isEmpty || !seenMedia.contains(t.mediaUrls.first));
          }).toList();

          if (localFresh.isNotEmpty) {
            await Repository.insertCachedMedia(localFresh);
          }

          allNewTweets.addAll(
              freshUnique.where((tweet) => seenIds.add(tweet.id)));
          apiRetries++;

          // Handle Pagination vs Rotation
          if (response.cursorBottom != null &&
              response.cursorBottom != currentCursor &&
              !seenCursors.contains(response.cursorBottom!)) {
            currentCursor = response.cursorBottom;
          } else {
            // Chunk exhausted or stuck cursor
            AppLogger.log(
                'XFLOW: Chunk exhausted or stuck cursor. Rotating to next subscription chunk.');
            currentCursor = null;
            chunkRotations++;
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e) {
          AppLogger.log('XFLOW: fetchMore API error: $e');
          apiRetries++;
          await Future.delayed(const Duration(seconds: 1));
        }

        if (allNewTweets.length < settings.minNewTweetsThreshold) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // Even if the subscriptions are exhausted, still search for new
      // discoveries via likes, watched videos and followed hashtags.

      // Shuffle candidates BEFORE taking the batch to improve diversity
      allNewTweets.shuffle();

      final finalNewTweets = filterByFeedback(
          allNewTweets, reactions, blockedHashtags: blockedHashtags)
          .take(settings.loadBatchSize)
          .map((t) => t.copyWith(source: t.source ?? 'Mixed'))
          .toList();

      final related = settings.suggestSimilarVideos
          ? await _fetchRelatedVideos(
              onlyLocalSubscriptionVideos(
                [...state.value!.tweets, ...finalNewTweets], allowedHandles),
              allowedHandles,
              ref.read(twitterClientProvider),
              reactions,
              followedHashtags,
              blockedHashtags,
            )
          : <Tweet>[];
      if (!ref.mounted) return;
      final newIds = <String>{...seenIds, ...finalNewTweets.map((e) => e.id)};
      final unseenRelated = related.where((video) =>
          !newIds.contains(video.id) &&
          !previouslyViewed.contains(video.id)).toList();
      final mixedNew = mixRelatedVideos(finalNewTweets, unseenRelated);
      // A dislike may have removed an item during an awaited API call.
      // Build on the LATEST state; never re-insert the rejected video.
      final latest = state.value ?? currentState;
      final latestReactions =
          ref.read(localVideoReactionsProvider).value ?? reactions;
      final currentAllowed = filterByFeedback(latest.tweets,
          latestReactions, blockedHashtags: blockedHashtags);
      final freshAllowed = filterByFeedback(mixedNew, latestReactions,
          blockedHashtags: blockedHashtags);
      var combined = appendFreshVideos(currentAllowed, freshAllowed,
          viewedIds: previouslyViewed);

      // Diversity applies to the new tail only, not the playing pages.
      combined = DiscoveryEngine.applySaturation(
        combined,
        threshold: settings.saturationThreshold,
        mediaThreshold: settings.mediaSaturationThreshold,
        windowSize: settings.saturationWindow,
        startIndex: currentAllowed.length,
        maxSaturationSwaps: settings.maxSaturationSwaps,
        maxPasses: settings.maxSaturationPasses,
      );

      state = AsyncData(latest.copyWith(
        tweets: combined,
        cursorBottom: currentCursor,
        isLoadingMore: false,
      ));
      final addedCount = combined.length - currentAllowed.length;
      _reportLoadResult(addedCount);
      debugPrint(
          'XFLOW: fetchMore complete. Added ${finalNewTweets.length} tweets. Total: ${combined.length}');
    } catch (e, st) {
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedLoadFailed);
      debugPrint('Error fetching more: $e\n$st');
      if (ref.mounted) {
        final latest = state.value;
        if (latest != null) {
          state = AsyncData(latest.copyWith(isLoadingMore: false));
        }
      }
    }
  }

  void _reportLoadResult(int added) {
    if (added <= 0) {
      _loadMoreRetryAfter = DateTime.now()
          .add(const Duration(seconds: 25));
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedLoadEmpty,
          resultCount: 0);
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedNoFreshCandidates);
    } else {
      _loadMoreRetryAfter = null;
      PrivacyDiagnostics.instance.record(
          DiagnosticEvent.feedLoadMoreCompleted, resultCount: added);
    }
  }

  /// Remove a rejected video immediately, without restarting the async feed.
  /// PageView continues at its current index, showing the next clip.
  void hideDislikedVideo(String id) {
    final current = state.value;
    if (current == null) return;
    final filtered = current.tweets.where((tweet) => tweet.id != id).toList();
    if (filtered.length == current.tweets.length) return;
    state = AsyncData(current.copyWith(tweets: filtered));
  }

}

final feedNotifierProvider =
    AsyncNotifierProvider.autoDispose<FeedNotifier, FeedState>(
        FeedNotifier.new);
