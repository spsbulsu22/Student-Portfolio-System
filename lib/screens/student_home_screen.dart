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
import 'backups_screen.dart';
import 'community_screen.dart';
import 'favorites_screen.dart';
import 'my_portfolio_screen.dart';
import 'notifications_screen.dart';
import 'quick_upload_screen.dart';
import 'student_classes_screen.dart';
import 'student_profile_screen.dart';

/// Figma frame: "2 - Home" (student). Menu: "Student Menu".
class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  void _openMenu(BuildContext context, WidgetRef ref) {
    showAppMenu(
      context,
      accountName: ref.read(authProvider).displayName,
      accountRole: 'Student account',
      items: [
        const AppMenuItem(
          label: 'Home',
          icon: Icons.home_outlined,
          selected: true, // already on Home -> menu just closes
        ),
        AppMenuItem(
          label: 'My Portfolio',
          icon: Icons.folder_outlined,
          onTap: () => Navigator.of(context).push(
            SlideFromRightRoute(page: const MyPortfolioScreen()),
          ),
        ),
        AppMenuItem(
          label: 'Favorites',
          icon: Icons.star_outline_rounded,
          onTap: () => Navigator.of(context).push(
            SlideFromRightRoute(page: const FavoritesScreen()),
          ),
        ),
        AppMenuItem(
          label: 'Backups',
          icon: Icons.history,
          onTap: () => Navigator.of(context).push(
            SlideFromRightRoute(page: const BackupsScreen()),
          ),
        ),
        AppMenuItem(
          label: 'My Classes',
          icon: Icons.people_outline,
          onTap: () => Navigator.of(context).push(
            SlideFromRightRoute(page: const StudentClassesScreen()),
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
        SlideFromRightRoute(page: const StudentProfileScreen()),
      ),
      onLogout: () => logoutAndReturnToLogin(context, ref, UserRole.student),
    );
  }

  void _openProfileDropdown(BuildContext context, WidgetRef ref, Rect anchor) {
    showProfileDropdown(
      context,
      anchor: anchor,
      onMyProfile: () => Navigator.of(context).push(
        SlideFromRightRoute(page: const StudentProfileScreen()),
      ),
      onNotifications: () => Navigator.of(context).push(
        SlideFromRightRoute(page: const NotificationsScreen(student: true)),
      ),
      // unreadCount: 8, // TODO: hook up real unread count later
      onLogout: () => logoutAndReturnToLogin(context, ref, UserRole.student),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Six tiles: phone 3 rows x 2 columns, desktop 2 rows x 3 columns.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: HomeShell(
          recentTitle: 'Recently Uploaded',
          columns: 2, // phone: 3 rows x 2 columns, on the left
          wideColumns: 3, // desktop: 2 rows x 3 columns
          onMenuTap: () => _openMenu(context, ref),
          onProfileTap: (anchor) => _openProfileDropdown(context, ref, anchor),
          actions: [
            HomeAction(
              label: 'Quick Upload',
              icon: Icons.note_add, // Figma: document with plus
              buttonTop: 370,
              labelTop: 474,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const QuickUploadScreen()),
              ),
            ),
            HomeAction(
              label: 'My Portfolio',
              icon: Icons.folder, // Figma: ant-design:folder-filled
              buttonTop: 508,
              labelTop: 612,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const MyPortfolioScreen()),
              ),
            ),
            HomeAction(
              label: 'Favorites',
              icon: Icons.star_border_rounded, // Figma: clarity:favorite-line
              buttonTop: 646,
              labelTop: 750,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const FavoritesScreen()),
              ),
            ),
            HomeAction(
              label: 'Backups',
              icon: Icons.history, // Figma: History clock
              buttonTop: 784,
              labelTop: 888,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const BackupsScreen()),
              ),
            ),
            HomeAction(
              label: 'My Classes',
              icon: Icons.people,
              // buttonTop / labelTop are ignored: with 5 actions the phone
              // layout positions the tiles itself.
              buttonTop: 922,
              labelTop: 1026,
              onTap: () => Navigator.of(context).push(
                SlideFromRightRoute(page: const StudentClassesScreen()),
              ),
            ),
            HomeAction(
              label: 'Community',
              icon: kCommunityFallbackIcon,
              iconBuilder: communityIconBuilder, // same logo as the menu
              buttonTop: 1060, // ignored: the 2-column grid places the tiles
              labelTop: 1164,
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
