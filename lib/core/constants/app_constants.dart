import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  AppConstants._();

  // Supabase Secrets
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // AWS S3
  static String get s3BucketName => dotenv.env['S3_BUCKET_NAME'] ?? '';
  static String get s3Region => dotenv.env['S3_REGION'] ?? '';
  static String get s3BaseUrl => 'https://$s3BucketName.s3.$s3Region.amazonaws.com';

  // Edge Function URLs (Derived from secrets)
  static String get generateUploadUrlEndpoint => '$supabaseUrl/functions/v1/generate-upload-url';
  static String get getPlaybackUrlEndpoint => '$supabaseUrl/functions/v1/get-playback-url';
  static String get processAudioEndpoint => '$supabaseUrl/functions/v1/process-audio';
  static String get createYapEndpoint => '$supabaseUrl/functions/v1/create-yap';
  static String get deletePostEndpoint => '$supabaseUrl/functions/v1/delete-post';
  static String get deleteYapEndpoint => '$supabaseUrl/functions/v1/delete-yap';

  // Hardcoded Configuration (Safe to keep in code)
  static const int maxYapDurationSeconds = 60;
  static const int maxReplyDurationSeconds = 30;
  static const int audioSampleRate = 48000;
  static const int audioBitRate = 48000;
  static const int audioChannels = 1;
  static const int feedPageSize = 20;
  static const String appName = 'Yapp';
}