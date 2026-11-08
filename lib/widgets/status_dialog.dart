import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Figma: "Logging in" / "Logging out" overlay dialogs (356 wide, spinner + message).
/// Heading/supporting text are placeholders until we pull those frames from Figma.
class StatusDialog extends StatelessWidget {
  const StatusDialog({super.key, required this.heading, required this.message});

  final String heading;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                  strokeWidth: 4, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(heading,
                textAlign: TextAlign.center,
                style: AppTheme.screenHeading.copyWith(color: AppColors.brandText)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: AppTheme.body14),
          ],
        ),
      ),
    );
  }
}
