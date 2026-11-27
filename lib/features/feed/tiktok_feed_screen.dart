import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../player/player_pool_provider.dart';
import 'persistent_fullscreen_provider.dart';
import 'feed_provider.dart';
import 'fresh_video_queue.dart';
import '../player/widgets/media_container.dart';
import '../../core/models/tweet.dart';
import '../../core/database/repository.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_provider.dart';
import '../auth/login_screen.dart';
import '../../core/client/account_provider.dart';
import '../../core/navigation/navigation_provider.dart';
import 'widgets/tweet_text_overlay.dart';
import '../cast/cast_video_button.dart';
import '../subscriptions/subscription_list_screen.dart';
import 'local_video_filter.dart';
import '../player/video_ui_provider.dart';
import '../diagnostics/privacy_diagnostics.dart';

class TiktokFeedScreen extends ConsumerStatefulWidget {
  const TiktokFeedScreen({super.key});

  @override
  ConsumerState<TiktokFeedScreen> createState() => _TiktokFeedScreenState();
}

class _TiktokFeedScreenState extends ConsumerState<TiktokFeedScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _poolUpdateScheduled = false;
  String? _lastMarkedVideoId;
  static const int _reserveTarget = 30;
  Timer? _reserveTimer;
  Timer? _advanceTimer;
  String? _pendingAdvanceId;
  int _lastReserve = -1;

  @override
  void initState() {
    super.initState();
    _reserveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _maintainReserve();
    });
  }

  bool _feedActive() {
    final nav = ref.read(navigationProvider);
    return nav.currentTab == MainTab.media && !nav.isVideoSearchOpen &&
        nav.selectedUser == null && nav.selectedHashtag == null;
  }

  void _maintainReserve() {
    if (!mounted || !_feedActive()) return;
    final feed = ref.read(feedNotifierProvider).value;
    if (feed == null) return;
    final remaining = (feed.tweets.length - _currentIndex - 1).clamp(0, feed.tweets.length).toInt();
    if (remaining != _lastReserve) {
      _lastReserve = remaining;
      if (remaining == 0) PrivacyDiagnostics.instance.record(DiagnosticEvent.feedReserveEmpty);
      final tail = feed.tweets.skip(_currentIndex + 1).take(20).toList();
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedDistinctAuthors,
          resultCount: tail.map((v) => v.userHandle.toLowerCase()).toSet().length);
      PrivacyDiagnostics.instance.record(DiagnosticEvent.feedReserveSample,
          resultCount: remaining);
    }
    final pending = _pendingAdvanceId;
    if (pending != null && _currentIndex < feed.tweets.length &&
        feed.tweets[_currentIndex].id == pending && remaining > 0 &&
        _pageController.hasClients) {
      _pendingAdvanceId = null;
      _pageController.jumpToPage(_currentIndex + 1);
      return;
    }
    if (!feed.isRefreshing && !feed.isLoadingMore && remaining < _reserveTarget) {
      unawaited(ref.read(feedNotifierProvider.notifier).fetchMore());
    }
  }

  void _requestAdvance(String id, int delaySeconds) {
    if (_advanceTimer?.isActive == true || _pendingAdvanceId == id) return;
    _advanceTimer = Timer(Duration(seconds: delaySeconds.clamp(0, 2).toInt()), () {
      if (!mounted || !_feedActive()) return;
      final tweets = ref.read(feedNotifierProvider).value?.tweets ?? const <Tweet>[];
      if (_currentIndex >= tweets.length || tweets[_currentIndex].id != id) return;
      if (_currentIndex + 1 < tweets.length && _pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex + 1);
      } else {
        _pendingAdvanceId = id;
        PrivacyDiagnostics.instance.record(DiagnosticEvent.videoAdvanceWaitingForReserve);
        _maintainReserve();
      }
    });
  }

  @override
  void dispose() {
    _reserveTimer?.cancel();
    _advanceTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    if (page != _currentIndex) {
      _advanceTimer?.cancel();
      _pendingAdvanceId = null;
      PrivacyDiagnostics.instance.record(DiagnosticEvent.videoAdvanced);
      setState(() {
        _currentIndex = page;
      });
      ref.read(videoUiHiddenProvider.notifier).show();
      _managePool();

      final feedAsync = ref.read(feedNotifierProvider);
      if (feedAsync.hasValue) {
        final tweets = feedAsync.value!.tweets;

        if (page < tweets.length) {
          ref.read(activeCastTweetProvider.notifier).selectFromPhone(tweets[page], tweets);
          final id = tweets[page].id;
          if (_lastMarkedVideoId != id) {
            _lastMarkedVideoId = id;
            unawaited(Repository.markMediaAsPlayed(id, video: tweets[page]));
          }
        }

        _maintainReserve();
      }
    }
  }

  void _managePool() {
    try {
      final feedAsync = ref.read(feedNotifierProvider);
      final state = feedAsync.value;
      if (state == null) return;
      final tweets = state.tweets;

      final pool = ref.read(playerPoolProvider.notifier);
      final activeIds = <String>{};

      for (int i = _currentIndex; i <= _currentIndex + 3; i++) {
        if (i >= 0 && i < tweets.length) {
          final tweet = tweets[i];
          activeIds.add(tweet.id);

          if (tweet.isVideo && tweet.mediaUrls.isNotEmpty) {
            pool.warmup(tweet.id, tweet.mediaUrls.first);
          }
        }
      }
      pool.cleanupExcept(activeIds);
    } catch (e) {
      debugPrint('XFLOW: Error in _managePool: $e');
    }
  }

  // Warm up outside of widget construction to avoid update loops.
  void _schedulePoolWarmup() {
    if (_poolUpdateScheduled) return;
    _poolUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _poolUpdateScheduled = false;
      if (mounted) {
        if (!_feedActive()) return;
        _managePool();
        final tweets = ref.read(feedNotifierProvider).value?.tweets;
        if (tweets != null && _currentIndex < tweets.length) {
          ref.read(castPlaylistProvider.notifier).setQueue(tweets);
          // The first video counts as viewed too; it was never marked when
          // the user opened the app without swiping.
          final visibleId = tweets[_currentIndex].id;
          if (_lastMarkedVideoId != visibleId) {
            _lastMarkedVideoId = visibleId;
            unawaited(Repository.markMediaAsPlayed(visibleId,
                video: tweets[_currentIndex]));
          }
          // One throttled detail request for the visible video, not for the
          // whole feed. Never block rendering or playback.
          unawaited(ref.read(feedNotifierProvider.notifier)
              .refreshVisibleEngagement(tweets[_currentIndex].id));
          // Refill from the periodic timer or page change, not every rebuild.

        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // A local follow/unfollow changes the eligible creators immediately.
    ref.listen(subscriptionListProvider, (previous, next) {
      final oldHandles = localVideoHandles(
          previous?.allSubscriptions ?? const []);
      final newHandles = localVideoHandles(next.allSubscriptions);
      if (oldHandles.length == newHandles.length &&
          oldHandles.containsAll(newHandles)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients) _pageController.jumpToPage(0);
        setState(() => _currentIndex = 0);
      });
    });
    // Keep the phone's current item aligned when the television advances.
    ref.listen(activeCastTweetProvider, (previous, next) {
      if (next == null || previous == next) return;
      if (!_feedActive()) return;
      final items = ref.read(feedNotifierProvider).value?.tweets ?? const <Tweet>[];
      final index = items.indexWhere((item) => item.id == next);
      if (index < 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(index);
        setState(() => _currentIndex = index);
        PrivacyDiagnostics.instance.record(DiagnosticEvent.castPhoneAligned);
      });
    });
    final account = ref.watch(accountProvider);
    final videoUiHidden = ref.watch(videoUiHiddenProvider);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final immersive = ref.watch(persistentFullscreenProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildMediaFeed()),
          if (!videoUiHidden && !landscape && !immersive)
            Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
                child: Row(
                  children: [
                    // The selected X session replaces the app branding.
                    // The active session (used for likes/API calls) is not
                    // necessarily the account that originally fetched a video.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                          message: account == null
                              ? 'Aucun compte X sélectionné'
                              : 'Compte X actif : @${account.screenName.replaceFirst('@', '')}. '
                                  'Les J’aime restent uniquement dans Twitter vidéo.',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xEB142621),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                  color: const Color(0xFF70F0CE)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.account_circle_rounded,
                                    color: Color(0xFF70F0CE), size: 19),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    account == null
                                        ? 'Sans compte X'
                                        : 'Session X : @${account.screenName.replaceFirst('@', '')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rechercher des vidéos',
                      onPressed: () => ref.read(navigationProvider.notifier).openVideoSearch(),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    if (account == null)
                      IconButton.filledTonal(
                        tooltip: 'Connexion X',
                        onPressed: _goToLogin,
                        icon: const Icon(Icons.login_rounded),
                      ),
                    IconButton(
                      tooltip: 'Actualiser',
                      onPressed: () {
                        _advanceTimer?.cancel();
                        _pendingAdvanceId = null;
                        if (_pageController.hasClients) _pageController.jumpToPage(0);
                        ref.read(feedNotifierProvider.notifier).refresh();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: 'Réglages',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaFeed() {
    final feedAsync = ref.watch(feedNotifierProvider);
    final nav = ref.watch(navigationProvider);
    final isScreenActive = !nav.isVideoSearchOpen &&
        nav.selectedUser == null &&
        nav.selectedHashtag == null &&
        nav.currentTab == MainTab.media;

    return feedAsync.when(
      data: (state) {
        final tweets = state.tweets;
        if (tweets.isEmpty) {
          if (state.isRefreshing || state.isLoadingMore) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Recherche de nouvelles vidéos…',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            );
          }
          return _buildNoItemsState();
        }
        _schedulePoolWarmup();
        return Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: tweets.length,
              itemBuilder: (context, index) {
                final settings = ref.read(settingsProvider);
                return TiktokFeedItem(
                  key: ValueKey('video_${tweets[index].id}'),
                  requireLongVideo: true,
                  tweet: tweets[index],
                  isVisible: index == _currentIndex && isScreenActive,
                  onDislike: () {
                    if (!mounted || index != _currentIndex) return;
                    _advanceTimer?.cancel();
                    _pendingAdvanceId = null;
                    final rejectedId = tweets[index].id;
                    PrivacyDiagnostics.instance.record(
                        DiagnosticEvent.dislikeAdvanceRequested);
                    ref.read(feedNotifierProvider.notifier)
                        .hideDislikedVideo(rejectedId);
                    final after = ref.read(feedNotifierProvider)
                        .value?.tweets ?? const <Tweet>[];
                    if (after.isEmpty) {
                      setState(() => _currentIndex = 0);
                    } else if (index >= after.length) {
                      // Last item removed: clamp to a valid page.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted || !_pageController.hasClients) return;
                        _pageController.jumpToPage(after.length - 1);
                        setState(() => _currentIndex = after.length - 1);
                        _managePool();
                      });
                    } else {
                      // Same page index now holds a different video.
                      setState(() {});
                      _schedulePoolWarmup();
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final current = ref.read(feedNotifierProvider)
                          .value?.tweets ?? const <Tweet>[];
                      final advanced = dislikeAdvancedToAnotherVideo(
                          tweets, current, rejectedId, index);
                      PrivacyDiagnostics.instance.record(advanced
                          ? DiagnosticEvent.dislikeAdvanceConfirmed
                          : DiagnosticEvent.dislikeAdvanceNoNext);
                    });
                    if (index < after.length) {
                      ref.read(activeCastTweetProvider.notifier).selectFromPhone(after[index], after);
                    }
                    _maintainReserve();
                  },
                  onPlaybackError: () {
                    if (index == _currentIndex && mounted) {
                      _requestAdvance(tweets[index].id, settings.autoSkipDelaySeconds);
                    }
                  },
                );
              },
            ),
            if (state.isRefreshing)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _buildErrorState(e),
    );
  }

  Widget _buildNoItemsState() {
    final emptyList =
        ref.watch(subscriptionListProvider).allSubscriptions.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emptyList
                  ? 'Ajoute des hashtags, aime des vidéos ou suis des comptes '
                       'pour personnaliser ton fil. Seules les vidéos de '
                       'plus de 15 secondes apparaissent.'
                  : 'Aucune vidéo de plus de 15 secondes disponible '
                       'pour tes centres d’intérêt.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                unawaited(ref.read(feedNotifierProvider.notifier).refresh());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Chercher de nouvelles vidéos'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => ref.read(navigationProvider.notifier)
                  .setTab(MainTab.subscriptions),
              child: const Text('Gérer mes abonnements'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object e) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Error: $e',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _goToLogin(),
            child: const Text('Login to X'),
          ),
          TextButton(
            onPressed: () => ref.invalidate(feedNotifierProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _goToLogin() async {
    final success = await Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => const LoginScreen()),
    );
    if (success == true) {
      ref.invalidate(feedNotifierProvider);
    }
  }
}

class TiktokFeedItem extends ConsumerWidget {
  final Tweet tweet;
  final bool isVisible;
  final bool autoFullscreen;
  final bool requireLongVideo;
  final VoidCallback? onPlaybackError;
  final VoidCallback? onDislike;

  const TiktokFeedItem({
    super.key,
    required this.tweet,
    required this.isVisible,
    this.autoFullscreen = false,
    this.requireLongVideo = false,
    this.onPlaybackError,
    this.onDislike,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final videoUiHidden = ref.watch(videoUiHiddenProvider);

    return RepaintBoundary(
      child: Stack(
        children: [
          TiktokMediaContainer(
            tweet: tweet,
            isVisible: isVisible,
            autoFullscreen: autoFullscreen,
            requireLongVideo: requireLongVideo,
            overlayBuilder: (context, onFullscreen, isFullscreen) =>
                TweetTextOverlay(
              tweet: tweet,
              onFullscreen: onFullscreen,
              isFullscreen: isFullscreen,
              onDislike: onDislike,
            ),
            onDislike: onDislike,
            onPlaybackError: onPlaybackError,
          ),
          if (settings.showDebugInfo && !videoUiHidden)
            DiscoveryDebugOverlay(tweet: tweet),
        ],
      ),
    );
  }
}

class DiscoveryDebugOverlay extends StatelessWidget {
  final Tweet tweet;
  const DiscoveryDebugOverlay({super.key, required this.tweet});

  Future<(int, int)> _fetchDebugStats() async {
    final mediaCount = await Repository.getMediaPlayedCount(tweet.id);
    final userCount = await Repository.getUserPlayedCount(tweet.userHandle);
    return (mediaCount, userCount);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100,
      left: 10,
      child: FutureBuilder<(int, int)>(
        future: _fetchDebugStats(),
        builder: (context, snapshot) {
          final stats = snapshot.data ?? (0, 0);
          return Card(
            color: Colors.black.withValues(alpha: 0.6),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _debugLine('TYPE', tweet.isVideo ? 'VIDEO' : 'IMAGE'),
                  _debugLine('SOURCE', tweet.source ?? 'UNKNOWN'),
                  _debugLine('ID', tweet.id.substring(tweet.id.length - 8)),
                  _debugLine('MEDIA', '${tweet.mediaUrls.length} urls'),
                  _debugLine('SEEN', '${stats.$1} times'),
                  _debugLine('ACCT_SEEN', '${stats.$2} times'),
                  if (tweet.createdAt != null)
                    _debugLine(
                        'TS',
                        tweet.createdAt!
                            .toLocal()
                            .toString()
                            .split(' ')
                            .last
                            .split('.')
                            .first),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _debugLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
