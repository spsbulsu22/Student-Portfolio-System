import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Figma: Remember Me Toggle (36x36 rounded square with check) + label.
///
/// Animation (on tap):
///  - box shrinks slightly while pressed, then springs back
///  - fill color fades in/out
///  - check mark pops in with a small overshoot and fades
class RememberMeToggle extends StatefulWidget {
  const RememberMeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.textColor,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? textColor;

  @override
  State<RememberMeToggle> createState() => _RememberMeToggleState();
}

class _RememberMeToggleState extends State<RememberMeToggle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final checked = widget.value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => widget.onChanged(!checked),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _pressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: checked ? AppColors.checkboxBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                // Border is always 2px so the box never "jumps" in size.
                border: Border.all(color: AppColors.checkboxBlue, width: 2),
              ),
              child: AnimatedScale(
                scale: checked ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 280),
                curve: checked ? Curves.easeOutBack : Curves.easeIn,
                child: AnimatedOpacity(
                  opacity: checked ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.check, color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text('Remember me',
              style: AppTheme.body14.copyWith(color: widget.textColor)),
        ],
      ),
    );
  }
}
