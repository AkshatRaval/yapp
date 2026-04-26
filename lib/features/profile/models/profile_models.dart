import '../../feed/models/feed_models.dart';

class ProfilePost {
  final String id;
  final String contentType;
  final String? textContent;
  final FeedMedia? media;
  final int yapCount;
  final int viewCount;
  final DateTime createdAt;

  const ProfilePost({
    required this.id,
    required this.contentType,
    this.textContent,
    this.media,
    required this.yapCount,
    required this.viewCount,
    required this.createdAt,
  });

  bool get hasImage =>
      contentType == 'image' || contentType == 'text_image';

  factory ProfilePost.fromMap(Map<String, dynamic> map) {
    final mediaRaw = map['media_files'] as Map<String, dynamic>?;
    return ProfilePost(
      id: map['id'] as String,
      contentType: map['content_type'] as String,
      textContent: map['text_content'] as String?,
      media: mediaRaw != null ? FeedMedia.fromMap(mediaRaw) : null,
      yapCount: (map['yap_count'] as int?) ?? 0,
      viewCount: (map['view_count'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class ProfileYap {
  final String id;
  final String postId;
  final String? parentYapId;
  final FeedMedia? media;
  final DateTime createdAt;
  final int playCount;
  final int replyCount;
  final String? postText;
  final String postContentType;

  const ProfileYap({
    required this.id,
    required this.postId,
    this.parentYapId,
    this.media,
    required this.createdAt,
    required this.playCount,
    required this.replyCount,
    this.postText,
    required this.postContentType,
  });

  factory ProfileYap.fromMap(Map<String, dynamic> map) {
    final mediaRaw = map['media_files'] as Map<String, dynamic>?;
    final postRaw = map['posts'] as Map<String, dynamic>?;
    return ProfileYap(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      parentYapId: map['parent_yap_id'] as String?,
      media: mediaRaw != null ? FeedMedia.fromMap(mediaRaw) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      playCount: (map['play_count'] as int?) ?? 0,
      replyCount: (map['reply_count'] as int?) ?? 0,
      postText: postRaw?['text_content'] as String?,
      postContentType: postRaw?['content_type'] as String? ?? 'post',
    );
  }
}

class ProfileSnapshot {
  final FeedProfile profile;
  final List<ProfilePost> posts;
  final List<ProfileYap> yaps;

  const ProfileSnapshot({
    required this.profile,
    required this.posts,
    required this.yaps,
  });

  int get totalYapCount =>
      posts.fold<int>(0, (total, post) => total + post.yapCount);
}
