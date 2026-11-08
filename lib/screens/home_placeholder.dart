import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_action_button.dart';
import 'login_screen.dart';

/// Temporary screen so login has somewhere to go.
/// We'll replace this with the real Student Home (2 - Home) / Instructor Home (2.2 - Home).
class HomePlaceholder extends ConsumerWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final roleName = auth.role == UserRole.instructor ? 'Instructor' : 'Student';

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Welcome, $roleName!', style: AppTheme.appTitle),
            const SizedBox(height: 8),
            Text(auth.email ?? '', style: AppTheme.body14),
            const SizedBox(height: 32),
            PrimaryActionButton(
              label: 'LOGOUT',
              width: 140,
              onPressed: () async {
                final role = auth.role ?? UserRole.student;
                await ref.read(authProvider.notifier).logout();
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => LoginScreen(role: role)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
