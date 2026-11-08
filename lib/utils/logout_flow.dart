import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../screens/instructor_home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/student_home_screen.dart';
import '../widgets/status_dialog.dart';

/// Shows the "Logging out..." overlay, signs out, then returns to the Login
/// screen of the same role.
///
/// The Login screen does NOT move. It sits underneath, and the HOME page
/// slides away to the right on top of it (the mirror of how Home slid in when
/// logging in), so the pages feel stacked. The navigation stack is cleared.
Future<void> logoutAndReturnToLogin(
  BuildContext context,
  WidgetRef ref,
  UserRole role,
) async {
  final navigator = Navigator.of(context);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const StatusDialog(
      heading: 'Logging out...',
      message: 'Please wait a moment.',
    ),
  );

  await ref.read(authProvider.notifier).logout();

  if (!navigator.mounted) return;

  // 1) Login becomes the only page (no animation). This also removes the
  //    old Home page and the "Logging out..." dialog.
  navigator.pushAndRemoveUntil(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => LoginScreen(role: role),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
    (route) => false,
  );

  // 2) Put Home back on top of it, instantly, so it looks exactly like the
  //    screen the user was just on...
  navigator.push(
    _HomeExitRoute(
      page: role == UserRole.instructor
          ? const InstructorHomeScreen()
          : const StudentHomeScreen(),
    ),
  );

  // 3) ...then pop it: Home slides out to the right and reveals Login.
  await WidgetsBinding.instance.endOfFrame;
  if (!navigator.mounted) return;
  navigator.pop();
}

/// Appears instantly, but its exit (pop) is the same 350ms slide to the right
/// that every other page uses when going back.
class _HomeExitRoute extends PageRouteBuilder<void> {
  _HomeExitRoute({required Widget page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, __, child) {
            return SlideTransition(
              position: animation.drive(
                Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                    .chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: RepaintBoundary(child: child),
            );
          },
        );
}
