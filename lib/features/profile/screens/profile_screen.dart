import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../../feed/providers/audio_player_provider.dart';
import '../../feed/services/media_url_service.dart';
import '../models/profile_models.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(profileSnapshotProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Profile', style: AppTextStyles.headlineLarge),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(profileSnapshotProvider),
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authProvider).signOut(),
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: snapshotAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (_, __) => _ProfileError(
          onRetry: () => ref.invalidate(profileSnapshotProvider),
        ),
        data: (snapshot) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => ref.refresh(profileSnapshotProvider.future),
          child: DefaultTabController(
            length: 2,
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [
                SliverToBoxAdapter(child: _ProfileHeader(snapshot: snapshot)),
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeaderDelegate(
                    TabBar(
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.primary,
                      tabs: [
                        Tab(text: 'Posts'),
                        Tab(text: 'Yaps'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _PostsTab(posts: snapshot.posts),
                  _YapsTab(yaps: snapshot.yaps),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final ProfileSnapshot snapshot;

  const _ProfileHeader({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final profile = snapshot.profile;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                emoji: profile.avatarEmoji,
                color: profile.avatarColor,
                size: 72,
                fontSize: 34,
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${profile.username}',
                        style: AppTextStyles.headlineLarge),
                    const Gap(4),
                    Text('Your voice, posts, and replies',
                        style: AppTextStyles.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const Gap(18),
          Row(
            children: [
              _Stat(label: 'Posts', value: snapshot.posts.length.toString()),
              const Gap(10),
              _Stat(label: 'Yaps', value: snapshot.yaps.length.toString()),
              const Gap(10),
              _Stat(
                label: 'Replies',
                value: snapshot.totalYapCount.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppTextStyles.headlineMedium),
            const Gap(2),
            Text(label, style: AppTextStyles.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _PostsTab extends StatelessWidget {
  final List<ProfilePost> posts;

  const _PostsTab({required this.posts});

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const _EmptyState(
        icon: Icons.article_outlined,
        message: 'No posts yet.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: posts.length,
      separatorBuilder: (_, __) => const Gap(10),
      itemBuilder: (_, index) => _ProfilePostCard(post: posts[index]),
    );
  }
}

class _ProfilePostCard extends ConsumerWidget {
  final ProfilePost post;

  const _ProfilePostCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Icon(
                  post.hasImage
                      ? Icons.image_outlined
                      : Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const Gap(8),
                Text(_timeAgo(post.createdAt), style: AppTextStyles.labelSmall),
                const Spacer(),
                _MiniMetric(
                  icon: Icons.mic_rounded,
                  value: post.yapCount.toString(),
                ),
                const Gap(12),
                _MiniMetric(
                  icon: Icons.visibility_outlined,
                  value: post.viewCount.toString(),
                ),
              ],
            ),
          ),
          if (post.hasImage && post.media != null)
            _SignedImage(fileKey: post.media!.rawFileKey),
          if (post.textContent != null && post.textContent!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Text(post.textContent!, style: AppTextStyles.bodyLarge),
            ),
        ],
      ),
    );
  }
}

class _YapsTab extends StatelessWidget {
  final List<ProfileYap> yaps;

  const _YapsTab({required this.yaps});

  @override
  Widget build(BuildContext context) {
    if (yaps.isEmpty) {
      return const _EmptyState(
        icon: Icons.mic_none_rounded,
        message: 'No yaps yet.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: yaps.length,
      separatorBuilder: (_, __) => const Gap(10),
      itemBuilder: (_, index) => _ProfileYapCard(yap: yaps[index]),
    );
  }
}

class _ProfileYapCard extends ConsumerWidget {
  final ProfileYap yap;

  const _ProfileYapCard({required this.yap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(audioPlayerProvider);
    final isPlaying = playback.isPlayingYap(yap.id);
    final isLoading = playback.isLoadingYap(yap.id);
    final media = yap.media;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.surfaceElevated,
              ),
              onPressed: media == null
                  ? null
                  : () => ref
                      .read(audioPlayerProvider.notifier)
                      .play(yap.id, media.playbackKey),
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(_timeAgo(yap.createdAt),
                        style: AppTextStyles.labelSmall),
                    const Spacer(),
                    _MiniMetric(
                      icon: Icons.play_arrow_rounded,
                      value: yap.playCount.toString(),
                    ),
                    const Gap(10),
                    _MiniMetric(
                      icon: Icons.reply_rounded,
                      value: yap.replyCount.toString(),
                    ),
                  ],
                ),
                const Gap(8),
                Text(
                  yap.postText?.isNotEmpty == true
                      ? yap.postText!
                      : _postTypeLabel(yap.postContentType),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge,
                ),
                if (yap.parentYapId != null) ...[
                  const Gap(8),
                  Text('Reply in thread',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.primary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final String value;

  const _MiniMetric({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const Gap(4),
        Text(value, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _SignedImage extends ConsumerWidget {
  final String fileKey;

  const _SignedImage({required this.fileKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.read(mediaUrlServiceProvider).getUrl(fileKey),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(8),
          ),
          child: Image.network(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 190,
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final String emoji;
  final Color color;
  final double size;
  final double fontSize;

  const _Avatar({
    required this.emoji,
    required this.color,
    required this.size,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(emoji, style: TextStyle(fontSize: fontSize)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 96),
      children: [
        Icon(icon, color: AppColors.textMuted, size: 42),
        const Gap(12),
        Center(child: Text(message, style: AppTextStyles.bodyMedium)),
      ],
    );
  }
}

class _ProfileError extends StatelessWidget {
  final VoidCallback onRetry;

  const _ProfileError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Could not load profile', style: AppTextStyles.bodyMedium),
          const Gap(12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  const _TabsHeaderDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabsHeaderDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String _postTypeLabel(String contentType) {
  if (contentType.contains('image')) return 'Image post';
  if (contentType.contains('video')) return 'Video post';
  return 'Post';
}
