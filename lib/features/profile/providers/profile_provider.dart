import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_models.dart';
import '../repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

final profileSnapshotProvider =
    FutureProvider.autoDispose<ProfileSnapshot>((ref) {
  return ref.read(profileRepositoryProvider).getCurrentUserProfile();
});
