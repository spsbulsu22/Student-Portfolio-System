import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_count_provider.dart';
import '../theme/app_colors.dart';
import 'primary_action_button.dart';

/// Figma: "Instructor/Student Profile Dropdown" (248 x 197).
///
/// Opens right beneath the profile button ([anchor] = the button's on-screen
/// rect). The background is NOT dimmed. Tapping anywhere else (including other
/// buttons) only closes it.
Future<void> showProfileDropdown(
  BuildContext context, {
  required Rect anchor,
  required VoidCallback onMyProfile,
  required VoidCallback onLogout,
  VoidCallback? onNotifications,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close profile menu',
    barrierColor: Colors.transparent, // no dimming
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, animation, _) {
      final screenWidth = MediaQuery.sizeOf(ctx).width;
      // CurveTween works both ways, so closing is the mirror of opening.
      final t = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return Stack(
        children: [
          Positioned(
            top: anchor.bottom + 4, // just beneath the profile button
            right: screenWidth - anchor.right, // right edges aligned
            child: FadeTransition(
              opacity: t,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(t),
                alignment: Alignment.topRight,
                child: _DropdownPanel(
                  onMyProfile: () {
                    _closeNow(ctx);
                    onMyProfile();
                  },
                  onNotifications: () {
                    _closeNow(ctx);
                    onNotifications?.call();
                  },
                  onLogout: () {
                    _closeNow(ctx);
                    onLogout();
                  },
                ),
              ),
            ),
          ),
        ],
      );
    },
    // The panel animates itself; no extra route-level transition.
    transitionBuilder: (_, __, ___, child) => child,
  );
}

/// Removes the dropdown instantly (no exit animation) so the page slide that
/// follows starts on a clean frame instead of overlapping the fade/scale-out.
void _closeNow(BuildContext ctx) {
  final route = ModalRoute.of(ctx);
  if (route != null) Navigator.of(ctx).removeRoute(route);
}

class _DropdownPanel extends ConsumerWidget {
  const _DropdownPanel({
    required this.onMyProfile,
    required this.onNotifications,
    required this.onLogout,
  });

  final VoidCallback onMyProfile;
  final VoidCallback onNotifications;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live: the number changes even while the dropdown is open.
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    return RepaintBoundary(
      child: Container(
        width: 248,
        // 1px border + 11px padding = Figma's 12px from the outer edge
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.dropdownBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24003F70), // rgba(0,63,112,0.14)
              offset: Offset(0, 8),
              blurRadius: 28,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuItem(
                label: 'My Profile',
                icon: Stack(
                  alignment: Alignment.center,
                  children: const [
                    CircleAvatar(radius: 8, backgroundColor: Colors.white),
                    Icon(Icons.account_circle,
                        size: 22, color: AppColors.menuButton),
                  ],
                ),
                onTap: onMyProfile,
              ),
              const SizedBox(height: 4),
              _MenuItem(
                label: 'Notifications',
                icon: const Icon(Icons.notifications_none,
                    size: 22, color: AppColors.menuButton),
                badgeCount: unreadCount,
                onTap: onNotifications,
              ),
              const SizedBox(height: 8),
              Container(height: 1, color: AppColors.dropdownBorder),
              const SizedBox(height: 8),
              PrimaryActionButton(
                label: 'Logout',
                width: double.infinity,
                onPressed: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badgeCount,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // Icon container: 36x36, radius 12, light blue
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.5, // Figma line-height 24
                    color: AppColors.dropdownText,
                  ),
                ),
              ),
              // Unread badge: 23.3px circle (grows into a pill for 3 chars).
              if (badgeCount != null && badgeCount! > 0)
                Container(
                  constraints: const BoxConstraints(
                      minWidth: 23.33, minHeight: 23.33),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.menuButton,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeCount! > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
