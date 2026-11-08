import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Label above a rounded light-blue field (Figma: Email / Password inputs).
///
/// The validation message is drawn in the empty gap UNDER the field without
/// taking any layout space, so showing/hiding an error never moves the other
/// widgets on the screen.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.labelColor,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTheme.fieldLabel.copyWith(color: labelColor)),
        const SizedBox(height: 8),
        FormField<String>(
          validator: (_) => validator?.call(controller.text),
          builder: (state) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                TextField(
                  controller: controller,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  style: AppTheme.fieldText,
                  // Clear the message as soon as the user starts fixing it.
                  onChanged: (_) {
                    if (state.hasError) state.validate();
                  },
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: AppTheme.fieldHint,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                // Floats in the gap below the field; takes no layout space.
                if (state.hasError)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: -15,
                    child: Text(
                      state.errorText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        height: 1.0,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
