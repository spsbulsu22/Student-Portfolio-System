import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/dissolve_route.dart';
import '../utils/slide_route.dart';
import '../widgets/app_text_field.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/remember_me_toggle.dart';
import '../widgets/status_dialog.dart';
import 'forgot_password_screen.dart';
import 'instructor_home_screen.dart';
import 'student_home_screen.dart';

/// Figma frames: "1 - Login" (student, white) and "1.2 - Login" (instructor, blue gradient).
///
/// RESPONSIVE:
///  - Narrower than [_wideBreakpoint] (phones): the original Figma layout,
///    unchanged (full-screen background, form padded 46px on each side).
///  - [_wideBreakpoint] or wider (tablets, browser windows): the same form is
///    placed inside a centered card (max 460px wide) on top of the page
///    background, so the fields never stretch across a big screen.
///    Student: blue background + white card.
///    Instructor: white background + blue card.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.role});
  final UserRole role;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

/// All the text colors of the form, for one kind of surface.
class _LoginColors {
  const _LoginColors({
    required this.heading,
    required this.title,
    required this.label,
    required this.link,
    required this.forgot,
    required this.clickHere,
    required this.body,
    required this.whiteLogo,
  });

  final Color heading;
  final Color title;
  final Color label;
  final Color link;
  final Color forgot;
  final Color clickHere;
  final Color body;
  final bool whiteLogo;

  /// [onDark] = the form sits directly on the blue gradient (white text).
  factory _LoginColors.forSurface({required bool onDark}) {
    return _LoginColors(
      heading: onDark ? Colors.white : AppColors.textDark,
      title: onDark ? Colors.white : AppColors.brandText,
      label: onDark ? Colors.white : AppColors.brandText,
      link: onDark
          ? Colors.white.withOpacity(0.75)
          : AppColors.link.withOpacity(0.75),
      forgot: onDark ? Colors.white.withOpacity(0.75) : AppColors.link,
      clickHere:
          onDark ? Colors.white.withOpacity(0.75) : AppColors.linkAccent,
      body: onDark ? Colors.white : AppColors.textDark,
      whiteLogo: onDark,
    );
  }
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// Width (in logical pixels) from which the centered-card layout is used.
  static const double _wideBreakpoint = 600;

  /// Shown in the lower right corner.
  static const String _appVersion = 'v0.0.0';

  /// Card width on wide screens.
  static const double _cardMaxWidth = 460;

  static const LinearGradient _blueGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      AppColors.instructorGradientStart,
      AppColors.instructorGradientEnd,
    ],
    stops: [0.04, 0.96],
  );

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _rememberMe = true;

  bool get _isStudent => widget.role == UserRole.student;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    _submitting = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StatusDialog(
        heading: 'Logging in...',
        message: 'Please wait a moment.',
      ),
    );

    String? error;
    try {
      await ref.read(authProvider.notifier).login(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            role: widget.role,
            rememberMe: _rememberMe,
          );
    } on AuthFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
    }
    _submitting = false;

    if (!mounted) return;
    Navigator.of(context).pop(); // close dialog
    if (error != null) {
      _showError(error);
      return;
    }
    Navigator.of(context).pushReplacement(
      SlideFromRightRoute(
        page: widget.role == UserRole.instructor
            ? const InstructorHomeScreen()
            : const StudentHomeScreen(),
      ),
    );
  }

  /// Floating message: does not change the login layout.
  void _showError(String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.error,
          content: Text(message, style: TextStyle(color: scheme.onError)),
        ),
      );
  }

  void _switchRole() {
    Navigator.of(context).pushReplacement(
      DissolvePageRoute(
        page: LoginScreen(
          role: _isStudent ? UserRole.instructor : UserRole.student,
        ),
      ),
    );
  }

  double? _stableW;
  double? _stableH;

  /// Layout height for the phone form. While a text field is focused, a
  /// shorter viewport (browser/keyboard resize) is ignored so nothing
  /// stretches, shrinks or moves while typing.
  double _stableHeight(BoxConstraints box) {
    final typing = FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    final keep = typing &&
        _stableW == box.maxWidth &&
        _stableH != null &&
        box.maxHeight < _stableH!;
    if (!keep) {
      _stableW = box.maxWidth;
      _stableH = box.maxHeight;
    }
    return _stableH!;
  }

  @override
  Widget build(BuildContext context) {
    final onDark = !_isStudent; // instructor screen has the dark gradient

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        // What sits behind the version label / status bar.
        final darkBackdrop = wide ? _isStudent : onDark;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: darkBackdrop
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Scaffold(
            // Phones: the keyboard must not resize/move the form.
            resizeToAvoidBottomInset: wide,
            body: Stack(
              children: [
                Positioned.fill(
                  child: wide
                      ? _buildWide(constraints.maxHeight)
                      : _buildCompact(onDark),
                ),
                // App version, lower right corner.
                Positioned(
                  right: 20,
                  bottom: 14,
                  child: IgnorePointer(
                    child: Text(
                      _appVersion,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: darkBackdrop
                            ? Colors.white.withOpacity(0.7)
                            : AppColors.menuMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Decorative logo watermark behind the form (ignores pointer input).
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Phone layout: exactly the original Figma layout.
  // ---------------------------------------------------------------------------
  Widget _buildCompact(bool onDark) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: onDark
          ? const BoxDecoration(
              gradient: LinearGradient(
                // CSS 221deg on a 428x926 frame, converted to Flutter alignments
                begin: Alignment(1.502, -0.799),
                end: Alignment(-1.502, 0.799),
                colors: [
                  AppColors.instructorGradientStart,
                  AppColors.instructorGradientEnd,
                ],
                stops: [0.04, 0.96],
              ),
            )
          : const BoxDecoration(color: Colors.white),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _watermark(
            color: onDark ? Colors.white : AppColors.menuButton,
            size: 340,
            right: -110,
            bottom: -110,
          ),
          // No scrolling and no movement while typing: the form is scaled to
          // fit once, from the viewport height WITHOUT the on-screen keyboard.
          // If the browser shrinks the viewport for the keyboard while a field
          // is focused, the previous height is kept (see _stableHeight).
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final h = _stableHeight(box);
                return OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: box.maxWidth,
                  maxWidth: box.maxWidth,
                  minHeight: h,
                  maxHeight: h,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(46, 12, 46, 36),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: box.maxWidth - 92,
                        child: _buildForm(
                          colors: _LoginColors.forSurface(onDark: onDark),
                          logoSize: 155,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tablet / browser layout: centered card on the page background.
  //   Student:    blue background, white card.
  //   Instructor: white background, blue card.
  // ---------------------------------------------------------------------------
  Widget _buildWide(double availableHeight) {
    // Keep the card on screen in short browser windows.
    final logoSize = availableHeight < 760 ? 110.0 : 140.0;
    final cardOnDark = !_isStudent; // blue card -> light text

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: _isStudent
          ? const BoxDecoration(gradient: _blueGradient)
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
                  constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                    decoration: BoxDecoration(
                      color: _isStudent ? Colors.white : null,
                      gradient: _isStudent ? null : _blueGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33002C51), // rgba(0,44,81,0.2)
                          offset: Offset(0, 16),
                          blurRadius: 40,
                        ),
                      ],
                    ),
                    child: _buildForm(
                      colors: _LoginColors.forSurface(onDark: cardOnDark),
                      logoSize: logoSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The form itself (shared by both layouts).
  // ---------------------------------------------------------------------------
  Widget _buildForm({
    required _LoginColors colors,
    required double logoSize,
  }) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            // Loaded from assets/images/logo.svg. Instructor logo is white in
            // Figma (only when on the gradient).
            child: SvgPicture.asset(
              'assets/images/logo.svg',
              width: logoSize,
              height: logoSize,
              colorFilter: colors.whiteLogo
                  ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Student Portfolio System',
                style: AppTheme.appTitle.copyWith(color: colors.title)),
          ),
          const SizedBox(height: 40),
          Text(
            _isStudent ? 'Student User Login' : 'Instructor User Login',
            style: AppTheme.screenHeading.copyWith(color: colors.heading),
          ),
          const SizedBox(height: 20),
          AppTextField(
            label: 'Email',
            hint: 'Enter email',
            labelColor: colors.label,
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please enter your email'
                : null,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Password',
            hint: 'Enter Password',
            labelColor: colors.label,
            controller: _passwordCtrl,
            obscureText: true,
            validator: (v) => (v == null || v.isEmpty)
                ? 'Please enter your password'
                : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                SlideFromRightRoute(
                  page: ForgotPasswordScreen(role: widget.role),
                ),
              ),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(top: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text('Forgot Password?',
                  style: AppTheme.linkText.copyWith(color: colors.forgot)),
            ),
          ),
          const SizedBox(height: 4),
          RememberMeToggle(
            value: _rememberMe,
            textColor: colors.body,
            onChanged: (v) => setState(() => _rememberMe = v),
          ),
          const SizedBox(height: 36),
          Center(
            child: PrimaryActionButton(
              label: 'LOGIN',
              width: 124,
              onPressed: _submit,
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Text(
                  _isStudent
                      ? 'Signing in as an Instructor?'
                      : 'Signing in as a Student?',
                  style: AppTheme.linkText.copyWith(color: colors.link),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _switchRole,
                  child: Text(
                    'Click here',
                    style: AppTheme.linkText.copyWith(
                      color: colors.clickHere,
                      decoration: TextDecoration.underline,
                      decorationColor: colors.clickHere,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
