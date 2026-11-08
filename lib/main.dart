import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/instructor_home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_home_screen.dart';
import 'services/supabase_clients.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Student + Instructor Supabase projects (see supabase_clients.dart).
  await AppSupabase.init();
  runApp(const ProviderScope(child: SpmsApp()));
}

class SpmsApp extends ConsumerWidget {
  const SpmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Session persistence: a restored session opens its Home directly.
    // (read, not watch: logging in/out must not swap the root page.)
    final restored = ref.read(authProvider).role;

    return MaterialApp(
      title: 'Student Portfolio System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) =>
          PhoneOrientationGuard(child: child ?? const SizedBox.shrink()),
      home: switch (restored) {
        UserRole.student => const StudentHomeScreen(),
        UserRole.instructor => const InstructorHomeScreen(),
        null => const LoginScreen(role: UserRole.student),
      },
    );
  }
}

/// Phones are portrait-only on the web: in landscape the app is hidden behind
/// a full-screen message and comes back by itself in portrait.
///
/// - Phone = the browser reports Android/iOS (Flutter Web derives
///   [defaultTargetPlatform] from the user agent) AND the shortest side of
///   the window is under [_phoneShortestSide]. Tablets (>= 600) and every
///   desktop/laptop browser (Windows/macOS/Linux, also iPadOS, which reports
///   itself as macOS) are never restricted, however narrow the window is.
/// - Tablets and desktops keep the screens' own width-based switching
///   (LayoutBuilder, 600 px breakpoint) in both orientations.
/// - While blocked, the app stays mounted (Offstage) and is laid out at its
///   last portrait size, so navigation, forms, uploads and sessions are
///   untouched and nothing flips to the desktop layout behind the message.
class PhoneOrientationGuard extends StatefulWidget {
  const PhoneOrientationGuard({super.key, required this.child});

  final Widget child;

  @override
  State<PhoneOrientationGuard> createState() => _PhoneOrientationGuardState();
}

class _PhoneOrientationGuardState extends State<PhoneOrientationGuard> {
  static const double _phoneShortestSide = 600;

  Size? _lastPortrait;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Add the on-screen keyboard back so a portrait phone with the keyboard
    // open is not mistaken for landscape.
    final full = Size(mq.size.width, mq.size.height + mq.viewInsets.bottom);

    final isMobileOs = kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final isPhone = isMobileOs && full.shortestSide < _phoneShortestSide;
    final blocked = isPhone && full.width > full.height;

    if (!blocked) _lastPortrait = mq.size;
    final frozen = _lastPortrait ??
        Size(full.shortestSide, full.longestSide); // started in landscape

    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        Offstage(
          offstage: blocked,
          child: MediaQuery(
            data: blocked
                ? mq.copyWith(size: frozen, viewInsets: EdgeInsets.zero)
                : mq,
            child: OverflowBox(
              minWidth: blocked ? frozen.width : null,
              maxWidth: blocked ? frozen.width : null,
              minHeight: blocked ? frozen.height : null,
              maxHeight: blocked ? frozen.height : null,
              child: widget.child,
            ),
          ),
        ),
        if (blocked) const Positioned.fill(child: _RotateMessage()),
      ],
    );
  }
}

class _RotateMessage extends StatelessWidget {
  const _RotateMessage();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.screen_rotation_alt_rounded,
                  size: 56,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 20),
                Flexible(
                  child: Text(
                    'Please change your phone orientation.',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.menuText,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
