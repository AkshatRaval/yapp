import 'package:supabase_flutter/supabase_flutter.dart';

import '../../feed/models/feed_models.dart';
import '../models/profile_models.dart';

class ProfileRepository {
  final SupabaseClient _supabase;

  ProfileRepository(this._supabase);

  Future<ProfileSnapshot> getCurrentUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final profileRaw = await _supabase
        .from('profiles')
        .select('id, username, avatar_emoji, avatar_color')
        .eq('id', user.id)
        .single();

    final postsRaw = await _supabase
        .from('posts')
        .select(
          'id, content_type, text_content, yap_count, view_count, '
          'created_at, media_files(id, raw_file_key, processed_file_key, media_type, duration_seconds)',
        )
        .eq('user_id', user.id)
        .eq('is_removed', false)
        .order('created_at', ascending: false)
        .limit(30);

    final yapsRaw = await _supabase
        .from('yaps')
        .select(
          'id, post_id, parent_yap_id, play_count, reply_count, created_at, '
          'media_files(id, raw_file_key, processed_file_key, media_type, duration_seconds), '
          'posts(id, text_content, content_type, created_at)',
        )
        .eq('user_id', user.id)
        .eq('is_deleted', false)
        .order('created_at', ascending: false)
        .limit(50);

    return ProfileSnapshot(
      profile: FeedProfile.fromMap(Map<String, dynamic>.from(profileRaw)),
      posts: List<Map<String, dynamic>>.from(postsRaw as List)
          .map(ProfilePost.fromMap)
          .toList(),
      yaps: List<Map<String, dynamic>>.from(yapsRaw as List)
          .map(ProfileYap.fromMap)
          .toList(),
    );
  }
}
