import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/auth_provider.dart' show UserRole;
import '../theme/app_colors.dart';
import 'primary_action_button.dart';

/// Width (logical px) from which the centered-card layout is used.
/// Same value as the login screen.
const double kAuthFlowWideBreakpoint = 600;

/// Text color used by the field and helper copy in the Figma frames.
const _deepBlue = Color(0xFF001B6E);

/// Text colors for the current surface (white page vs. blue card).
class AuthFlowColors {
  const AuthFlowColors({
    required this.label,
    required this.helper,
    required this.body,
    required this.link,
  });

  final Color label;
  final Color helper;
  final Color body;
  final Color link;

  /// Form sits on a white surface (phone layout / student card).
  factory AuthFlowColors.onLight() => AuthFlowColors(
        label: AppColors.brandText,
        helper: _deepBlue.withValues(alpha: 0.6),
        body: _deepBlue,
        link: AppColors.brandText,
      );

  /// Form sits on the blue gradient (instructor card).
  factory AuthFlowColors.onDark() => AuthFlowColors(
        label: Colors.white,
        helper: Colors.white.withValues(alpha: 0.85),
        body: Colors.white,
        link: Colors.white,
      );
}

/// Shared shell of the password-recovery frames
/// ("1.3 Forgot Password", "1.4 Verify Code").
///
/// Responsive:
///  - Narrower than [kAuthFlowWideBreakpoint] (phones): the Figma layout
///    (gradient header, content padded 43 px, Back button bottom left).
///  - Wider (tablets, browser windows): the same content in a centered card,
///    styled like the login card for the given [role]
///    (student: blue background + white card, instructor: the opposite).
class AuthFlowLayout extends StatelessWidget {
  const AuthFlowLayout({
    super.key,
    required this.role,
    required this.title,
    required this.formBuilder,
    required this.onBack,
    this.compactBottomPadding = 49,
    this.bottomActionBuilder,
  });

  final UserRole role;

  /// Header title (phone) / card heading (wide).
  final String title;

  /// Builds the form for the given surface colors.
  final Widget Function(BuildContext context, AuthFlowColors colors)
      formBuilder;

  final VoidCallback onBack;

  /// Distance between the Back button and the bottom edge on phones (Figma).
  final double compactBottomPadding;

  /// Optional second action next to Back (e.g. "Submit"). Phones: placed at
  /// the right end of the bottom row (`wide == false`). Wide card: placed
  /// under the form (`wide == true`).
  final Widget Function(bool wide)? bottomActionBuilder;

  static const LinearGradient _blueGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      AppColors.instructorGradientStart,
      AppColors.instructorGradientEnd,
    ],
    stops: [0.04, 0.96],
  );

  bool get _isStudent => role == UserRole.student;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kAuthFlowWideBreakpoint
          ? _buildWide(context)
          : _buildCompact(context),
    );
  }

  // ---------------------------------------------------------------------------
  // Phone layout: the Figma frame.
  // ---------------------------------------------------------------------------
  Widget _buildCompact(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _AuthFlowHeader(title: title, topPad: inset.top),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      // 43 px sides, content starts 66 px under the header.
                      padding: EdgeInsets.fromLTRB(
                          43, 66, 43, compactBottomPadding + inset.bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          formBuilder(context, AuthFlowColors.onLight()),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              PrimaryActionButton(
                                label: 'Back',
                                width: 104,
                                onPressed: onBack,
                              ),
                              if (bottomActionBuilder != null)
                                bottomActionBuilder!(false),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tablet / browser layout: centered card (see [AuthFlowWideShell]).
  // ---------------------------------------------------------------------------
  Widget _buildWide(BuildContext context) {
    final cardOnDark = !_isStudent; // instructor card is blue -> light text
    final headingColor = cardOnDark ? Colors.white : AppColors.textDark;
    final backColor = cardOnDark ? Colors.white : AppColors.link;

    return AuthFlowWideShell(
      role: role,
      builder: (context, colors) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 28 / 24,
              color: headingColor,
            ),
          ),
          const SizedBox(height: 32),
          formBuilder(context, colors),
          if (bottomActionBuilder != null) ...[
            const SizedBox(height: 24),
            bottomActionBuilder!(true),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.chevron_left, size: 20, color: backColor),
              label: Text(
                'Back',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: backColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tablet / browser shell shared by the auth pages: gradient (student) or
/// white (instructor) page with logo watermarks and a centered, shadowed card
/// in the opposite style. Only the card's content differs per page.
class AuthFlowWideShell extends StatelessWidget {
  const AuthFlowWideShell({
    super.key,
    required this.role,
    required this.builder,
  });

  final UserRole role;

  /// Builds the card content for the card's surface colors.
  final Widget Function(BuildContext context, AuthFlowColors colors) builder;

  static const double _cardMaxWidth = 460;

  bool get _isStudent => role == UserRole.student;

  @override
  Widget build(BuildContext context) {
    final cardOnDark = !_isStudent; // instructor card is blue -> light text
    final colors =
        cardOnDark ? AuthFlowColors.onDark() : AuthFlowColors.onLight();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _isStudent
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: _isStudent
              ? const BoxDecoration(gradient: AuthFlowLayout._blueGradient)
              : const BoxDecoration(color: Colors.white),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _watermark(
                color: _isStudent ? Colors.white : AppColors.menuButton,
                size: 520,
                left: -130,
                bottom: -130,
              ),
              _watermark(
                color: _isStudent ? Colors.white : AppColors.menuButton,
                size: 300,
                right: -80,
                top: -80,
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: _cardMaxWidth),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 48, vertical: 40),
                        decoration: BoxDecoration(
                          color: _isStudent ? Colors.white : null,
                          gradient:
                              _isStudent ? null : AuthFlowLayout._blueGradient,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33002C51), // rgba(0,44,81,0.2)
                              offset: Offset(0, 16),
                              blurRadius: 40,
                            ),
                          ],
                        ),
                        child: builder(context, colors),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Decorative logo watermark behind the card (ignores pointer input).
  Widget _watermark({
    required Color color,
    required double size,
    double? left,
    double? right,
    double? top,
    double? bottom,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.07,
          child: SvgPicture.asset(
            'assets/images/logo.svg',
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

/// Figma: header gradient (114 high, -90deg #007EDE -> #004478) with the
/// title in Inter Bold 20 / 24 at 23 px from the left.
class _AuthFlowHeader extends StatelessWidget {
  const _AuthFlowHeader({required this.title, required this.topPad});

  final String title;
  final double topPad;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 114 + topPad,
      padding: const EdgeInsets.fromLTRB(23, 0, 23, 21),
      alignment: Alignment.bottomLeft,
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
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 24 / 20,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Figma: label (Inter Medium 16, #007EDE), 24 px gap, 44 px high rounded
/// field (#D3E7FF) with a 50% opacity hint.
///
/// The validation message floats in the gap under the field without taking
/// layout space (same approach as [AppTextField]).
class AuthFlowField extends StatelessWidget {
  const AuthFlowField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.labelColor,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.labelGap = 24,
    this.helperText,
    this.helperColor,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Color labelColor;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;

  /// Gap between the label and the field (Figma: 24, or 8 on Change Password).
  final double labelGap;

  /// Optional small hint under the field (Inter 12 / 16). When set, the
  /// validation message replaces it (in the error color) instead of floating
  /// under the field.
  final String? helperText;
  final Color? helperColor;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
        SizedBox(height: labelGap),
        FormField<String>(
          validator: (_) => validator?.call(controller.text),
          builder: (state) {
            final stack = Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  height: 44,
                  child: TextField(
                    controller: controller,
                    obscureText: obscureText,
                    keyboardType: keyboardType,
                    inputFormatters: inputFormatters,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: _deepBlue,
                    ),
                    // Clear the message as soon as the user starts fixing it.
                    onChanged: (_) {
                      if (state.hasError) state.validate();
                    },
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: _deepBlue.withValues(alpha: 0.5),
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.inputFill,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (state.hasError && helperText == null)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: -17,
                    child: Text(
                      state.errorText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        height: 1.0,
                        color: errorColor,
                      ),
                    ),
                  ),
              ],
            );
            if (helperText == null) return stack;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                stack,
                const SizedBox(height: 8),
                Text(
                  state.hasError ? state.errorText! : helperText!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 16 / 12,
                    color: state.hasError ? errorColor : helperColor,
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

/// Figma: helper copy under the field (Inter Regular 14 / 20, 60% opacity).
class AuthFlowHelperText extends StatelessWidget {
  const AuthFlowHelperText(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 20 / 14,
        color: color,
      ),
    );
  }
}
