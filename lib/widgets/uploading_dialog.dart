import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../theme/app_colors.dart';

const _textMuted = Color(0xFF52718A);
const _trackFill = Color(0xFFE2EEFA);
const _iconCircle = Color(0xFFD3E7FF);

/// Figma: "Uploading dialog".
///
/// Shows the overlay in the exact center of the screen, dims the background
/// and fades it in ("dissolve" with a tiny scale-up). It runs the real upload
/// ([task]) and shows its progress. When the upload finishes the bar fills to
/// 100%, stays there for [holdAtEnd] (0.4 seconds) and the dialog closes.
///
/// The Supabase upload is a single request without byte-level progress, so
/// the bar advances smoothly towards 90% while the request runs (paced by the
/// file size), follows the stages reported through [control], and only reaches
/// 100% when the upload has really completed.
///
/// Returns `true` when the upload finished, `false`/`null` when the user
/// cancelled (Cancel upload button or the system back button). If the upload
/// fails, the dialog closes and the error thrown by [task] is rethrown here.
Future<bool?> showUploadingDialog(
  BuildContext context, {
  required String fileName,
  int? totalBytes,
  required UploadControl control,
  required Future<void> Function() task,
  Duration holdAtEnd = const Duration(milliseconds: 400),
}) async {
  Object? failure;
  final done = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false, // only "Cancel upload" closes it
    barrierLabel: 'Uploading',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.5),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => Center(
      child: _UploadingCard(
        fileName: fileName,
        totalBytes: totalBytes,
        control: control,
        task: task,
        holdAtEnd: holdAtEnd,
        onError: (e) => failure = e,
      ),
    ),
    transitionBuilder: (_, animation, __, child) {
      final t = Curves.easeOut.transform(animation.value);
      return Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      );
    },
  );
  if (failure != null) throw failure!;
  return done;
}

class _UploadingCard extends StatefulWidget {
  const _UploadingCard({
    required this.fileName,
    required this.totalBytes,
    required this.control,
    required this.task,
    required this.holdAtEnd,
    required this.onError,
  });
  final String fileName;
  final int? totalBytes;
  final UploadControl control;
  final Future<void> Function() task;
  final Duration holdAtEnd;
  final void Function(Object error) onError;

  @override
  State<_UploadingCard> createState() => _UploadingCardState();
}

class _UploadingCardState extends State<_UploadingCard>
    with SingleTickerProviderStateMixin {
  // Shown fraction (0..1). Driven by the estimate, the reported stages and,
  // at the very end, the real completion.
  late final AnimationController _progress;
  bool _finished = false;

  /// Time the bar takes to reach 90% while waiting: ~1.5 MB/s, between 3 and
  /// 90 seconds. The real upload usually finishes earlier and jumps ahead.
  Duration get _estimate {
    final bytes = widget.totalBytes ?? 1000 * 1000;
    final seconds = (bytes / 1.5e6).clamp(3.0, 90.0);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _progress.animateTo(0.9, duration: _estimate, curve: Curves.easeOut);
    widget.control.progress.addListener(_onReported);
    _run();
  }

  void _onReported(double v) {
    if (!mounted || _finished) return;
    final target = v.clamp(0.0, 0.98).toDouble();
    if (target > _progress.value) {
      _progress.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _run() async {
    try {
      await widget.task();
    } catch (e) {
      if (!mounted) return; // cancelled meanwhile: nothing to show
      _finished = true;
      widget.onError(e);
      Navigator.of(context).pop(false);
      return;
    }
    if (!mounted) return; // cancelled: the dialog is already gone
    _finished = true;
    await _progress.animateTo(
      1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    // Pause on 100% for a moment, then close. If the user cancels during
    // the pause, the dialog is already gone (not mounted) and we skip.
    await Future<void>.delayed(widget.holdAtEnd);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    // Closed before the upload finished (Cancel / system back): tell the
    // upload to undo itself once its request ends.
    if (!_finished) widget.control.cancel();
    widget.control.progress.removeListener(_onReported);
    _progress.dispose();
    super.dispose();
  }

  // Both numbers use the same unit (picked from the total) so they read well:
  // "114 KB of 190 KB", "1.2 MB of 2 MB".
  static String _formatPair(int uploaded, int total) {
    String fmt(double v, String unit, int decimals) {
      var s = v.toStringAsFixed(decimals);
      if (s.contains('.')) {
        s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
      return '$s $unit';
    }

    if (total >= 1000 * 1000) {
      return '${fmt(uploaded / 1e6, 'MB', 1)} of ${fmt(total / 1e6, 'MB', 1)}';
    }
    if (total >= 1000) {
      return '${fmt(uploaded / 1e3, 'KB', 0)} of ${fmt(total / 1e3, 'KB', 0)}';
    }
    return '$uploaded B of $total B';
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 356),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x29002C51), // rgba(0,44,81,0.16)
                  offset: Offset(0, 12),
                  blurRadius: 40,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // status icon
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: _iconCircle,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.upload_file_rounded,
                        size: 28,
                        color: AppColors.menuButton,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // title + file name
                  const Text(
                    'Uploading file…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 22,
                      height: 29 / 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.menuButton,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.fileName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15,
                      height: 22 / 15,
                      fontWeight: FontWeight.w400,
                      color: _textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // progress bar + transfer details (only this part rebuilds)
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) {
                      final p = _progress.value;
                      final total = widget.totalBytes;
                      final left = total == null
                          ? 'Uploading…'
                          : '${_formatPair((total * p).round(), total)} uploaded';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              height: 8,
                              child: Stack(
                                children: [
                                  const Positioned.fill(
                                    child: ColoredBox(color: _trackFill),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: p,
                                    heightFactor: 1,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius:
                                            BorderRadius.all(Radius.circular(4)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  left,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 13,
                                    height: 20 / 13,
                                    fontWeight: FontWeight.w400,
                                    color: _textMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(p * 100).round()}%',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14,
                                  height: 20 / 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.menuButton,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // cancel button (hugs its content, centered)
                  Center(
                    child: Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          widget.control.cancel();
                          Navigator.of(context).pop(false);
                        },
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Cancel upload',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
