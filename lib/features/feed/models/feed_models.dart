import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// FeedProfile
// ---------------------------------------------------------------------------
class FeedProfile {
  final String id;
  final String username;
  final String avatarEmoji;
  final Color avatarColor;

  const FeedProfile({
    required this.id,
    required this.username,
    required this.avatarEmoji,
    required this.avatarColor,
  });

  factory FeedProfile.fromMap(Map<String, dynamic> map) {
    return FeedProfile(
      id: map['id'] as String,
      username: map['username'] as String? ?? 'anonymous',
      avatarEmoji: map['avatar_emoji'] as String? ?? '👤',
      avatarColor: _parseColor(map['avatar_color'] as String?),
    );
  }

  static Color _parseColor(String? hex) {
    if (hex == null) return const Color(0xFFFF3C5F);
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return const Color(0xFFFF3C5F);
    }
  }
}

// ---------------------------------------------------------------------------
// FeedMedia
// ---------------------------------------------------------------------------
class FeedMedia {
  final String? id;
  final String rawFileKey;
  final String? processedFileKey; // set once voice filter is processed
  final String mediaType;         // 'audio' | 'image' | 'video'
  final double? durationSeconds;

  const FeedMedia({
    this.id,
    required this.rawFileKey,
    this.processedFileKey,
    required this.mediaType,
    this.durationSeconds,
  });

  factory FeedMedia.fromMap(Map<String, dynamic> map) {
    return FeedMedia(
      id: map['id'] as String?,
      rawFileKey: map['raw_file_key'] as String,
      processedFileKey: map['processed_file_key'] as String?,
      mediaType: map['media_type'] as String? ?? 'audio',
      durationSeconds: (map['duration_seconds'] as num?)?.toDouble(),
    );
  }

  /// Prefer processed (filtered) key if available, else fall back to raw.
  String get playbackKey => processedFileKey ?? rawFileKey;

  String get formattedDuration {
    final secs = durationSeconds?.round() ?? 0;
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  int get totalSeconds => durationSeconds?.round() ?? 0;

  FeedMedia copyWith({
    String? id,
    String? rawFileKey,
    String? processedFileKey,
    String? mediaType,
    double? durationSeconds,
  }) {
    return FeedMedia(
      id: id ?? this.id,
      rawFileKey: rawFileKey ?? this.rawFileKey,
      processedFileKey: processedFileKey ?? this.processedFileKey,
      mediaType: mediaType ?? this.mediaType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }
}

// ---------------------------------------------------------------------------
// YapStatus — for optimistic UI
// ---------------------------------------------------------------------------
enum YapStatus { live, pending, failed }

// ---------------------------------------------------------------------------
// FeedYap  (node in the reply tree)
// ---------------------------------------------------------------------------
class FeedYap {
  final String id;           // temp id (uuid) for pending yaps
  final String postId;
  final String? parentYapId;
  final FeedProfile profile;
  final FeedMedia? media;
  final DateTime createdAt;
  final List<FeedYap> replies;
  final YapStatus status;    // live = from server, pending = optimistic, failed = upload failed
  final String? localAudioPath; // only set for pending yaps

  FeedYap({
    required this.id,
    required this.postId,
    this.parentYapId,
    required this.profile,
    this.media,
    required this.createdAt,
    List<FeedYap>? replies,
    this.status = YapStatus.live,
    this.localAudioPath,
  }) : replies = replies ?? [];

  bool get isPending => status == YapStatus.pending;
  bool get isFailed => status == YapStatus.failed;

  FeedYap copyWith({
    String? id,
    FeedMedia? media,
    List<FeedYap>? replies,
    YapStatus? status,
    String? localAudioPath,
  }) {
    return FeedYap(
      id: id ?? this.id,
      postId: postId,
      parentYapId: parentYapId,
      profile: profile,
      media: media ?? this.media,
      createdAt: createdAt,
      replies: replies ?? this.replies,
      status: status ?? this.status,
      localAudioPath: localAudioPath ?? this.localAudioPath,
    );
  }

  /// Build from the yap map returned by create-yap edge function
  factory FeedYap.fromServerMap(Map<String, dynamic> map) {
    final profileMap = map['profile'] as Map<String, dynamic>?;
    final mediaMap = map['media_files'] as Map<String, dynamic>?;
    return FeedYap(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      parentYapId: map['parent_yap_id'] as String?,
      profile: profileMap != null
          ? FeedProfile.fromMap(profileMap)
          : FeedProfile(
              id: '',
              username: 'anonymous',
              avatarEmoji: '👤',
              avatarColor: const Color(0xFFFF3C5F),
            ),
      media: mediaMap != null ? FeedMedia.fromMap(mediaMap) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: YapStatus.live,
    );
  }

  int get totalReplyCount => _countDescendants(this);

  static int _countDescendants(FeedYap yap) {
    int count = 0;
    for (final r in yap.replies) {
      count += 1 + _countDescendants(r);
    }
    return count;
  }
}

// ---------------------------------------------------------------------------
// FeedPost
// ---------------------------------------------------------------------------
class FeedPost {
  final String id;
  final String contentType;
  final String? textContent;
  final FeedMedia? media;
  final FeedProfile profile;
  final int yapCount;
  final List<FeedYap> yaps;
  final DateTime createdAt;

  const FeedPost({
    required this.id,
    required this.contentType,
    this.textContent,
    this.media,
    required this.profile,
    required this.yapCount,
    required this.yaps,
    required this.createdAt,
  });

  bool get hasImage =>
      contentType == 'image' || contentType == 'text_image';

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get categoryLabel {
    if (yapCount >= 100) return '🔥 Trending';
    if (hasImage) return '📸 Image';
    return '💬 Post';
  }

  FeedPost copyWith({
    List<FeedYap>? yaps,
    int? yapCount,
  }) {
    return FeedPost(
      id: id,
      contentType: contentType,
      textContent: textContent,
      media: media,
      profile: profile,
      yapCount: yapCount ?? this.yapCount,
      yaps: yaps ?? this.yaps,
      createdAt: createdAt,
    );
  }
}
