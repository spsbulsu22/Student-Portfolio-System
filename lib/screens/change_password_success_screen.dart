import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/auth_provider.dart' show UserRole;
import '../widgets/auth_flow_layout.dart';
import '../widgets/primary_action_button.dart';
import 'upload_complete_screen.dart' show SuccessBadge;

const _titleNavy = Color(0xFF001B6E);

/// Figma frame: "1.6 Change Password Successful" (shared by student and
/// instructor), shown after the new password is submitted.
///
/// Responsive, one file:
///  - Narrower than [kAuthFlowWideBreakpoint] (phones): the Figma frame. The
///    gaps (169 / 210 / 69 / 92 on the 926 tall frame) are kept as ratios, so
///    it fits any phone height, and scrolls if the screen is very short.
///  - Wider (tablets, browser windows): the same content in the centered card
///    shared with the other password-recovery pages ([AuthFlowWideShell]).
///
/// "Return to Login" (and the system back button) clear the recovery pages
/// and go back to the Login screen, the first route of the stack.
class ChangePasswordSuccessScreen extends StatelessWidget {
  const ChangePasswordSuccessScreen({super.key, required this.role});

  final UserRole role;

  static const String _caption =
      'Your password has been successfully changed. '
      'You will go back to the login page.';

  void _returnToLogin(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // back = Return to Login, not back to the form
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _returnToLogin(context);
      },
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= kAuthFlowWideBreakpoint
            ? _buildWide(context)
            : _buildCompact(context),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Phone layout: the Figma frame.
  // ---------------------------------------------------------------------------
  Widget _buildCompact(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const Spacer(flex: 169),
                    const SuccessBadge(),
                    // Figma title box is 44 high; its two lines overflow it.
                    const SizedBox(
                      height: 44,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 0,
                        maxHeight: 64,
                        child: Text(
                          'Password Change\nComplete!',
                          textAlign: TextAlign.center,
                          style: _titleStyle,
                        ),
                      ),
                    ),
                    const Spacer(flex: 210),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 368),
                        child: Text(
                          _caption,
                          textAlign: TextAlign.center,
                          style: _captionStyle(
                              Colors.black.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                    const Spacer(flex: 69),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: PrimaryActionButton(
                        label: 'Return to Login',
                        width: double.infinity,
                        onPressed: () => _returnToLogin(context),
                      ),
                    ),
                    const Spacer(flex: 92),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tablet / browser layout: centered card.
  // ---------------------------------------------------------------------------
  Widget _buildWide(BuildContext context) {
    final onDark = role == UserRole.instructor; // instructor card is blue

    return AuthFlowWideShell(
      role: role,
      builder: (context, colors) {
        const badgeSize = 160.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: onDark
                  // Same blue as the card: a white ring keeps it visible.
                  ? Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const SuccessBadge(size: badgeSize),
                    )
                  : const SuccessBadge(size: badgeSize),
            ),
            const SizedBox(height: 28),
            Text(
              'Password Change Complete!',
              textAlign: TextAlign.center,
              style: _titleStyle.copyWith(color: colors.body),
            ),
            const SizedBox(height: 12),
            Text(
              _caption,
              textAlign: TextAlign.center,
              style: _captionStyle(
                onDark ? colors.helper : Colors.black.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 32),
            PrimaryActionButton(
              label: 'Return to Login',
              width: double.infinity,
              onPressed: () => _returnToLogin(context),
            ),
          ],
        );
      },
    );
  }

  /// Figma: Inter Semi Bold 24, #001B6E. Only 400/500/700 are bundled, so
  /// 600 resolves to the Bold file (same as the Upload Complete title).
  static const TextStyle _titleStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: _titleNavy,
  );

  /// Figma: Inter Medium 15, black at 50% opacity.
  static TextStyle _captionStyle(Color color) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: color,
      );
}
