import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feed_models.dart';

class FeedRepository {
  final SupabaseClient _supabase;

  FeedRepository(this._supabase);

  /// Fetches a page of posts with their yap trees and profiles.
  /// Cursor-based pagination on created_at for feed stability.
  Future<List<FeedPost>> getFeed({
    int limit = 20,
    DateTime? before,
  }) async {
    try {
      // --- Query 1: posts + media ---
      var filterQuery = _supabase
          .from('posts')
          .select(
            'id, content_type, text_content, media_file_id, yap_count, '
            'created_at, user_id, '
            'media_files(id, raw_file_key, processed_file_key, media_type, duration_seconds)',
          )
          .eq('is_removed', false);

      if (before != null) {
        filterQuery = filterQuery.lt('created_at', before.toIso8601String());
      }

      final query = filterQuery
          .order('created_at', ascending: false)
          .limit(limit);

      final rawPosts = await query;
      final postList = List<Map<String, dynamic>>.from(rawPosts as List);
      if (postList.isEmpty) return [];

      final postIds = postList.map((p) => p['id'] as String).toList();

      // --- Query 2: flat yaps with parent_yap_id ---
      final rawYaps = await _supabase
          .from('yaps')
          .select(
            'id, user_id, post_id, parent_yap_id, created_at, '
            'media_files(id, raw_file_key, processed_file_key, media_type, duration_seconds)',
          )
          .inFilter('post_id', postIds)
          .eq('is_deleted', false)
          .order('created_at', ascending: true);

      final yapList = List<Map<String, dynamic>>.from(rawYaps as List);

      // --- Query 3: profiles for all unique user_ids ---
      final userIds = <String>{
        ...postList.map((p) => p['user_id'] as String),
        ...yapList.map((y) => y['user_id'] as String),
      }.toList();

      final rawProfiles = userIds.isEmpty
          ? []
          : await _supabase
              .from('profiles')
              .select('id, username, avatar_emoji, avatar_color')
              .inFilter('id', userIds);

      final profileMap = <String, FeedProfile>{};
      for (final p in rawProfiles as List) {
        final map = Map<String, dynamic>.from(p as Map);
        profileMap[map['id'] as String] = FeedProfile.fromMap(map);
      }

      FeedProfile _fallbackProfile(String userId) => FeedProfile(
            id: userId,
            username: 'anonymous',
            avatarEmoji: '👤',
            avatarColor: const Color(0xFFFF3C5F),
          );

      // --- Build flat FeedYap list ---
      final typedYaps = yapList.map((y) {
        final userId = y['user_id'] as String;
        final mediaRaw = y['media_files'] as Map<String, dynamic>?;
        return FeedYap(
          id: y['id'] as String,
          postId: y['post_id'] as String,
          parentYapId: y['parent_yap_id'] as String?,
          profile: profileMap[userId] ?? _fallbackProfile(userId),
          media: mediaRaw != null ? FeedMedia.fromMap(mediaRaw) : null,
          createdAt: DateTime.parse(y['created_at'] as String),
        );
      }).toList();

      // --- Group yaps by post ---
      final yapsByPostId = <String, List<FeedYap>>{};
      for (final yap in typedYaps) {
        yapsByPostId.putIfAbsent(yap.postId, () => []).add(yap);
      }

      // --- Assemble FeedPost list ---
      return postList.map((p) {
        final userId = p['user_id'] as String;
        final mediaRaw = p['media_files'] as Map<String, dynamic>?;
        final postId = p['id'] as String;

        return FeedPost(
          id: postId,
          contentType: p['content_type'] as String,
          textContent: p['text_content'] as String?,
          media: mediaRaw != null ? FeedMedia.fromMap(mediaRaw) : null,
          profile: profileMap[userId] ?? _fallbackProfile(userId),
          yapCount: (p['yap_count'] as int?) ?? 0,
          yaps: _buildReplyTree(yapsByPostId[postId] ?? []),
          createdAt: DateTime.parse(p['created_at'] as String),
        );
      }).toList();
    } catch (e) {
      debugPrint('[FeedRepository] getFeed error: $e');
      rethrow;
    }
  }

  /// Builds a nested reply tree from a flat list. O(n).
  List<FeedYap> _buildReplyTree(List<FeedYap> flat) {
    final byParent = <String?, List<FeedYap>>{};
    for (final yap in flat) {
      byParent.putIfAbsent(yap.parentYapId, () => []).add(yap);
    }
    return _attachChildren(null, byParent);
  }

  List<FeedYap> _attachChildren(
    String? parentId,
    Map<String?, List<FeedYap>> byParent,
  ) {
    final children = byParent[parentId] ?? [];
    return children.map((yap) {
      return FeedYap(
        id: yap.id,
        postId: yap.postId,
        parentYapId: yap.parentYapId,
        profile: yap.profile,
        media: yap.media,
        createdAt: yap.createdAt,
        replies: _attachChildren(yap.id, byParent),
      );
    }).toList();
  }
}
