import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'primary_action_button.dart';

/// One row of the side menu.
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.icon,
    this.selected = false,
    this.onTap,
    this.iconBuilder,
  });

  final String label;
  final IconData icon;

  /// Draws a custom logo instead of [icon] (used by Community).
  final Widget Function(double size, Color color)? iconBuilder;
  final bool selected;

  /// Called after the menu has started closing.
  final VoidCallback? onTap;
}

/// Figma: "Instructor Menu" / "Student Menu".
///
/// - Background is dimmed with black @ 45%.
/// - Tapping the dimmed area (or the X) closes it.
/// - Slides in from the left, and slides back out to the left when closed.
Future<void> showAppMenu(
  BuildContext context, {
  required String accountName,
  required String accountRole,
  required List<AppMenuItem> items,
  required VoidCallback onLogout,
  VoidCallback? onAccountTap,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.45),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => _MenuPanel(
      accountName: accountName,
      accountRole: accountRole,
      items: items,
      onLogout: onLogout,
      onAccountTap: onAccountTap,
    ),
    transitionBuilder: (_, animation, __, child) {
      // One ease-out curve for both directions: opening decelerates, and
      // closing is the exact mirror (accelerates away to the left).
      final t = Curves.easeOutCubic.transform(animation.value);
      return FractionalTranslation(
        // -1.2 so the panel's soft shadow is fully off-screen at the start
        translation: Offset(-1.2 * (1 - t), 0),
        child: child,
      );
    },
  );
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.accountName,
    required this.accountRole,
    required this.items,
    required this.onLogout,
    this.onAccountTap,
  });

  final String accountName;
  final String accountRole;
  final List<AppMenuItem> items;
  final VoidCallback onLogout;
  final VoidCallback? onAccountTap;

  void _close(BuildContext context) => Navigator.of(context).pop();

  /// Runs a card's action.
  ///
  /// If it opened a new page, the menu is NOT removed straight away. Removing
  /// it in the same frame as the push makes the dim layer vanish in one frame
  /// (a visible "jump") while the new page is still starting to slide in.
  /// Instead the menu stays put underneath, the new page slides over it, and
  /// the menu is dropped silently once the page fully covers it.
  ///
  /// If nothing opened (e.g. "Home" or a not-yet-built item), it closes with
  /// the normal slide-out.
  void _activate(BuildContext context, VoidCallback? action) {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    action?.call();
    if (route == null) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      // Slightly longer than the 350ms slide so the page fully covers the menu.
      Future.delayed(const Duration(milliseconds: 450), () {
        // If the user already went back, leave the menu alone.
        if (route.isActive && !route.isCurrent) navigator.removeRoute(route);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Figma panel is 336 wide. Slightly narrower (312) leaves a bit more of
    // the dimmed area to tap on. Never wider than 80% of a small screen.
    final panelWidth = math.min(312.0, MediaQuery.sizeOf(context).width * 0.80);

    return Align(
      alignment: Alignment.centerLeft,
      child: RepaintBoundary(
        child: SizedBox(
        width: panelWidth,
        height: double.infinity,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33002C51), // rgba(0,44,81,0.2)
                offset: Offset(8, 0),
                blurRadius: 32,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Figma has the phone clock (19px) + 28px gap here.
                            const SizedBox(height: 47),
                            _Heading(onClose: () => _close(context)),
                            const SizedBox(height: 28),
                            _AccountSummary(
                              name: accountName,
                              role: accountRole,
                              onTap: onAccountTap == null
                                  ? null
                                  : () => _activate(context, onAccountTap),
                            ),
                            const SizedBox(height: 28),
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _NavTile(
                                item: items[i],
                                onTap: () =>
                                    _activate(context, items[i].onTap),
                              ),
                            ],
                            const SizedBox(height: 28),
                            const _Divider(),
                          ],
                        ),
                      ),
                    ),
                    // Logout area
                    const _Divider(),
                    const SizedBox(height: 20),
                    PrimaryActionButton(
                      label: 'Logout',
                      width: double.infinity,
                      onPressed: () {
                        _close(context);
                        onLogout();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Menu',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 25,
              fontWeight: FontWeight.w600,
              color: AppColors.menuText,
            ),
          ),
          // Close menu control: 44x44, radius 18, light blue
          Material(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onClose,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.close,
                    size: 21, color: AppColors.menuButton),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.name, required this.role, this.onTap});
  final String name;
  final String role;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Account avatar 48x48: blue ring + person, white inside
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: const [
                    CircleAvatar(radius: 20, backgroundColor: Colors.white),
                    Icon(Icons.account_circle,
                        size: 48, color: AppColors.menuButton),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.menuText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      role,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.menuMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.onTap});
  final AppMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = item.selected;
    return Material(
      color: selected ? AppColors.inputFill : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                item.iconBuilder?.call(23, AppColors.menuButton) ??
                    Icon(item.icon, size: 23, color: AppColors.menuButton),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.menuButton
                          : AppColors.menuText,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 5,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.menuButton,
                      borderRadius: BorderRadius.circular(3),
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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.menuDivider);
}
