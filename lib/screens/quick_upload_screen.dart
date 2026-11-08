import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../utils/slide_route.dart';
import '../widgets/primary_action_button.dart';
import 'upload_review_screen.dart';

const _navy = Color(0xFF0A2381);
const _labelNavy = Color(0xFF001B6E);
const _zoneFill = Color(0xFFD9DFEE);
const _zoneBorder = Color(0xFF636EA3);
const _plusCircle = Color(0xFF9FBCE9);
const _hintBlue = Color(0xFF1B38A2);
const _disabledFill = Color(0xFFD1D5DB);
const _disabledText = Color(0xFF6B7280);

// Width from which the desktop web layout is used (same as Home).
const double _wideBreakpoint = 600;


/// Figma frame: "3 - File Upload" (student only, opened from "Quick Upload").
///
/// Tap the dashed rectangle to pick a file from the phone. The chosen file
/// name and size show under "File Name", and the rectangle switches to the
/// "File Selected Successfully" look with an X button that discards the file. "Next" turns blue once a valid file
/// is chosen and opens the Upload Review screen, where the file is uploaded.
/// The type and the size (50MB max) are checked here, right after picking.
class QuickUploadScreen extends StatefulWidget {
  const QuickUploadScreen({super.key, this.folderId});

  /// My Portfolio folder the file is uploaded into (null = root).
  final String? folderId;

  @override
  State<QuickUploadScreen> createState() => _QuickUploadScreenState();
}

class _QuickUploadScreenState extends State<QuickUploadScreen> {
  PlatformFile? _file;
  int? _size;
  String? _error;
  bool _picking = false;

  Future<void> _pickFile() async {
    if (_picking) return; // ignore double taps while the picker is opening
    _picking = true;
    try {
      final file = await FilePicker.pickFile();
      if (file == null || !mounted) return; // user cancelled

      // Real length of the picked file (falls back to what the picker reported)
      final bytes = await file.length() ?? file.lengthSync();
      if (!mounted) return;

      final problem = validateUploadFile(file.name, bytes);
      if (problem != null) {
        setState(() {
          _file = null;
          _size = null;
          _error = problem;
        });
        return;
      }
      setState(() {
        _file = file;
        _size = bytes;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the file picker. Please try again.');
    } finally {
      _picking = false;
    }
  }

  void _discardFile() {
    setState(() {
      _file = null;
      _size = null;
      _error = null;
    });
  }

  void _next() {
    final file = _file;
    if (file == null) return;
    Navigator.of(context).push(
      SlideFromRightRoute(
        page: UploadReviewScreen(
          file: file,
          fileName: file.name,
          fileSize: _size,
          folderId: widget.folderId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: LayoutBuilder(
          builder: (context, c) => c.maxWidth >= _wideBreakpoint
              ? _buildWeb()
              : _buildPhone(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WEB / DESKTOP LAYOUT (same structure as the Home screen: white top bar +
  // blue dashboard with translucent panels and a white details card).
  // ---------------------------------------------------------------------------
  Widget _buildWeb() {
    final hasFile = _file != null;
    return Column(
      children: [
        _WebTopBar(onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  AppColors.instructorGradientStart,
                  AppColors.instructorGradientEnd,
                ],
                stops: [0.040192, 0.95981],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final desktop = c.maxWidth >= 1000;
                final hPad = c.maxWidth >= 900 ? 40.0 : 24.0;

                final uploadPanel = _WebPanel(
                  title: 'Upload File',
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _DropZone(
                        fileName: _file?.name,
                        onTap: _pickFile,
                        onDiscard: _discardFile,
                      ),
                    ),
                  ),
                );

                final detailsCard = Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'File Details',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _labelNavy,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: AppColors.menuDivider),
                      const SizedBox(height: 20),
                      _FileInfo(file: _file, size: _size, error: _error),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: AppColors.menuDivider),
                      const SizedBox(height: 16),
                      _MetaRow(
                        label: 'Type',
                        value: hasFile ? _extOf(_file!.name) : '—',
                      ),
                      const SizedBox(height: 10),
                      const _MetaRow(label: 'Max size', value: '50MB'),
                      const SizedBox(height: 10),
                      _MetaRow(
                        label: 'Status',
                        value: hasFile ? 'Ready for review' : 'Waiting for file',
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          PrimaryActionButton(
                            label: 'Home',
                            width: 104,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          _NextButton(enabled: hasFile, onPressed: _next),
                        ],
                      ),
                    ],
                  ),
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Big faint logo in the corner (decoration only)
                    Positioned(
                      right: -90,
                      bottom: -90,
                      width: 460,
                      height: 460,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.07,
                          child: SvgPicture.asset(
                            'assets/images/logo.svg',
                            colorFilter: const ColorFilter.mode(
                                Colors.white, BlendMode.srcIn),
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(hPad, 40, hPad, 56),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'File Upload',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 40,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Choose a work file to add to your portfolio.',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 32),
                              if (desktop)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: uploadPanel),
                                    const SizedBox(width: 24),
                                    SizedBox(width: 400, child: detailsCard),
                                  ],
                                )
                              else ...[
                                uploadPanel,
                                const SizedBox(height: 24),
                                detailsCard,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static String _extOf(String name) {
    final i = name.lastIndexOf('.');
    return (i < 0 || i == name.length - 1)
        ? 'File'
        : name.substring(i + 1).toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // PHONE LAYOUT (unchanged from the original).
  // ---------------------------------------------------------------------------
  Widget _buildPhone() {
    final inset = MediaQuery.viewPaddingOf(context);
    final topPad = inset.top + 12;
    final bottomPad = inset.bottom + 12;
    final hasFile = _file != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Column(
        children: [
          _Header(
            topPad: topPad,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DropZone(
                        fileName: _file?.name,
                        onTap: _pickFile,
                        onDiscard: _discardFile,
                      ),
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _FileInfo(
                          file: _file,
                          size: _size,
                          error: _error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(45, 8, 39, 43 + bottomPad),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PrimaryActionButton(
                  label: 'Home',
                  width: 104,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                _NextButton(enabled: hasFile, onPressed: _next),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White top bar of the web layout (same bar as the Home screen: 72px high,
/// divider underneath, round blue button at the far left, brand next to it).
class _WebTopBar extends StatelessWidget {
  const _WebTopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.menuDivider)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final showBrand = c.maxWidth >= 1000;
          return Row(
            children: [
              Tooltip(
                message: 'Back',
                child: Material(
                  color: AppColors.menuButton,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onBack,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.chevron_left_rounded,
                          size: 29, color: Colors.white),
                    ),
                  ),
                ),
              ),
              if (showBrand) ...[
                const SizedBox(width: 16),
                SvgPicture.asset('assets/images/logo.svg',
                    width: 34, height: 34),
                const SizedBox(width: 12),
                const Text(
                  'Student Portfolio System',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandText,
                  ),
                ),
              ],
              const SizedBox(width: 24),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onBack,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Home',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.menuMuted,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.menuMuted),
              ),
              const Text(
                'Quick Upload',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.menuText,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Translucent white card on the blue background, with a heading
/// (same look as the Home screen panels).
class _WebPanel extends StatelessWidget {
  const _WebPanel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

/// "Label ........ value" row in the details card.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.menuMuted,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.menuText,
          ),
        ),
      ],
    );
  }
}

/// Same header as My Portfolio / Favorites / Notifications / Profile.
class _Header extends StatelessWidget {
  const _Header({required this.topPad, required this.onBack});
  final double topPad;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 62 + topPad,
      padding: EdgeInsets.fromLTRB(24, 12 + topPad, 24, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            AppColors.instructorGradientStart, // #007EDE
            AppColors.instructorGradientEnd, // #004478
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            color: const Color(0x33FFFFFF), // white @ 20%
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onBack,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.chevron_left, size: 20, color: Colors.white),
              ),
            ),
          ),
          const Text(
            'File Upload',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// The big dashed rectangle.
///
/// RESPONSIVE: it is always as wide as the screen allows and keeps the Figma
/// proportions (402 : 263). Everything inside (circle, texts, X button) is
/// designed on a 402 x 263 canvas and scaled together with the rectangle, so
/// it looks the same on small phones, big phones and tablets, and never
/// changes shape when a file is added or removed. The dashed border is drawn
/// on top at the real size, so its line stays 2px thin.
///
/// Two looks, like the Figma "Upload" states:
///  - no file: plus icon, "Tap to choose a file" (tappable)
///  - file chosen: check icon, "File Selected Successfully" + the file name
///    and an X button that discards the file (rectangle is not tappable)
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.fileName,
    required this.onTap,
    required this.onDiscard,
  });
  final String? fileName;
  final VoidCallback onTap;
  final VoidCallback onDiscard;

  static const double _designW = 402;
  static const double _designH = 263;

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null;
    return AspectRatio(
      aspectRatio: _designW / _designH,
      child: Material(
        color: _zoneFill,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: hasFile ? null : onTap,
          child: RepaintBoundary(
            child: CustomPaint(
              foregroundPainter: const _DashedRRectPainter(
                color: _zoneBorder,
                radius: 20,
              ),
              // Phone text-size settings must not resize this fixed artwork.
              child: MediaQuery.withNoTextScaling(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _designW,
                    height: _designH,
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 61, 10, 0),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 70px circle with a plus or a check
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    color: _plusCircle.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: hasFile
                                        ? const _Check()
                                        : const _Plus(),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                _FixedLine(
                                  text: hasFile
                                      ? 'File Selected Successfully'
                                      : 'Tap to choose a file',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: _navy,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                _FixedLine(
                                  text: hasFile
                                      ? fileName!
                                      : 'Documents, images and other work files up to 50MB',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: _hintBlue.withValues(alpha: 0.5),
                                  ),
                                  ellipsis: hasFile,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // X button (Figma: 40px circle, 15px from the top,
                        // 13px from the right). Discards the chosen file.
                        if (hasFile)
                          Positioned(
                            top: 15,
                            right: 13,
                            child: _DiscardButton(onTap: onDiscard),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One text line in a fixed 26px-high slot (Figma text height). It never wraps:
/// the hint text shrinks to fit, and a long file name is cut with "...".
class _FixedLine extends StatelessWidget {
  const _FixedLine({
    required this.text,
    required this.style,
    this.ellipsis = false,
  });
  final String text;
  final TextStyle style;
  final bool ellipsis;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      width: double.infinity,
      child: Center(
        child: ellipsis
            ? Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: style)
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text, maxLines: 1, style: style),
              ),
      ),
    );
  }
}

/// Figma: 40px circle (#9FBCE9 @ 50%) with a navy X, top-right of the zone.
class _DiscardButton extends StatelessWidget {
  const _DiscardButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _plusCircle.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: CustomPaint(
              size: Size(15, 15),
              painter: _XPainter(color: Color(0xFF1B2F9E)),
            ),
          ),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  const _XPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.butt;
    // inset a little so the butt ends stay inside the 15px box
    canvas.drawLine(const Offset(1, 1), Offset(size.width - 1, size.height - 1), paint);
    canvas.drawLine(Offset(size.width - 1, 1), Offset(1, size.height - 1), paint);
  }

  @override
  bool shouldRepaint(_XPainter old) => old.color != color;
}

/// Check mark inside the 70px circle (Figma: two 5px navy strokes).
class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(42, 24),
      painter: _CheckPainter(color: Color(0xFF1B2F9E)),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.butt;
    final path = Path()
      ..moveTo(2, size.height * 0.5)
      ..lineTo(size.width * 0.36, size.height - 2)
      ..lineTo(size.width - 2, 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

class _Plus extends StatelessWidget {
  const _Plus();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1B2F9E);
    return SizedBox(
      width: 21,
      height: 21,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 21,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Container(
            width: 5,
            height: 21,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a dashed rounded-rectangle border (Flutter has no built-in one).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 2,
    this.dash = 8,
    this.gap = 6,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}

/// "File Name" label + the chosen file (or "No file selected...").
class _FileInfo extends StatelessWidget {
  const _FileInfo({required this.file, required this.size, required this.error});
  final PlatformFile? file;
  final int? size;
  final String? error;

  static String _formatSize(int bytes) {
    // Decimal units (1 KB = 1000 B) so it matches the phone's file manager.
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'File Name',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _labelNavy,
          ),
        ),
        const SizedBox(height: 12),
        if (file == null)
          Text(
            'No file selected...',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          )
        else ...[
          Text(
            file!.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          if (size != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatSize(size!),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFFD32F2F),
            ),
          ),
        ],
      ],
    );
  }
}

/// Figma "Primary_Action_Button": Disabled = grey (#D1D5DB, radius 8,
/// text #6B7280), Default = blue (radius 10). 124 x 48.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(enabled ? 10 : 8);
    return Material(
      color: enabled ? AppColors.primary : _disabledFill,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 124,
          height: 48,
          child: Center(
            child: Text(
              'Next',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: enabled ? Colors.white : _disabledText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
