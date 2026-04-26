import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../record/services/audio_service.dart';
import '../models/feed_models.dart';
import '../providers/feed_provider.dart';

// ---------------------------------------------------------------------------
// YapReplyPreview — lightweight snippet passed to hold button + preview sheet
// ---------------------------------------------------------------------------
class YapReplyPreview {
  final String username;
  final String avatarEmoji;
  final Color avatarColor;

  const YapReplyPreview({
    required this.username,
    required this.avatarEmoji,
    required this.avatarColor,
  });
}

// ---------------------------------------------------------------------------
// YapHoldButton
//
// Hold to record inline (no modal). Release → preview sheet.
// While recording: button shrinks right, waveform fills left.
// Slide left > 80px to cancel.
// ---------------------------------------------------------------------------
class YapHoldButton extends ConsumerStatefulWidget {
  final String postId;
  final String? parentYapId;
  final YapReplyPreview? replyPreview; // set when this is a reply-to-yap
  final Widget child;

  const YapHoldButton({
    super.key,
    required this.postId,
    required this.child,
    this.parentYapId,
    this.replyPreview,
  });

  @override
  ConsumerState<YapHoldButton> createState() => _YapHoldButtonState();
}

class _YapHoldButtonState extends ConsumerState<YapHoldButton>
    with TickerProviderStateMixin {
  static const int _maxSeconds = 30;
  static const int _minMs = 800;

  bool _isRecording = false;
  bool _cancelled = false;
  bool _cancelPending = false; // swipe threshold crossed but not released
  int _recordedMs = 0;
  String? _localPath;
  Timer? _durationTimer;
  Timer? _amplitudeTimer;

  // Smoothed amplitudes for waveform
  final List<double> _amplitudes = List.filled(32, 0.05);
  final List<double> _smoothed = List.filled(32, 0.05);
  final _recorder = AudioRecorder();
  DateTime? _recordStart;

  // Animation for waveform repaints
  late final AnimationController _waveController;
  late final AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // 60fps tick
    )..repeat();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _maxSeconds),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    _waveController.dispose();
    _ringController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Gesture handlers
  // ---------------------------------------------------------------------------

  Future<void> _onLongPressStart(LongPressStartDetails _) async {
    HapticFeedback.mediumImpact();
    _cancelled = false;
    _cancelPending = false;
    _recordedMs = 0;
    _amplitudes.fillRange(0, _amplitudes.length, 0.05);
    _smoothed.fillRange(0, _smoothed.length, 0.05);

    final audioService = ref.read(audioServiceProvider);
    final path = await audioService.startRecording();
    if (path == null || !mounted || _cancelled) {
      await audioService.cancelRecording();
      return;
    }

    _localPath = path;
    _recordStart = DateTime.now();

    setState(() => _isRecording = true);
    _ringController.forward(from: 0);

    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted || _cancelled) return t.cancel();
      final elapsed = DateTime.now().difference(_recordStart!).inMilliseconds;
      setState(() => _recordedMs = elapsed);
      if (elapsed >= _maxSeconds * 1000) {
        t.cancel();
        _onLongPressEnd(null);
      }
    });

    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!mounted || _cancelled) return;
      try {
        final amp = await _recorder.getAmplitude();
        final raw = ((amp.current + 60) / 60).clamp(0.05, 1.0);
        _amplitudes.removeAt(0);
        _amplitudes.add(raw);
        // Smooth each bar toward target
        for (int i = 0; i < _smoothed.length; i++) {
          _smoothed[i] += (_amplitudes[i] - _smoothed[i]) * 0.35;
        }
        if (raw > 0.7) HapticFeedback.selectionClick();
      } catch (_) {}
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final dx = details.offsetFromOrigin.dx;
    final wasPending = _cancelPending;
    final nowPending = dx < -60;
    if (nowPending != wasPending) {
      setState(() => _cancelPending = nowPending);
    }
    if (dx < -120 && !_cancelled) {
      _cancelRecording();
    }
  }

  Future<void> _onLongPressEnd(LongPressEndDetails? _) async {
    if (_cancelled) return;
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    _ringController.stop();

    final audioService = ref.read(audioServiceProvider);
    final path = await audioService.stopRecording();
    if (!mounted) return;

    final elapsed = _recordedMs;
    final amplitudeSnapshot = List<double>.from(_smoothed);
    setState(() {
      _isRecording = false;
      _cancelPending = false;
    });

    if (elapsed < _minMs) {
      HapticFeedback.lightImpact();
      _showTooShortSnack();
      return;
    }

    HapticFeedback.lightImpact();

    if (mounted) {
      YapPreviewSheet.show(
        context,
        postId: widget.postId,
        parentYapId: widget.parentYapId,
        replyPreview: widget.replyPreview,
        localPath: path ?? _localPath ?? '',
        durationSeconds: elapsed / 1000.0,
        amplitudes: amplitudeSnapshot,
      );
    }
  }

  Future<void> _cancelRecording() async {
    _cancelled = true;
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    _ringController.stop();

    setState(() {
      _isRecording = false;
      _cancelPending = false;
    });
    HapticFeedback.heavyImpact();

    final audioService = ref.read(audioServiceProvider);
    await audioService.cancelRecording();
  }

  void _showTooShortSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Hold longer to record a yap'),
      backgroundColor: AppColors.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_isRecording) {
      // Idle — show normal child button
      return GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        onLongPressCancel: () => _cancelRecording(),
        child: widget.child,
      );
    }

    // Recording — inline layout: [waveform + timer] [mic icon]
    final secs = (_recordedMs / 1000).toStringAsFixed(1);
    final cancelColor =
        _cancelPending ? AppColors.error : AppColors.primary;

    return GestureDetector(
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: () => _cancelRecording(),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _cancelPending
              ? AppColors.error.withValues(alpha: 0.08)
              : AppColors.primaryGlow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cancelColor.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            // LEFT: waveform + labels
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Waveform painter
                    SizedBox(
                      height: 24,
                      child: AnimatedBuilder(
                        animation: _waveController,
                        builder: (_, __) => CustomPaint(
                          painter: _InlineWavePainter(
                            amplitudes: _smoothed,
                            color: cancelColor,
                            cancelPending: _cancelPending,
                          ),
                          size: const Size(double.infinity, 24),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Timer + cancel hint
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: cancelColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _cancelPending ? '← release to cancel' : '${secs}s · slide ← to cancel',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: cancelColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // RIGHT: mic icon + progress ring
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: AnimatedBuilder(
                animation: _ringController,
                builder: (_, __) => CustomPaint(
                  painter: _ProgressRingPainter(
                    progress: _ringController.value,
                    color: cancelColor,
                  ),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.mic_rounded,
                      color: cancelColor,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _InlineWavePainter — CustomPainter for live waveform bars
// ---------------------------------------------------------------------------
class _InlineWavePainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;
  final bool cancelPending;

  _InlineWavePainter({
    required this.amplitudes,
    required this.color,
    required this.cancelPending,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = amplitudes.length;
    final barWidth = 2.5;
    final spacing = (size.width - barCount * barWidth) / (barCount - 1);
    final midY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final amp = amplitudes[i];
      final h = (amp * size.height).clamp(2.0, size.height);
      final x = i * (barWidth + spacing);

      // Glow layer
      final glowPaint = Paint()
        ..color = color.withValues(alpha: amp * 0.25)
        ..strokeWidth = barWidth + 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x + barWidth / 2, midY - h * 0.6),
        Offset(x + barWidth / 2, midY + h * 0.6),
        glowPaint,
      );

      // Foreground bar
      final barPaint = Paint()
        ..color = color.withValues(alpha: 0.4 + amp * 0.6)
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x + barWidth / 2, midY - h / 2),
        Offset(x + barWidth / 2, midY + h / 2),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_InlineWavePainter old) => true;
}

// ---------------------------------------------------------------------------
// _ProgressRingPainter — thin ring around mic button showing 30s countdown
// ---------------------------------------------------------------------------
class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ProgressRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      2 * 3.14159 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress || old.color != color;
}

// ---------------------------------------------------------------------------
// YapPreviewSheet
// ---------------------------------------------------------------------------
class YapPreviewSheet extends ConsumerStatefulWidget {
  final String postId;
  final String? parentYapId;
  final YapReplyPreview? replyPreview;
  final String localPath;
  final double durationSeconds;
  final List<double> amplitudes;

  const YapPreviewSheet({
    super.key,
    required this.postId,
    required this.parentYapId,
    required this.localPath,
    required this.durationSeconds,
    required this.amplitudes,
    this.replyPreview,
  });

  static Future<void> show(
    BuildContext context, {
    required String postId,
    String? parentYapId,
    YapReplyPreview? replyPreview,
    required String localPath,
    required double durationSeconds,
    required List<double> amplitudes,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => YapPreviewSheet(
        postId: postId,
        parentYapId: parentYapId,
        replyPreview: replyPreview,
        localPath: localPath,
        durationSeconds: durationSeconds,
        amplitudes: amplitudes,
      ),
    );
  }

  @override
  ConsumerState<YapPreviewSheet> createState() => _YapPreviewSheetState();
}

class _YapPreviewSheetState extends ConsumerState<YapPreviewSheet> {
  String _selectedFilter = 'normal';
  bool _publishing = false;

  Future<void> _publish() async {
    setState(() => _publishing = true);

    final user = Supabase.instance.client.auth.currentUser;
    final profile = user != null
        ? await _fetchProfile(user.id)
        : const FeedProfile(
            id: '',
            username: 'you',
            avatarEmoji: '👤',
            avatarColor: AppColors.primary,
          );

    final postId = widget.postId;
    final parentYapId = widget.parentYapId;
    final selectedFilter = _selectedFilter;
    final path = widget.localPath;
    final durationSeconds = widget.durationSeconds;

    // Insert optimistic pending yap into the feed
    final tempId = ref.read(feedProvider.notifier).addOptimisticYap(
          postId: postId,
          parentYapId: parentYapId,
          profile: profile,
          durationSeconds: durationSeconds,
          localAudioPath: path,
        );
    debugPrint('[YapPreview] STEP 1 addOptimisticYap tempId=$tempId');

    final audioService = ref.read(audioServiceProvider);

    // Upload to S3
    final uploadResult = await audioService.uploadAudio(path, durationSeconds);
    final mediaFileId = uploadResult?['mediaFileId'] as String?;
    debugPrint('[YapPreview] STEP 2 upload mediaFileId=$mediaFileId');

    if (mediaFileId == null) {
      ref.read(feedProvider.notifier).failYap(tempId, postId);
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Upload failed. Try again.'),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }

    // Create the yap row in DB via edge function
    debugPrint('[YapPreview] STEP 3 calling create-yap');
    final yapResult = await audioService.createYap(
      mediaFileId: mediaFileId,
      postId: postId,
      selectedFilter: selectedFilter,
      parentYapId: parentYapId,
    );
    debugPrint('[YapPreview] STEP 4 create-yap result=${yapResult != null}');

    if (yapResult == null || yapResult['yap'] == null) {
      ref.read(feedProvider.notifier).failYap(tempId, postId);
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not publish yap. Try again.'),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }

    // Confirm the optimistic yap with the real server data
    final serverYap = FeedYap.fromServerMap(
      yapResult['yap'] as Map<String, dynamic>,
    );
    final yapWithMediaId = serverYap.media == null
        ? serverYap
        : serverYap.copyWith(
            media: serverYap.media!.copyWith(id: mediaFileId),
          );
    ref.read(feedProvider.notifier).confirmYap(tempId, yapWithMediaId);
    debugPrint('[YapPreview] STEP 5 confirmYap done');

    // Start watching for processed audio (background, fire-and-forget)
    try {
      ref.read(feedProvider.notifier).watchMediaProcessing(mediaFileId);
    } catch (e) {
      debugPrint('[YapPreview] watchMediaProcessing skipped: $e');
    }

    // Now safe to close the sheet
    if (mounted) Navigator.of(context).pop();
  }

  Future<FeedProfile> _fetchProfile(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_emoji, avatar_color')
          .eq('id', userId)
          .single();
      return FeedProfile.fromMap(data);
    } catch (_) {
      return FeedProfile(
        id: userId,
        username: 'you',
        avatarEmoji: '👤',
        avatarColor: AppColors.primary,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = widget.durationSeconds.toStringAsFixed(1);
    final reply = widget.replyPreview;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // "Replying to" chip — only shown for replies
          if (reply != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: reply.avatarColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: reply.avatarColor, width: 1),
                    ),
                    child: Center(
                      child: Text(reply.avatarEmoji,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Replying to @${reply.username}',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const Gap(14),
          ],

          Text(
            reply != null ? 'Your Reply' : 'Your Yap',
            style: AppTextStyles.headlineMedium,
          ),
          const Gap(4),
          Text('${secs}s recorded', style: AppTextStyles.labelSmall),
          const Gap(16),

          _FrozenWaveform(amplitudes: widget.amplitudes),
          const Gap(20),

          Text('Choose a voice style', style: AppTextStyles.bodyMedium),
          const Gap(12),
          _FilterSelector(
            selected: _selectedFilter,
            onChanged: (f) => setState(() => _selectedFilter = f),
          ),
          const Gap(24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _publishing ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Re-record'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_publishing ? 'Sending...' : 'Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FrozenWaveform
// ---------------------------------------------------------------------------
class _FrozenWaveform extends StatelessWidget {
  final List<double> amplitudes;
  const _FrozenWaveform({required this.amplitudes});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: CustomPaint(
        painter: _InlineWavePainter(
          amplitudes: amplitudes,
          color: AppColors.primary,
          cancelPending: false,
        ),
        size: const Size(double.infinity, 56),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FilterSelector
// ---------------------------------------------------------------------------
class _FilterSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterSelector({required this.selected, required this.onChanged});

  static const _filters = [
    ('normal', '🎤', 'Normal'),
    ('chipmunk', '🐿️', 'Chipmunk'),
    ('deep', '🔊', 'Deep'),
    ('robot', '🤖', 'Robot'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _filters.map((f) {
        final (id, emoji, label) = f;
        final isSelected = selected == id;
        return GestureDetector(
          onTap: () => onChanged(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primaryGlow
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const Gap(4),
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
