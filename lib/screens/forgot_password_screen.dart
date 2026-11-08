import 'package:flutter/material.dart';

import '../providers/auth_provider.dart' show UserRole;
import '../utils/slide_route.dart';
import '../widgets/auth_flow_layout.dart';
import '../widgets/primary_action_button.dart';
import 'verify_code_screen.dart';

/// Figma frame: "1.3 Forgot Password" (shared by student and instructor).
///
/// Layout (phone Figma frame + desktop card) lives in [AuthFlowLayout], shared
/// with the Verify Code page. Both layouts use the same form, controller and
/// validation below.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.role,
    this.onSendCode,
  });

  final UserRole role;

  /// Called with the trimmed email once it passes validation. Hook up the
  /// real "send verification code" request here (e.g. Supabase). The Verify
  /// Code page opens after it completes.
  final Future<void> Function(String email)? onSendCode;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  static String? _validateEmail(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return 'Please enter your email';
    final looksValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    return looksValid ? null : 'Please enter a valid email';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final send = widget.onSendCode;
    if (send != null) {
      setState(() => _sending = true);
      try {
        await send(email);
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      if (!mounted) return;
    }
    // TODO: when the real request is hooked up, only continue if it succeeds.
    Navigator.of(context).push(
      SlideFromRightRoute(
        page: VerifyCodeScreen(role: widget.role, email: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthFlowLayout(
      role: widget.role,
      title: 'Forgot Password',
      onBack: () => Navigator.of(context).maybePop(),
      formBuilder: (context, colors) => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthFlowField(
              label: 'Email',
              hint: 'Enter your email address',
              controller: _emailCtrl,
              labelColor: colors.label,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
            const SizedBox(height: 24),
            AuthFlowHelperText(
              "We'll send a verification code to this email to help you "
              'reset your password.',
              color: colors.helper,
            ),
            const SizedBox(height: 24),
            PrimaryActionButton(
              label: 'Send Verification Code',
              width: double.infinity,
              onPressed: _sending ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
