import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../services/media_url_service.dart';

// ---------------------------------------------------------------------------
// AudioPlaybackState
// ---------------------------------------------------------------------------
class AudioPlaybackState {
  final String? currentYapId;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;

  const AudioPlaybackState({
    this.currentYapId,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  bool isPlayingYap(String yapId) => currentYapId == yapId && isPlaying;
  bool isLoadingYap(String yapId) => currentYapId == yapId && isLoading;

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  AudioPlaybackState copyWith({
    String? currentYapId,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    bool clearCurrentYap = false,
  }) {
    return AudioPlaybackState(
      currentYapId: clearCurrentYap ? null : (currentYapId ?? this.currentYapId),
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

// ---------------------------------------------------------------------------
// _LifecycleObserver — pauses player when app backgrounds
// ---------------------------------------------------------------------------
class _LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onPause;
  _LifecycleObserver(this.onPause);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      onPause();
    }
  }
}

// ---------------------------------------------------------------------------
// AudioPlayerNotifier — single global player, enforces one-at-a-time invariant
// Pauses when app backgrounds.
// ---------------------------------------------------------------------------
class AudioPlayerNotifier extends Notifier<AudioPlaybackState> {
  late final AudioPlayer _player;
  late final _LifecycleObserver _lifecycleObserver;

  @override
  AudioPlaybackState build() {
    _player = AudioPlayer();

    // Pause whenever the app goes to background / phone is closed
    _lifecycleObserver = _LifecycleObserver(() {
      if (state.isPlaying) {
        _player.pause();
      }
    });
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
      _player.dispose();
    });

    _player.positionStream.listen((pos) {
      if (state.currentYapId != null) {
        state = state.copyWith(position: pos);
      }
    });

    _player.durationStream.listen((dur) {
      if (dur != null && state.currentYapId != null) {
        state = state.copyWith(duration: dur);
      }
    });

    _player.playerStateStream.listen((ps) async {
      if (ps.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
        await _player.pause();
        state = state.copyWith(
          isPlaying: false,
          isLoading: false,
          position: Duration.zero,
        );
      } else if (state.currentYapId != null) {
        // Stream is single source of truth — sync isPlaying with actual player
        if (state.isPlaying != ps.playing) {
          state = state.copyWith(isPlaying: ps.playing);
        }
      }
    });

    return const AudioPlaybackState();
  }

  /// Play a yap by its id and S3 file key.
  /// Stops any currently playing yap first.
  Future<void> play(String yapId, String fileKey) async {
    // Toggle: tapping an already-playing yap pauses it
    if (state.currentYapId == yapId && state.isPlaying) {
      await _player.pause(); // stream will set isPlaying: false
      return;
    }

    // Resume same yap if paused
    if (state.currentYapId == yapId && !state.isPlaying && !state.isLoading) {
      await _player.play(); // stream will set isPlaying: true
      return;
    }

    // Switch to a different yap
    await _player.stop();
    state = AudioPlaybackState(
      currentYapId: yapId,
      isLoading: true,
    );

    try {
      final url = await ref.read(mediaUrlServiceProvider).getUrl(fileKey);
      if (url == null) {
        state = state.copyWith(isLoading: false, clearCurrentYap: true);
        return;
      }

      await _player.setUrl(url);
      final dur = _player.duration ?? Duration.zero;
      state = state.copyWith(
        isLoading: false,
        isPlaying: true,
        duration: dur,
        position: Duration.zero,
      );
      await _player.play();
    } catch (e) {
      state = state.copyWith(isLoading: false, clearCurrentYap: true);
    }
  }

  Future<void> pause() async {
    await _player.pause(); // stream handles state update
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    state = state.copyWith(position: position);
  }

  Future<void> stop() async {
    await _player.stop();
    state = const AudioPlaybackState();
  }
}

final audioPlayerProvider =
    NotifierProvider<AudioPlayerNotifier, AudioPlaybackState>(
  AudioPlayerNotifier.new,
);
