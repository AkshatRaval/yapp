import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/feed_models.dart';
import '../providers/feed_provider.dart';
import '../providers/audio_player_provider.dart';
import '../services/media_url_service.dart';
import '../widgets/yap_recorder_sheet.dart' show YapHoldButton, YapReplyPreview;

// ---------------------------------------------------------------------------
// FeedScreen
// ---------------------------------------------------------------------------
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('yapp',
            style: AppTextStyles.displayMedium
                .copyWith(color: AppColors.primary, letterSpacing: -2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded,
                color: AppColors.textSecondary),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-post'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Post', style: TextStyle(color: Colors.white)),
      ),
      body: feedAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load feed',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary)),
              const Gap(12),
              TextButton(
                onPressed: () => ref.read(feedProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (state) {
          if (state.posts.isEmpty) {
            return Center(
                child: Text('No posts yet.', style: AppTextStyles.bodyLarge));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.read(feedProvider.notifier).refresh(),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollEndNotification &&
                    n.metrics.extentAfter < 300) {
                  ref.read(feedProvider.notifier).loadMore();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount:
                    state.posts.length + (state.isLoadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const Gap(8),
                itemBuilder: (context, i) {
                  if (i == state.posts.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2)),
                    );
                  }
                  return _PostCard(post: state.posts[i]);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PostCard
// ---------------------------------------------------------------------------
class _PostCard extends ConsumerWidget {
  final FeedPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewYaps = post.yaps.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                _Avatar(
                    emoji: post.profile.avatarEmoji,
                    color: post.profile.avatarColor,
                    size: 36,
                    fontSize: 18),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@${post.profile.username}',
                          style: AppTextStyles.username),
                      Text(post.timeAgo, style: AppTextStyles.labelSmall),
                    ],
                  ),
                ),
                _CategoryTag(label: post.categoryLabel),
                _OwnerMenu(
                  ownerId: post.profile.id,
                  label: 'post',
                  onDelete: () => ref
                      .read(feedProvider.notifier)
                      .removePost(post.id),
                ),
              ],
            ),
          ),

          // Image
          if (post.hasImage && post.media != null)
            _SignedImage(fileKey: post.media!.playbackKey, height: 200),

          // Text
          if (post.textContent != null && post.textContent!.isNotEmpty)
            Padding(
              padding:
                  EdgeInsets.fromLTRB(14, post.hasImage ? 10 : 0, 14, 14),
              child:
                  Text(post.textContent!, style: AppTextStyles.bodyLarge),
            ),

          Container(height: 1, color: AppColors.border),

          // Yap count row
          GestureDetector(
            onTap: () => _openYapChain(context, post),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  const Icon(Icons.mic_rounded,
                      color: AppColors.primary, size: 14),
                  const Gap(6),
                  Text('${post.yapCount} Yaps',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.primary)),
                  const Spacer(),
                  Text('See all →',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
          ),

          // Preview yap bubbles
          if (previewYaps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: previewYaps
                    .map((yap) => _YapBubble(
                          yap: yap,
                          onTap: () => _openYapChain(context, post),
                        ))
                    .toList(),
              ),
            ),

          // Record reply — hold to record
          Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border))),
            child: YapHoldButton(
              postId: post.id,
              child: TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.mic_none_rounded,
                    color: AppColors.textMuted, size: 18),
                label: Text('Hold to Yapp',
                    style: AppTextStyles.bodyMedium),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openYapChain(BuildContext context, FeedPost post) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _YapChainSheet(post: post),
    );
  }
}

// ---------------------------------------------------------------------------
// _YapChainSheet
// ---------------------------------------------------------------------------
class _YapChainSheet extends StatelessWidget {
  final FeedPost post;
  const _YapChainSheet({required this.post});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Gap(4),

          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Gap(12),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _Avatar(
                                emoji: post.profile.avatarEmoji,
                                color: post.profile.avatarColor,
                                size: 34,
                                fontSize: 17),
                            const Gap(10),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('@${post.profile.username}',
                                    style: AppTextStyles.username),
                                Text(post.timeAgo,
                                    style: AppTextStyles.labelSmall),
                              ],
                            ),
                            const Spacer(),
                            _CategoryTag(label: post.categoryLabel),
                          ],
                        ),
                      ),
                      const Gap(10),
                      if (post.hasImage && post.media != null)
                        _SignedImage(
                            fileKey: post.media!.playbackKey,
                            height: 220),
                      if (post.textContent != null &&
                          post.textContent!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              16, post.hasImage ? 12 : 0, 16, 16),
                          child: Text(post.textContent!,
                              style: AppTextStyles.bodyLarge),
                        ),
                      Container(
                        color: AppColors.background,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.mic_rounded,
                                color: AppColors.primary, size: 16),
                            const Gap(8),
                            Text('${post.yapCount} Yaps',
                                style: AppTextStyles.headlineMedium),
                          ],
                        ),
                      ),
                      Container(height: 1, color: AppColors.border),
                      const Gap(12),
                    ],
                  ),
                ),

                if (post.yaps.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                          child: Text('No yaps yet.',
                              style: AppTextStyles.bodyMedium)),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child:
                            _YapChainItem(yap: post.yaps[i], depth: 0, postId: post.id),
                      ),
                      childCount: post.yaps.length,
                    ),
                  ),

                const SliverToBoxAdapter(child: Gap(24)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _YapChainItem — recursive, expand/collapse, real audio playback
// ---------------------------------------------------------------------------
class _YapChainItem extends ConsumerWidget {
  final FeedYap yap;
  final int depth;
  final String postId;

  const _YapChainItem({
    required this.yap,
    required this.depth,
    required this.postId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _YapChainItemStateful(yap: yap, depth: depth, postId: postId);
  }
}

class _YapChainItemStateful extends ConsumerStatefulWidget {
  final FeedYap yap;
  final int depth;
  final String postId;

  const _YapChainItemStateful({
    required this.yap,
    required this.depth,
    required this.postId,
  });

  @override
  ConsumerState<_YapChainItemStateful> createState() =>
      _YapChainItemState();
}

class _YapChainItemState extends ConsumerState<_YapChainItemStateful> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final yap = widget.yap;
    final replies = yap.replies;
    final hasReplies = replies.isNotEmpty;
    final color = yap.profile.avatarColor;
    final audio = ref.watch(audioPlayerProvider);
    final isThisPlaying = audio.isPlayingYap(yap.id);
    final isThisLoading = audio.isLoadingYap(yap.id);
    final isThisCurrent = audio.currentYapId == yap.id;
    final duration = yap.media?.formattedDuration ?? '0:00';
    final totalSeconds = yap.media?.totalSeconds ?? 0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.depth > 0)
            Row(children: [
              SizedBox(width: (widget.depth - 1) * 20.0),
              Container(
                width: 2,
                margin: const EdgeInsets.only(right: 12, bottom: 8),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(1)),
              ),
            ]),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: widget.depth == 0
                        ? AppColors.surfaceElevated
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: yap.isFailed
                          ? AppColors.error
                          : AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Row(
                          children: [
                            _Avatar(
                                emoji: yap.profile.avatarEmoji,
                                color: color,
                                size: 30,
                                fontSize: 15),
                            const Gap(10),
                            Expanded(
                              child: Text(
                                  '@${yap.profile.username}',
                                  style: AppTextStyles.labelLarge),
                            ),
                            _OwnerMenu(
                              ownerId: yap.profile.id,
                              label: 'yap',
                              onDelete: () => ref
                                  .read(feedProvider.notifier)
                                  .removeYap(yap.id, widget.postId),
                            ),
                            // Play button
                            _PlayButton(
                              isPlaying: isThisPlaying,
                              isLoading:
                                  isThisLoading || yap.isPending,
                              isFailed: yap.isFailed,
                              onTap: yap.isPending || yap.isFailed || yap.media == null
                                  ? null
                                  : () => ref
                                      .read(audioPlayerProvider.notifier)
                                      .play(yap.id,
                                          yap.media!.playbackKey),
                            ),
                          ],
                        ),
                      ),

                      // Seek slider (real position when this yap is current)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape:
                                    const RoundSliderThumbShape(
                                        enabledThumbRadius: 6),
                                overlayShape:
                                    const RoundSliderOverlayShape(
                                        overlayRadius: 12),
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: AppColors.border,
                                thumbColor: AppColors.primary,
                                overlayColor: AppColors.primaryGlow,
                              ),
                              child: Slider(
                                value: isThisCurrent
                                    ? audio.progress
                                    : 0.0,
                                onChanged: isThisCurrent
                                    ? (val) {
                                        final ms =
                                            (val * audio.duration.inMilliseconds)
                                                .round();
                                        ref
                                            .read(audioPlayerProvider
                                                .notifier)
                                            .seek(Duration(
                                                milliseconds: ms));
                                      }
                                    : null,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isThisCurrent
                                        ? _fmt(audio.position)
                                        : '0:00',
                                    style: AppTextStyles.labelSmall,
                                  ),
                                  Text(duration,
                                      style: AppTextStyles.labelSmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Footer: reply + expand
                      Container(
                        decoration: const BoxDecoration(
                            border: Border(
                                top: BorderSide(
                                    color: AppColors.border))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Big, visible "Hold to reply" button — reliable long-press
                            if (!yap.isPending && !yap.isFailed)
                              YapHoldButton(
                                postId: widget.postId,
                                parentYapId: yap.id,
                                replyPreview: YapReplyPreview(
                                  username: yap.profile.username,
                                  avatarEmoji: yap.profile.avatarEmoji,
                                  avatarColor: yap.profile.avatarColor,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.reply_rounded,
                                          size: 14,
                                          color: color),
                                      const Gap(6),
                                      Text(
                                        'Hold to Yapp your reply',
                                        style: AppTextStyles.labelSmall
                                            .copyWith(color: color),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (yap.isFailed)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Text(
                                    'Upload failed · tap to retry',
                                    style: AppTextStyles.labelSmall
                                        .copyWith(
                                            color: AppColors.error)),
                              ),
                            if (yap.isPending)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Text('Uploading...',
                                    style: AppTextStyles.labelSmall
                                        .copyWith(
                                            color:
                                                AppColors.textMuted)),
                              ),
                            // Expand replies row — separate, tappable
                            if (hasReplies)
                              Container(
                                decoration: const BoxDecoration(
                                    border: Border(
                                        top: BorderSide(
                                            color: AppColors.border))),
                                child: GestureDetector(
                                  onTap: () => setState(
                                      () => _expanded = !_expanded),
                                  behavior: HitTestBehavior.opaque,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _expanded
                                              ? Icons
                                                  .keyboard_arrow_up_rounded
                                              : Icons
                                                  .keyboard_arrow_down_rounded,
                                          size: 14,
                                          color: AppColors.accent,
                                        ),
                                        const Gap(2),
                                        Text(
                                          '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                                          style: AppTextStyles
                                              .labelSmall
                                              .copyWith(
                                                  color:
                                                      AppColors.accent),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_expanded)
                  ...replies.map((reply) => _YapChainItemStateful(
                      yap: reply,
                      depth: widget.depth + 1,
                      postId: widget.postId)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// _PlayButton — unified play/pause/loading/failed button
// ---------------------------------------------------------------------------
class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final bool isFailed;
  final VoidCallback? onTap;

  const _PlayButton({
    required this.isPlaying,
    required this.isLoading,
    required this.isFailed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isPlaying
              ? AppColors.primary
              : isFailed
                  ? AppColors.error.withValues(alpha: 0.15)
                  : AppColors.primaryGlow,
          shape: BoxShape.circle,
          border: Border.all(
            color: isFailed ? AppColors.error : AppColors.primary,
            width: 1,
          ),
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(9),
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              )
            : isFailed
                ? const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 18)
                : Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color:
                        isPlaying ? Colors.white : AppColors.primary,
                    size: 18,
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _YapBubble — preview bubble in feed card
// ---------------------------------------------------------------------------
class _YapBubble extends ConsumerWidget {
  final FeedYap yap;
  final VoidCallback onTap;
  const _YapBubble({required this.yap, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replyCount = yap.replies.length;
    final duration = yap.media?.formattedDuration ?? '0:00';
    final audio = ref.watch(audioPlayerProvider);
    final isPlaying = audio.isPlayingYap(yap.id);
    final isLoading = audio.isLoadingYap(yap.id);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _Avatar(
                emoji: yap.profile.avatarEmoji,
                color: yap.profile.avatarColor,
                size: 28,
                fontSize: 14),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${yap.profile.username}',
                      style: AppTextStyles.labelLarge),
                  Row(
                    children: [
                      Text(duration, style: AppTextStyles.labelSmall),
                      if (replyCount > 0) ...[
                        const Gap(6),
                        Text(
                          '· $replyCount ${replyCount == 1 ? 'reply' : 'replies'}',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.accent),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Tapping the play button in the preview bubble plays inline
            GestureDetector(
              onTap: yap.media == null || yap.isPending
                  ? null
                  : () => ref
                      .read(audioPlayerProvider.notifier)
                      .play(yap.id, yap.media!.playbackKey),
              child: _PlayButton(
                isPlaying: isPlaying,
                isLoading: isLoading || yap.isPending,
                isFailed: yap.isFailed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SignedImage
// ---------------------------------------------------------------------------
class _SignedImage extends ConsumerStatefulWidget {
  final String fileKey;
  final double height;
  const _SignedImage({required this.fileKey, required this.height});

  @override
  ConsumerState<_SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends ConsumerState<_SignedImage> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url =
        await ref.read(mediaUrlServiceProvider).getUrl(widget.fileKey);
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: widget.height,
        color: AppColors.surfaceElevated,
        child: const Center(
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2)),
      );
    }
    final url = _url;
    if (url == null) {
      return Container(
          height: widget.height, color: AppColors.surfaceElevated);
    }
    return Image.network(
      url,
      width: double.infinity,
      height: widget.height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        height: widget.height,
        color: AppColors.surfaceElevated,
        child: const Center(
            child: Icon(Icons.broken_image_rounded,
                color: AppColors.textMuted, size: 32)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------
class _Avatar extends StatelessWidget {
  final String emoji;
  final Color color;
  final double size;
  final double fontSize;
  const _Avatar(
      {required this.emoji,
      required this.color,
      required this.size,
      required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child:
          Center(child: Text(emoji, style: TextStyle(fontSize: fontSize))),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  final String label;
  const _CategoryTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: AppTextStyles.labelSmall),
    );
  }
}

// ---------------------------------------------------------------------------
// _OwnerMenu — three-dot menu shown only to the owner of a post or yap
// ---------------------------------------------------------------------------
class _OwnerMenu extends ConsumerStatefulWidget {
  final String ownerId;
  final String label; // 'post' or 'yap'
  final Future<bool> Function() onDelete;

  const _OwnerMenu({
    required this.ownerId,
    required this.label,
    required this.onDelete,
  });

  @override
  ConsumerState<_OwnerMenu> createState() => _OwnerMenuState();
}

class _OwnerMenuState extends ConsumerState<_OwnerMenu> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != widget.ownerId) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      enabled: !_isDeleting,
      icon: _isDeleting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.more_vert_rounded,
              color: AppColors.textMuted, size: 18),
      color: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) async {
        if (value != 'delete') return;
        final confirmed = await showDialog<bool>(
          context: context,
          barrierColor: AppColors.background.withValues(alpha: 0.35),
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Delete this ${widget.label}?',
                style: AppTextStyles.headlineMedium),
            content: Text(
              "This can't be undone.",
              style: AppTextStyles.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete',
                    style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;

        setState(() => _isDeleting = true);
        final messenger = ScaffoldMessenger.of(context);
        final deleted = await widget.onDelete();
        if (!mounted) return;

        setState(() => _isDeleting = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              deleted
                  ? '${_capitalize(widget.label)} deleted'
                  : 'Could not delete ${widget.label}. Please try again.',
            ),
            backgroundColor:
                deleted ? AppColors.surfaceElevated : AppColors.error,
          ),
        );
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 18),
              const Gap(10),
              Text('Delete ${widget.label}',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
