import 'package:flutter/material.dart';

/// Builds an icon at [size] in [color]. Lets an item use a drawn logo where
/// the app otherwise uses an [IconData].
typedef IconWidgetBuilder = Widget Function(double size, Color color);

/// The Community logo (Figma reference "Frame.png"): a globe made of an outer
/// circle, one vertical ellipse (meridian) and the equator line.
///
/// It is drawn as a vector, so it is sharp at any size and takes whatever
/// color the place that shows it gives (white tile -> blue, side menu -> blue).
/// The Home tile and the side-menu item of BOTH accounts use this one builder,
/// so they always look the same. [kCommunityFallbackIcon] is only the
/// `IconData` the item classes require; it is never drawn.
Widget communityIconBuilder(double size, Color color) =>
    CommunityGlobeIcon(size: size, color: color);

const IconData kCommunityFallbackIcon = Icons.public;

class CommunityGlobeIcon extends StatelessWidget {
  const CommunityGlobeIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GlobePainter(color)),
      );
}

class _GlobePainter extends CustomPainter {
  _GlobePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24; // drawn on a 24 x 24 grid
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * u
      ..strokeCap = StrokeCap.round;
    final c = Offset(12 * u, 12 * u);
    const r = 10.2;
    canvas.drawCircle(c, r * u, stroke); // outer circle
    canvas.drawLine(Offset((12 - r) * u, 12 * u), Offset((12 + r) * u, 12 * u),
        stroke); // equator
    canvas.drawOval(
        Rect.fromCenter(center: c, width: 2 * 4.0 * u, height: 2 * r * u),
        stroke); // meridian
  }

  @override
  bool shouldRepaint(_GlobePainter old) => old.color != color;
}
