import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';

final audioServiceProvider = Provider((ref) => AudioService());

class AudioService {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  String? _lastError;

  String? get lastError => _lastError;

  Future<String?> startRecording() async {
    try {
      _lastError = null;
      if (!await _recorder.hasPermission()) {
        _lastError = 'Microphone permission denied';
        return null;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.ogg';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          bitRate: AppConstants.audioBitRate,
          sampleRate: AppConstants.audioSampleRate,
          numChannels: AppConstants.audioChannels,
        ),
        path: path,
      );
      return path;
    } catch (error) {
      _lastError = 'Recording error: $error';
      return null;
    }
  }

  Future<String?> stopRecording() async {
    try {
      return await _recorder.stop();
    } catch (error) {
      _lastError = 'Stop error: $error';
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  Future<Map<String, dynamic>?> uploadAudio(
    String filePath,
    double durationSeconds,
  ) async {
    try {
      _lastError = null;
      final supabase = Supabase.instance.client;

      final file = File(filePath);
      if (!await file.exists()) throw Exception('File not found');

      final fileSize = await file.length();
      debugPrint('[AudioService] uploadAudio start fileSize=$fileSize');
      final session = supabase.auth.currentSession;
      if (session == null) throw Exception('No active session');

      debugPrint('[AudioService] requesting upload URL');
      final response = await http.post(
        Uri.parse(AppConstants.generateUploadUrlEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConstants.supabaseAnonKey,
        },
        body: jsonEncode({
          'fileExtension': 'ogg',
          'contentType': 'audio/ogg',
          'mediaType': 'audio',
          'durationSeconds': durationSeconds,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Edge function error: ${response.statusCode} - ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final uploadUrl = data['uploadUrl'] as String;
      final mediaFileId = data['mediaFileId'] as String;
      final fileKey = data['fileKey'] as String;
      debugPrint('[AudioService] upload URL ok mediaFileId=$mediaFileId');

      final fileBytes = await file.readAsBytes();
      debugPrint('[AudioService] uploading audio bytes to S3');
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Content-Type': 'audio/ogg',
          'Content-Length': fileSize.toString(),
        },
        body: fileBytes,
      );

      if (uploadResponse.statusCode != 200) {
        throw Exception('S3 upload failed: ${uploadResponse.statusCode}');
      }
      debugPrint('[AudioService] S3 upload ok mediaFileId=$mediaFileId');

      try {
        debugPrint('[AudioService] updating media file size');
        await supabase
            .from('media_files')
            .update({'file_size_bytes': fileSize})
            .eq('id', mediaFileId)
            .timeout(const Duration(seconds: 5));
        debugPrint('[AudioService] media file size update ok');
      } catch (error) {
        debugPrint('[AudioService] media file size update skipped: $error');
      }

      return {
        'mediaFileId': mediaFileId,
        'fileKey': fileKey,
      };
    } catch (error) {
      _lastError = 'Upload failed: $error';
      debugPrint('Upload error: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>?> createYap({
    required String mediaFileId,
    required String postId,
    String selectedFilter = 'normal',
    String? parentYapId,
  }) async {
    try {
      _lastError = null;
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('No active session');

      final response = await http.post(
        Uri.parse(AppConstants.createYapEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConstants.supabaseAnonKey,
        },
        body: jsonEncode({
          'mediaFileId': mediaFileId,
          'postId': postId,
          'selectedFilter': selectedFilter,
          if (parentYapId != null) 'parentYapId': parentYapId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Create yap failed: ${response.statusCode} - ${response.body}',
        );
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      _lastError = 'Create yap failed: $error';
      debugPrint('Create yap error: $error');
      return null;
    }
  }

  Future<void> playAudio(String url) async {
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (error) {
      _lastError = 'Playback error: $error';
    }
  }

  Future<void> playLocalFile(String path) async {
    try {
      await _player.setFilePath(path);
      await _player.play();
    } catch (error) {
      _lastError = 'Local playback error: $error';
    }
  }

  Future<void> pauseAudio() async => _player.pause();

  Future<void> stopAudio() async => _player.stop();

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<Duration> get positionStream => _player.positionStream;

  Duration? get duration => _player.duration;

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
