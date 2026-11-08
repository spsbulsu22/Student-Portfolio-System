import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/auth_provider.dart' show UserRole;
import '../utils/slide_route.dart';
import '../widgets/auth_flow_layout.dart';
import '../widgets/primary_action_button.dart';
import 'change_password_screen.dart';

/// Figma frame: "1.4 Verify Code" (shared by student and instructor).
///
/// Layout (phone Figma frame + desktop card) lives in [AuthFlowLayout], shared
/// with the Forgot Password page. Both layouts use the same form, controller
/// and validation below.
class VerifyCodeScreen extends StatefulWidget {
  const VerifyCodeScreen({
    super.key,
    required this.role,
    this.email,
    this.onVerifyCode,
    this.onResendCode,
  });

  final UserRole role;

  /// Email the code was sent to (for the resend request).
  final String? email;

  /// Called with the 6-digit code once it passes validation. Hook up the
  /// real verification here (e.g. Supabase). The Change Password page opens
  /// after it completes.
  final Future<void> Function(String code)? onVerifyCode;

  /// Called when "Resend code" is tapped.
  final Future<void> Function()? onResendCode;

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  static const int _codeLength = 6;

  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  static String? _validateCode(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return 'Please enter the code';
    if (text.length != _codeLength) return 'Enter the 6-digit code';
    return null;
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    final verify = widget.onVerifyCode;
    if (verify != null) {
      setState(() => _verifying = true);
      try {
        await verify(_codeCtrl.text.trim());
      } finally {
        if (mounted) setState(() => _verifying = false);
      }
      if (!mounted) return;
    }
    // TODO: when the real verification is hooked up, only continue if the
    // code is correct.
    Navigator.of(context).push(
      SlideFromRightRoute(page: ChangePasswordScreen(role: widget.role)),
    );
  }

  Future<void> _resend() async {
    // TODO: request a new code for [VerifyCodeScreen.email].
    await widget.onResendCode?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AuthFlowLayout(
      role: widget.role,
      title: 'Forgot Password',
      onBack: () => Navigator.of(context).maybePop(),
      // The Figma frame keeps the Back button 61 px from the bottom.
      compactBottomPadding: 61,
      formBuilder: (context, colors) => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthFlowField(
              label: 'Verification code',
              hint: 'Enter 6-digit code',
              controller: _codeCtrl,
              labelColor: colors.label,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_codeLength),
              ],
              validator: _validateCode,
            ),
            const SizedBox(height: 24),
            AuthFlowHelperText(
              'Enter the 6-digit code sent to your email to reset your '
              'password.',
              color: colors.helper,
            ),
            const SizedBox(height: 24),
            PrimaryActionButton(
              label: 'Verify Code',
              width: double.infinity,
              onPressed: _verifying ? null : _verify,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "Didn't receive a code? ",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 20 / 14,
                    color: colors.body,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _resend,
                  child: Text(
                    'Resend code',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 20 / 14,
                      color: colors.link,
                      decoration: TextDecoration.underline,
                      decorationColor: colors.link,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
