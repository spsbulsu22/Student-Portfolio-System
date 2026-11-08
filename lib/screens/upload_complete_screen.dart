import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../widgets/primary_action_button.dart';

const _titleNavy = Color(0xFF001B6E);

/// Figma frame: "5 - Upload Complete" (student only, shown after the
/// "Uploading file..." overlay finishes).
///
/// "Return Home" (and the system back button) go straight back to the Home
/// screen, clearing Quick Upload / Upload Review from the stack.
class UploadCompleteScreen extends StatelessWidget {
  const UploadCompleteScreen({super.key});

  void _returnHome(BuildContext context) {
    // Home is the first route of the stack (Login was replaced by it).
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // back = Return Home, not back to the review screen
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _returnHome(context);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                // The spacers use the Figma gaps (169 / 210 / 69 / 92 on a
                // 926 tall frame) as ratios, so it fits any screen height.
                child: Column(
                  children: [
                    const Spacer(flex: 169),
                    const SuccessBadge(),
                    const SizedBox(
                      height: 44,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          'Upload Complete!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _titleNavy,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 210),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Text(
                        'Your file has been successfully uploaded into your portfolio.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const Spacer(flex: 69),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: PrimaryActionButton(
                        label: 'Return Home',
                        width: double.infinity,
                        onPressed: () => _returnHome(context),
                      ),
                    ),
                    const Spacer(flex: 92),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma "ix:success-filled": 250px blue gradient circle with a white check.
/// Pops in with a short ease-out scale + fade when the screen opens.
///
/// Shared by the other success pages (e.g. Change Password Successful);
/// [size] is 250 in the Figma phone frames.
class SuccessBadge extends StatelessWidget {
  const SuccessBadge({super.key, this.size = 250});

  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.instructorGradientStart, // #007EDE
              AppColors.instructorGradientEnd, // #004478
            ],
          ),
        ),
        child: const CustomPaint(painter: _CheckPainter()),
      ),
    );
  }
}

/// Thick white check mark, drawn on a 250 x 250 circle (flat ends, sharp joint).
class _CheckPainter extends CustomPainter {
  const _CheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 250;
    // points relative to the circle center (taken from the Figma frame)
    final c = Offset(size.width / 2, size.height / 2);
    Offset p(double x, double y) => c + Offset(x * s * 1.2, y * s * 1.2);

    final path = Path()
      ..moveTo(p(-49, -2).dx, p(-49, -2).dy)
      ..lineTo(p(-11, 41).dx, p(-11, 41).dy)
      ..lineTo(p(54, -36).dx, p(54, -36).dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24 * s * 1.2
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
