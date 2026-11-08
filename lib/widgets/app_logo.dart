import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app logo (assets/images/logo.svg), drawn directly in code.
///
/// An SVG file has to be loaded and parsed AFTER the page appears, so it pops
/// in late (most visible on web, after a reload). This widget draws the exact
/// same shape from path data, so it is on screen in the very first frame, with
/// no loading at all. Any color works (the Instructor login uses white).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 155,
    this.color = AppColors.brandText, // #007EDE, same as logo.svg
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(color)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.color);

  final Color color;

  /// logo.svg uses a 155 x 155 viewBox.
  static const double _box = 155;

  // Built once and shared by every logo on screen.
  static final Path _path = _buildPath();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _box, size.height / _box);
    canvas.drawPath(
      _path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.color != color;

  static Path _buildPath() {
    return Path()
      ..moveTo(78.895, 98.6796)
      ..cubicTo(88.9506, 108.672, 104.193, 108.929, 114.703, 98.4859)
      ..lineTo(146.558, 66.6334)
      ..cubicTo(148.053, 65.0114, 148.053, 62.4816, 146.494, 61.0562)
      ..cubicTo(144.872, 59.6279, 142.666, 59.6279, 141.042, 61.1835)
      ..lineTo(109.452, 92.7786)
      ..cubicTo(101.993, 100.238, 91.4832, 100.238, 84.5414, 93.1024)
      ..cubicTo(77.4696, 85.8368, 77.3395, 75.521, 84.8016, 68.0616)
      ..lineTo(124.631, 28.3595)
      ..cubicTo(129.563, 23.4299, 136.245, 23.3635, 140.397, 27.3879)
      ..cubicTo(144.482, 31.4096, 144.418, 38.0912, 139.423, 43.0845)
      ..lineTo(100.625, 82.0725)
      ..cubicTo(99.0699, 83.6945, 96.994, 83.6308, 95.5658, 82.0725)
      ..cubicTo(93.9438, 80.517, 94.0103, 78.5047, 95.6322, 76.8828)
      ..lineTo(123.073, 49.4422)
      ..cubicTo(124.695, 47.8203, 124.631, 45.6143, 123.203, 44.1224)
      ..cubicTo(121.708, 42.697, 119.569, 42.6305, 117.947, 44.3162)
      ..lineTo(90.3124, 71.8895)
      ..cubicTo(85.7731, 76.4288, 85.7731, 83.437, 89.9886, 87.5888)
      ..cubicTo(94.4642, 91.9344, 101.016, 91.9344, 105.621, 87.3287)
      ..lineTo(144.676, 48.3406)
      ..cubicTo(152.786, 40.1671, 152.656, 29.4638, 145.324, 22.1318)
      ..cubicTo(138.058, 14.9962, 127.094, 14.8025, 119.181, 22.7795)
      ..lineTo(79.1552, 62.8054)
      ..cubicTo(68.6456, 73.315, 68.9695, 88.7541, 78.895, 98.6796)
      ..close()
      ..moveTo(22.3283, 140.197)
      ..lineTo(129.237, 140.197)
      ..cubicTo(142.664, 140.197, 149.345, 133.646, 149.345, 120.413)
      ..lineTo(149.345, 79.4762)
      ..lineTo(138.902, 90.1187)
      ..lineTo(138.902, 119.893)
      ..cubicTo(138.902, 126.51, 135.462, 129.754, 129.104, 129.754)
      ..lineTo(22.4612, 129.754)
      ..cubicTo(16.037, 129.754, 12.6629, 126.51, 12.6629, 119.893)
      ..lineTo(12.6629, 46.7214)
      ..cubicTo(12.6629, 40.1062, 16.037, 36.7959, 22.4612, 36.7959)
      ..lineTo(89.0143, 36.7959)
      ..lineTo(99.3937, 26.4164)
      ..lineTo(22.3283, 26.4164)
      ..cubicTo(8.8959, 26.4137, 2.2143, 32.9015, 2.2143, 46.1983)
      ..lineTo(2.2143, 120.413)
      ..cubicTo(2.2143, 133.646, 8.8959, 140.197, 22.3228, 140.197);
  }
}
