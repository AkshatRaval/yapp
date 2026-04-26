import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../models/feed_models.dart';
import '../repositories/feed_repository.dart';
import '../services/media_url_service.dart';
import 'audio_player_provider.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepository(Supabase.instance.client);
});

// ---------------------------------------------------------------------------
// Feed state
// ---------------------------------------------------------------------------
class FeedState {
  final List<FeedPost> posts;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const FeedState({
    this.posts = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  FeedState copyWith({
    List<FeedPost>? posts,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

// ---------------------------------------------------------------------------
// FeedNotifier
// ---------------------------------------------------------------------------
class FeedNotifier extends AsyncNotifier<FeedState> {
  static const int _pageSize = 20;
  final Map<String, RealtimeChannel> _mediaChannels = {};
  final Map<String, Timer> _mediaChannelTimers = {};

  FeedRepository get _repo => ref.read(feedRepositoryProvider);
  MediaUrlService get _mediaService => ref.read(mediaUrlServiceProvider);

  @override
  Future<FeedState> build() async {
    ref.onDispose(_disposeMediaSubscriptions);
    final posts = await _repo.getFeed(limit: _pageSize);
    await _prefetchUrls(posts);
    return FeedState(posts: posts, hasMore: posts.length == _pageSize);
  }

  Future<void> refresh() async {
    // Stop any currently playing yap — fresh feed = fresh slate
    try {
      await ref.read(audioPlayerProvider.notifier).stop();
    } catch (_) {}

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final posts = await _repo.getFeed(limit: _pageSize);
      await _prefetchUrls(posts);
      return FeedState(posts: posts, hasMore: posts.length == _pageSize);
    });
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final cursor =
          current.posts.isNotEmpty ? current.posts.last.createdAt : null;
      final more = await _repo.getFeed(limit: _pageSize, before: cursor);
      await _prefetchUrls(more);

      state = AsyncData(current.copyWith(
        posts: [...current.posts, ...more],
        isLoadingMore: false,
        hasMore: more.length == _pageSize,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Optimistic yap management
  // ---------------------------------------------------------------------------

  /// Inserts a pending yap immediately into the in-memory tree.
  /// Returns the tempId so the caller can confirm/fail it later.
  String addOptimisticYap({
    required String postId,
    required String? parentYapId,
    required FeedProfile profile,
    required double durationSeconds,
    required String localAudioPath,
  }) {
    final current = state.valueOrNull;
    if (current == null) return '';

    final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = FeedYap(
      id: tempId,
      postId: postId,
      parentYapId: parentYapId,
      profile: profile,
      media: FeedMedia(
        rawFileKey: '',
        mediaType: 'audio',
        durationSeconds: durationSeconds,
      ),
      createdAt: DateTime.now(),
      status: YapStatus.pending,
      localAudioPath: localAudioPath,
    );

    final updatedPosts = current.posts.map((post) {
      if (post.id != postId) return post;
      final updatedYaps = _insertYapIntoTree(
        post.yaps,
        optimistic,
        parentYapId,
      );
      return post.copyWith(
        yaps: updatedYaps,
        yapCount: post.yapCount + 1,
      );
    }).toList();

    state = AsyncData(current.copyWith(posts: updatedPosts));
    return tempId;
  }

  /// Replaces the optimistic (pending) yap with the confirmed server yap.
  void confirmYap(String tempId, FeedYap serverYap) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updatedPosts = current.posts.map((post) {
      if (post.id != serverYap.postId) return post;
      final updatedYaps = _replaceYapInTree(post.yaps, tempId, serverYap);
      return post.copyWith(yaps: updatedYaps);
    }).toList();

    state = AsyncData(current.copyWith(posts: updatedPosts));
  }

  void attachMediaToOptimisticYap({
    required String tempId,
    required String mediaFileId,
    required String rawFileKey,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updatedPosts = current.posts.map((post) {
      final updatedYaps = _updateYapMedia(
        post.yaps,
        tempId,
        (media) => media.copyWith(id: mediaFileId, rawFileKey: rawFileKey),
      );
      return post.copyWith(yaps: updatedYaps);
    }).toList();

    state = AsyncData(current.copyWith(posts: updatedPosts));
  }

  void watchMediaProcessing(String mediaFileId) {
    if (_mediaChannels.containsKey(mediaFileId)) return;

    try {
      final channel = Supabase.instance.client.channel(
        'media-processing-$mediaFileId',
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'media_files',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: mediaFileId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          final processedFileKey = row['processed_file_key'] as String?;
          final processingStatus = row['processing_status'] as String?;

          if (processingStatus == 'completed' &&
              processedFileKey != null &&
              processedFileKey.isNotEmpty) {
            _applyProcessedMediaKey(mediaFileId, processedFileKey);
            _unsubscribeFromMedia(mediaFileId);
          }
        },
      ).subscribe();

      _mediaChannels[mediaFileId] = channel;
      _mediaChannelTimers[mediaFileId] = Timer(
        const Duration(seconds: 60),
        () => _unsubscribeFromMedia(mediaFileId),
      );
    } catch (e) {
      // Realtime is a playback optimization; publishing must continue without it.
      debugPrint('[FeedNotifier] watchMediaProcessing failed: $e');
    }
  }

  /// Marks the optimistic yap as failed so the UI can show a retry.
  void failYap(String tempId, String postId) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updatedPosts = current.posts.map((post) {
      if (post.id != postId) return post;
      final updatedYaps = _markYapFailed(post.yaps, tempId);
      return post.copyWith(
        yaps: updatedYaps,
        yapCount: (post.yapCount - 1).clamp(0, double.maxFinite.toInt()),
      );
    }).toList();

    state = AsyncData(current.copyWith(posts: updatedPosts));
  }

  // ---------------------------------------------------------------------------
  // Tree helpers
  // ---------------------------------------------------------------------------

  List<FeedYap> _insertYapIntoTree(
    List<FeedYap> yaps,
    FeedYap newYap,
    String? parentYapId,
  ) {
    if (parentYapId == null) {
      // Top-level yap — append at the end
      return [...yaps, newYap];
    }
    return yaps.map((yap) {
      if (yap.id == parentYapId) {
        return yap.copyWith(replies: [...yap.replies, newYap]);
      }
      if (yap.replies.isNotEmpty) {
        return yap.copyWith(
          replies: _insertYapIntoTree(yap.replies, newYap, parentYapId),
        );
      }
      return yap;
    }).toList();
  }

  List<FeedYap> _replaceYapInTree(
    List<FeedYap> yaps,
    String tempId,
    FeedYap serverYap,
  ) {
    return yaps.map((yap) {
      if (yap.id == tempId) {
        final pendingMedia = yap.media;
        final serverMedia = serverYap.media;
        if (pendingMedia != null && serverMedia != null) {
          return serverYap.copyWith(
            media: serverMedia.copyWith(
              id: serverMedia.id ?? pendingMedia.id,
              rawFileKey: serverMedia.rawFileKey.isEmpty
                  ? pendingMedia.rawFileKey
                  : serverMedia.rawFileKey,
              processedFileKey:
                  serverMedia.processedFileKey ?? pendingMedia.processedFileKey,
            ),
          );
        }
        return serverYap;
      }
      if (yap.replies.isNotEmpty) {
        return yap.copyWith(
          replies: _replaceYapInTree(yap.replies, tempId, serverYap),
        );
      }
      return yap;
    }).toList();
  }

  List<FeedYap> _markYapFailed(List<FeedYap> yaps, String tempId) {
    return yaps.map((yap) {
      if (yap.id == tempId) return yap.copyWith(status: YapStatus.failed);
      if (yap.replies.isNotEmpty) {
        return yap.copyWith(replies: _markYapFailed(yap.replies, tempId));
      }
      return yap;
    }).toList();
  }

  List<FeedYap> _updateYapMedia(
    List<FeedYap> yaps,
    String yapId,
    FeedMedia Function(FeedMedia media) update,
  ) {
    return yaps.map((yap) {
      if (yap.id == yapId && yap.media != null) {
        return yap.copyWith(media: update(yap.media!));
      }
      if (yap.replies.isNotEmpty) {
        return yap.copyWith(
          replies: _updateYapMedia(yap.replies, yapId, update),
        );
      }
      return yap;
    }).toList();
  }

  void _applyProcessedMediaKey(
    String mediaFileId,
    String processedFileKey,
  ) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updatedPosts = current.posts.map((post) {
      return post.copyWith(
        yaps: _updateMediaByMediaFileId(
          post.yaps,
          mediaFileId,
          processedFileKey,
        ),
      );
    }).toList();

    state = AsyncData(current.copyWith(posts: updatedPosts));
  }

  List<FeedYap> _updateMediaByMediaFileId(
    List<FeedYap> yaps,
    String mediaFileId,
    String processedFileKey,
  ) {
    return yaps.map((yap) {
      final media = yap.media;
      if (media?.id == mediaFileId) {
        return yap.copyWith(
          media: media!.copyWith(processedFileKey: processedFileKey),
        );
      }
      if (yap.replies.isNotEmpty) {
        return yap.copyWith(
          replies: _updateMediaByMediaFileId(
            yap.replies,
            mediaFileId,
            processedFileKey,
          ),
        );
      }
      return yap;
    }).toList();
  }

  void _unsubscribeFromMedia(String mediaFileId) {
    _mediaChannelTimers.remove(mediaFileId)?.cancel();
    final channel = _mediaChannels.remove(mediaFileId);
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
  }

  void _disposeMediaSubscriptions() {
    for (final timer in _mediaChannelTimers.values) {
      timer.cancel();
    }
    _mediaChannelTimers.clear();

    for (final channel in _mediaChannels.values) {
      Supabase.instance.client.removeChannel(channel);
    }
    _mediaChannels.clear();
  }

  // ---------------------------------------------------------------------------
  // Delete operations
  // ---------------------------------------------------------------------------

  Future<bool> removePost(String postId) async {
    final current = state.valueOrNull;
    if (current == null) return false;

    // Call server FIRST, then remove optimistically on success
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return false;

      final response = await http.post(
        Uri.parse(AppConstants.deletePostEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConstants.supabaseAnonKey,
        },
        body: jsonEncode({'postId': postId}),
      );

      if (response.statusCode != 200) return false;

      // Only remove from state after confirmed server success
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncData(latest.copyWith(
          posts: latest.posts.where((p) => p.id != postId).toList(),
        ));
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeYap(String yapId, String postId) async {
    final current = state.valueOrNull;
    if (current == null) return false;

    // Optimistic remove from tree
    final updatedPosts = current.posts.map((post) {
      if (post.id != postId) return post;
      final updatedYaps = _removeYapFromTree(post.yaps, yapId);
      final removedCount = _countYaps(post.yaps) - _countYaps(updatedYaps);
      return post.copyWith(
        yaps: updatedYaps,
        yapCount: (post.yapCount - removedCount).clamp(0, post.yapCount),
      );
    }).toList();

    state = AsyncData(current.copyWith(posts: updatedPosts));

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('No session');

      final response = await http.post(
        Uri.parse(AppConstants.deleteYapEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConstants.supabaseAnonKey,
        },
        body: jsonEncode({'yapId': yapId}),
      );

      if (response.statusCode != 200) {
        refresh();
        return false;
      }
      return true;
    } catch (e) {
      refresh();
      return false;
    }
  }

  List<FeedYap> _removeYapFromTree(List<FeedYap> yaps, String yapId) {
    return yaps
        .where((y) => y.id != yapId)
        .map((y) => y.copyWith(replies: _removeYapFromTree(y.replies, yapId)))
        .toList();
  }

  int _countYaps(List<FeedYap> yaps) {
    int count = 0;
    for (final y in yaps) {
      count += 1 + _countYaps(y.replies);
    }
    return count;
  }

  Future<void> _prefetchUrls(List<FeedPost> posts) async {
    final keys = <String>[];
    for (final post in posts) {
      if (post.media?.mediaType == 'image') {
        keys.add(post.media!.rawFileKey);
      }
    }
    if (keys.isNotEmpty) await _mediaService.getUrls(keys);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final feedProvider =
    AsyncNotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);
