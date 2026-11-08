import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/app_icons.dart';
import '../utils/logout_flow.dart';
import '../utils/slide_route.dart';
import '../widgets/app_menu.dart';
import '../widgets/home_shell.dart';
import '../widgets/profile_dropdown.dart';
import 'community_screen.dart';
import 'instructor_profile_screen.dart';
import 'my_classes_screen.dart';
import 'notifications_screen.dart';
import 'submissions_screen.dart';

/// Figma frame: "2.2 - Home" (instructor). Menu: "Instructor Menu".
class InstructorHomeScreen extends ConsumerWidget {
  const InstructorHomeScreen({super.key});

  void _openMenu(BuildContext context, WidgetRef ref) {
    showAppMenu(
      context,
      accountName: ref.read(authProvider).displayName,
      accountRole: 'Instructor account',
      items: [
        const AppMenuItem(
          label: 'Home',
          icon: Icons.home_outlined,
          selected: true, // already on Home -> menu just closes
        ),
        AppMenuItem(
          label: 'Submissions',
          icon: Icons.assignment_outlined, // Figma: clipboard-list
          onTap: () => Navigator.of(context).push(
            SlideFromRightRoute(page: const SubmissionsScreen()),
          ),
        ),
        AppMenuItem(
          label: 'My Classes',
          icon: Icons.people_outline, // Figma: users
          onTap: () => Navigator.of(context).push(
            SlideFromRightRoute(page: const MyClassesScreen()),
          ),
        ),
        AppMenuItem(
          label: 'Community',
          icon: kCommunityFallbackIcon,
          iconBuilder: communityIconBuilder, // same logo as the Home tile
          onTap: () => Navigator.of(context).push(
            SlideFromRightRoute(page: const CommunityScreen()),
          ),
        ),
      ],
      onAccountTap: () => Navigator.of(context).push(
        SlideFromRightRoute(page: const InstructorProfileScreen()),
      ),
      onLogout: () => logoutAndReturnToLogin(context, ref, UserRole.instructor),
    );
  }

  void _openProfileDropdown(BuildContext context, WidgetRef ref, Rect anchor) {
    showProfileDropdown(
      context,
      anchor: anchor,
      onMyProfile: () => Navigator.of(context).push(
        SlideFromRightRoute(page: const InstructorProfileScreen()),
      ),
      onNotifications: () => Navigator.of(context).push(
        SlideFromRightRoute(page: const NotificationsScreen(instructor: true)),
      ),
      // unreadCount: 8, // TODO: hook up real unread count later
      onLogout: () => logoutAndReturnToLogin(context, ref, UserRole.instructor),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: HomeShell(
          recentTitle: 'Recent Submissions',
          onMenuTap: () => _openMenu(context, ref),
          onProfileTap: (anchor) => _openProfileDropdown(context, ref, anchor),
          actions: [
            HomeAction(
              label: 'Submissions',
              icon: Icons.content_paste, // Figma: bi:clipboard-fill
              iconSize: 58,
              buttonTop: 376,
              labelTop: 488,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const SubmissionsScreen()),
              ),
            ),
            HomeAction(
              label: 'My Classes',
              icon: Icons.people, // Figma: bi:people-fill
              iconSize: 64,
              buttonTop: 524,
              labelTop: 636,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const MyClassesScreen()),
              ),
            ),
            HomeAction(
              label: 'Community',
              icon: kCommunityFallbackIcon,
              iconBuilder: communityIconBuilder, // same logo as the menu
              iconSize: 64,
              buttonTop: 672,
              labelTop: 784,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const CommunityScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
