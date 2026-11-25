import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/repository.dart';
import '../../core/models/tweet.dart';
import '../../core/navigation/navigation_provider.dart';
import '../../core/client/public_x_client.dart';
import '../cast/cast_video_button.dart';
import '../player/player_pool_provider.dart';
import '../player/widgets/media_container.dart';
import 'feed_provider.dart';
import 'local_video_reactions_provider.dart';
import 'widgets/tweet_text_overlay.dart';

class LikedVideosScreen extends ConsumerWidget {
  const LikedVideosScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, List<Tweet> items,
      Tweet selected) async {
    var item = selected;
    if (item.mediaUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recherche de la vidéo enregistrée…')));
      try {
        final result = await ref.read(twitterClientProvider)
            .fetchTweetDetail(item.id).timeout(const Duration(seconds: 12));
        for (final video in result.tweets) {
          if (video.id == item.id && video.isVideo && video.mediaUrls.isNotEmpty) {
            item = video;
            break;
          }
        }
      } catch (_) {}
      if (!context.mounted) return;
      if (item.mediaUrls.isEmpty) {
        try {
          final result = await PublicXClient().userVideos(
              item.userHandle.replaceFirst('@', ''));
          for (final video in result.tweets) {
            if (video.id == item.id && video.isVideo && video.mediaUrls.isNotEmpty) {
              item = video;
              break;
            }
          }
        } catch (_) {}
      }
      if (!context.mounted) return;
      if (item.mediaUrls.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vidéo indisponible sur X. Ton J’aime est conservé.')));
        return;
      }
      await Repository.insertCachedMedia([item]);
      if (!context.mounted) return;
      ref.invalidate(likedVideosProvider);
    }
    final playable = [
      for (final video in items)
        if (video.id == item.id) item
        else if (video.mediaUrls.isNotEmpty) video,
    ];
    final index = playable.indexWhere((v) => v.id == item.id);
    if (!context.mounted || index < 0) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _LikedVideoPlayer(videos: playable, initialIndex: index),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(likedVideosProvider);
    final reactions = ref.watch(localVideoReactionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes J’aime')),
      body: videos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: TextButton(
          onPressed: () => ref.invalidate(likedVideosProvider),
          child: const Text('Réessayer'),
        )),
        data: (stored) {
          final current = reactions.value;
          final items = stored.where((v) =>
              current == null || current[v.id]?.value == 1).toList();
          if (items.isEmpty) {
            return const Center(child: Text('Aucune vidéo likée pour le moment.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4,
              childAspectRatio: 9 / 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final video = items[index];
              return InkWell(
                key: ValueKey(video.id),
                onTap: () => _open(context, ref, items, video),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: Colors.black,
                    child: Stack(fit: StackFit.expand, children: [
                      if (video.thumbnailUrl?.isNotEmpty == true)
                        CachedNetworkImage(
                          imageUrl: video.thumbnailUrl!,
                          fit: BoxFit.contain, memCacheWidth: 360,
                          errorWidget: (_, _, _) => const Icon(Icons.play_circle_outline),
                        )
                      else
                        Center(child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(video.text.isEmpty ? 'Vidéo' : video.text,
                            maxLines: 4, overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center),
                        )),
                      const Positioned(top: 4, right: 4,
                        child: Icon(Icons.play_circle_outline, color: Colors.white)),
                      Positioned(bottom: 0, right: 0,
                        child: IconButton(
                          tooltip: 'Retirer le J’aime',
                          icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
                          onPressed: () async {
                            try {
                              await ref.read(localVideoReactionsProvider.notifier)
                                  .toggle(video, 1);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Impossible de retirer le J’aime.')));
                              }
                            }
                          },
                        )),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LikedVideoPlayer extends ConsumerStatefulWidget {
  const _LikedVideoPlayer({required this.videos, required this.initialIndex});
  final List<Tweet> videos;
  final int initialIndex;

  @override
  ConsumerState<_LikedVideoPlayer> createState() => _LikedVideoPlayerState();
}

class _LikedVideoPlayerState extends ConsumerState<_LikedVideoPlayer> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
    _schedulePool();
  }

  void _schedulePool() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pool = ref.read(playerPoolProvider.notifier);
      final ids = <String>{};
      for (var i = _index; i < widget.videos.length && i <= _index + 3; i++) {
        final video = widget.videos[i];
        ids.add(video.id);
        pool.warmup(video.id, video.mediaUrls.first);
      }
      pool.cleanupExcept(ids);
      ref.read(castPlaylistProvider.notifier).setQueue(widget.videos);
    });
  }

  void _advance(int index) {
    if (!mounted || _index != index || !_pages.hasClients ||
        index + 1 >= widget.videos.length) return;
    _pages.jumpToPage(index + 1);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(navigationProvider, (previous, next) {
      if ((next.selectedUser != null || next.selectedHashtag != null) &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
    ref.listen(activeCastTweetProvider, (previous, next) {
      if (previous == null || next == null || previous == next) return;
      final index = widget.videos.indexWhere((v) => v.id == next);
      if (index >= 0 && _pages.hasClients) _pages.jumpToPage(index);
    });
    final cast = ref.watch(activeCastTweetProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Mes J’aime')),
      body: PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: widget.videos.length,
        onPageChanged: (i) {
          setState(() => _index = i);
          _schedulePool();
        },
        itemBuilder: (context, index) {
          final video = widget.videos[index];
          return TiktokMediaContainer(
            key: ValueKey(video.id), tweet: video,
            isVisible: index == _index && cast != video.id,
            onPlaybackError: () => _advance(index),
            onDislike: () => _advance(index),
            overlayBuilder: (context, fullscreen, isFullscreen) => TweetTextOverlay(
              tweet: video, onFullscreen: fullscreen, isFullscreen: isFullscreen,
              onDislike: () => _advance(index),
            ),
          );
        },
      ),
    );
  }
}
