import 'package:flutter/material.dart';

import '../providers/auth_provider.dart' show UserRole;
import '../utils/slide_route.dart';
import '../widgets/auth_flow_layout.dart';
import '../widgets/primary_action_button.dart';
import 'change_password_success_screen.dart';

/// Figma frame: "1.5 Change Password" (shared by student and instructor).
///
/// Layout (phone Figma frame + desktop card) lives in [AuthFlowLayout], shared
/// with the Forgot Password and Verify Code pages. Both layouts use the same
/// form, controllers and validation below.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    required this.role,
    this.onSubmit,
  });

  final UserRole role;

  /// Called with the new password once the form is valid. Hook up the real
  /// password update here (e.g. Supabase). When it completes, the
  /// "Change Password Successful" page opens, and its "Return to Login"
  /// button closes the recovery pages and returns to the login screen.
  final Future<void> Function(String newPassword)? onSubmit;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const int _minLength = 8;

  final _formKey = GlobalKey<FormState>();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateNew(String? v) {
    final text = v ?? '';
    if (text.isEmpty) return 'Please enter a new password';
    if (text.length < _minLength) return 'Use at least 8 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    final text = v ?? '';
    if (text.isEmpty) return 'Please confirm your password';
    if (text != _newCtrl.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // TODO: update the password here when no onSubmit is provided.
      await widget.onSubmit?.call(_newCtrl.text);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      SlideFromRightRoute(page: ChangePasswordSuccessScreen(role: widget.role)),
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return AuthFlowLayout(
      role: widget.role,
      title: 'Change Password',
      onBack: () => Navigator.of(context).maybePop(),
      // The Figma frame keeps the Back / Submit row 61 px from the bottom.
      compactBottomPadding: 61,
      bottomActionBuilder: (wide) => PrimaryActionButton(
        label: 'Submit',
        width: wide ? double.infinity : 124,
        onPressed: _saving ? null : _submit,
      ),
      formBuilder: (context, colors) => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthFlowField(
              label: 'Create new password',
              hint: '••••••••',
              controller: _newCtrl,
              labelColor: colors.label,
              labelGap: 8,
              obscureText: true,
              keyboardType: TextInputType.visiblePassword,
              helperText:
                  'Use 8+ characters with a mix of letters, numbers, and '
                  'symbols.',
              helperColor: colors.helper,
              validator: _validateNew,
            ),
            const SizedBox(height: 24),
            AuthFlowField(
              label: 'Confirm Password',
              hint: '••••••••',
              controller: _confirmCtrl,
              labelColor: colors.label,
              labelGap: 8,
              obscureText: true,
              keyboardType: TextInputType.visiblePassword,
              helperText: 'Re-enter your new password to ensure it matches.',
              helperColor: colors.helper,
              validator: _validateConfirm,
            ),
            const SizedBox(height: 24),
            AuthFlowHelperText(
              'Your password will be updated immediately. You may be logged '
              'out of other devices.',
              color: colors.helper,
            ),
          ],
        ),
      ),
    );
  }
}
