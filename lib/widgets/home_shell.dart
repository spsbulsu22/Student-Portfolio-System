import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/auth_provider.dart';
import '../providers/notification_count_provider.dart';
import '../theme/app_colors.dart';

/// "Welcome, <name>!" - the logged-in account's name (Lexend SemiBold 40).
class _WelcomeText extends ConsumerWidget {
  const _WelcomeText({
    required this.color,
    this.textAlign = TextAlign.start,
    this.shrinkToFit = false,
  });

  final Color color;
  final TextAlign textAlign;
  final bool shrinkToFit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authProvider.select((a) => a.displayName));
    final text = Text(
      'Welcome, $name!',
      textAlign: textAlign,
      style: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 40,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
    return shrinkToFit
        ? FittedBox(fit: BoxFit.scaleDown, child: text)
        : text;
  }
}

/// One big white tile + its caption (Figma: "Quick Upload Button" instances).
class HomeAction {
  const HomeAction({
    required this.label,
    required this.icon,
    required this.buttonTop,
    required this.labelTop,
    this.iconSize = 64,
    this.iconBuilder,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final double buttonTop; // y of the 100x100 tile in the 428x926 frame
  final double labelTop; // y of the caption in the 428x926 frame
  final double iconSize;

  /// Draws a custom logo instead of [icon] (used by Community).
  final Widget Function(double size, Color color)? iconBuilder;
  final VoidCallback? onTap;

  Widget buildIcon(double size, Color color) =>
      iconBuilder?.call(size, color) ?? Icon(icon, size: size, color: color);
}

/// Layout shared by Figma "2 - Home" (student) and "2.2 - Home" (instructor).
///
/// RESPONSIVE:
///  - Narrower than [_wideBreakpoint] (phones): the original Figma layout.
///    Everything is positioned in the Figma frame's own coordinates
///    (428 x 926) and the whole frame is scaled to the screen width. If the
///    screen is shorter than the scaled frame it scrolls. UNCHANGED.
///  - [_wideBreakpoint] or wider (tablets, browser windows): a web-app
///    layout (see [_WideHome]): a fixed top bar (Menu button always at the far
///    left, Profile button always at the far right) and a scrolling blue
///    dashboard underneath.
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.recentTitle,
    required this.actions,
    this.columns = 1,
    this.wideColumns = 1,
    this.onMenuTap,
    this.onProfileTap,
    this.onSearchTap,
  });

  final String recentTitle;
  final List<HomeAction> actions;

  /// Phone layout: tile columns on the LEFT (1 = one vertical column,
  /// 2 = two columns, student: 3 rows x 2 columns). The recent paper stays
  /// where it always was, on the right.
  final int columns;

  /// Wide layout (tablet / desktop): tiles per row in the Quick Actions panel
  /// (3 = student: 2 rows x 3 columns; 1 = one vertical column).
  final int wideColumns;
  final VoidCallback? onMenuTap;

  /// Called with the profile button's on-screen rectangle (so overlays can be
  /// placed right beneath it).
  final ValueChanged<Rect>? onProfileTap;
  final VoidCallback? onSearchTap;

  static const double _w = 428;
  static const double _h = 926;
  static const double _gradientTop = 346;
  static const double _bodyY = 200; // design y where the scaled body starts
  static const double _bodyH = _h - _bodyY;
  static const double _headerPad = 8;
  static const double _headerContent = 58;

  /// Width from which the desktop layout is used (same as the Login screen).
  static const double _wideBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= _wideBreakpoint) {
        return _WideHome(
          recentTitle: recentTitle,
          actions: actions,
          columns: wideColumns,
          onMenuTap: onMenuTap,
          onProfileTap: onProfileTap,
          onSearchTap: onSearchTap,
        );
      }

      // No scrolling: the header (Menu left, Search, Profile right) is laid
      // out at real size across the full width; the rest of the Figma frame
      // (design y 200..926) is scaled uniformly to fit the remaining height
      // and is bottom-aligned, so tall phones keep the original look.
      final topInset = MediaQuery.paddingOf(context).top;
      final headerH = topInset + _headerPad + _headerContent + _headerPad;
      final sw = c.maxWidth / _w;
      final sh = (c.maxHeight - headerH) / _bodyH;
      final s = sh < sw ? sh : sw;
      final bodyW = _w * s;
      final bodyH = _bodyH * s;
      final bodyTop = c.maxHeight - bodyH;

      return SizedBox(
        width: c.maxWidth,
        height: c.maxHeight,
        child: Stack(
          children: [
            // Blue gradient panel (extends to the bottom)
            Positioned(
              top: bodyTop + (_gradientTop - _bodyY) * s,
              left: 0,
              right: 0,
              bottom: 0,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  // CSS 208.5deg, 4.02% -> 95.98% on the 428x580 panel
                  gradient: LinearGradient(
                    begin: Alignment(0.796, -1.0817),
                    end: Alignment(-0.796, 1.0817),
                    colors: [
                      AppColors.instructorGradientStart,
                      AppColors.instructorGradientEnd,
                    ],
                    stops: [0.040192, 0.95981],
                  ),
                ),
              ),
            ),
            // The Figma frame below the header, scaled to fit
            Positioned(
              top: bodyTop,
              left: (c.maxWidth - bodyW) / 2,
              width: bodyW,
              height: bodyH,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: _w,
                  height: _bodyH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: -_bodyY,
                        left: 0,
                        width: _w,
                        height: _h,
                        child: _Frame(
                          recentTitle: recentTitle,
                          actions: actions,
                          columns: columns,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Header: Menu (left), Search, Profile (right)
            Positioned(
              top: topInset + _headerPad,
              left: 12,
              right: 7,
              height: _headerContent,
              child: _MobileHeader(
                onMenuTap: onMenuTap,
                onProfileTap: onProfileTap,
                onSearchTap: onSearchTap,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// =============================================================================
// PHONE LAYOUT: the 428 x 926 design frame.
// =============================================================================
class _Frame extends StatelessWidget {
  const _Frame({
    required this.recentTitle,
    required this.actions,
    this.columns = 1,
  });

  final String recentTitle;
  final List<HomeAction> actions;
  final int columns;

  static const _shadow = [
    BoxShadow(color: Color(0x40000000), offset: Offset(-5, 4), blurRadius: 4),
  ];

  // Up to this many actions keep the original Figma positions (100x100
  // tiles at the caller's buttonTop/labelTop).
  static const int _maxFigmaActions = 4;

  // With more actions (student home: 5) the tiles are laid out evenly and a
  // bit smaller so all of them fit in the 428x926 frame. The first tile must
  // stay below the top edge of the blue panel (y = 346), because the tiles
  // and captions are white.
  static const double _compactTile = 76;
  static const double _compactFirstTop = 366;
  static const double _compactPitch = 110;
  static const double _compactLabelGap = 4;

  /// Tile (white, radius 10) + caption (Inter Bold 16 white) of every action,
  /// centered on x = 83 like the Figma tiles.
  List<Widget> _actionWidgets() {
    if (columns == 2) return _gridWidgets();
    final compact = actions.length > _maxFigmaActions;
    final size = compact ? _compactTile : 100.0;
    return [
      for (var i = 0; i < actions.length; i++) ...[
        Positioned(
          left: 83 - size / 2,
          top: compact
              ? _compactFirstTop + i * _compactPitch
              : actions[i].buttonTop,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: actions[i].onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: actions[i].buildIcon(
                    compact
                        ? actions[i].iconSize * size / 100
                        : actions[i].iconSize,
                    AppColors.homeIcon,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 83 - 64,
          top: compact
              ? _compactFirstTop + i * _compactPitch + size + _compactLabelGap
              : actions[i].labelTop,
          width: 128,
          child: Text(
            actions[i].label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ];
  }

  // Two columns on the LEFT of the frame (student: 3 rows x 2 columns). The
  // recent paper keeps its place on the right (x 164..397, y 453..768), so the
  // grid fits in x 0..160 and spans the SAME vertical band: the first row of
  // tiles starts at the top of the paper (453) and the last caption ends at
  // its bottom (768). Tiles of 64, 12 px captions (two lines if needed).
  static const double _gridTile = 64;
  static const double _gridFirstTop = 453; // top of the back card
  static const double _gridLabelGap = 4;
  static const double _gridLabelH = 29; // two lines of 12 px
  static const double _gridBottom = 768; // bottom of the front card
  static const double _gridPitch = (_gridBottom -
          _gridFirstTop -
          (_gridTile + _gridLabelGap + _gridLabelH)) /
      2; // 3 rows
  static const double _gridLabelW = 76;
  static const List<double> _gridCenters = [44, 122];

  // Student home (two columns): the tiles + the recent paper together span
  // x 12..397 of the 428 frame (12 free on the left, 31 on the right). They
  // are moved right by (31 - 12) / 2 = 9.5 so both sides have 21.5 free.
  // The instructor home (one column, x 33..397) is already balanced.
  double get _dx => columns == 2 ? 9.5 : 0;

  List<Widget> _gridWidgets() {
    return [
      for (var i = 0; i < actions.length; i++) ...[
        Positioned(
          left: _gridCenters[i % 2] + _dx - _gridTile / 2,
          top: _gridFirstTop + (i ~/ 2) * _gridPitch,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: actions[i].onTap,
              child: SizedBox(
                width: _gridTile,
                height: _gridTile,
                child: Center(
                  child: actions[i].buildIcon(
                    actions[i].iconSize * _gridTile / 100,
                    AppColors.homeIcon,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: _gridCenters[i % 2] + _dx - _gridLabelW / 2,
          top: _gridFirstTop +
              (i ~/ 2) * _gridPitch +
              _gridTile +
              _gridLabelGap,
          width: _gridLabelW,
          child: Text(
            actions[i].label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ---- Welcome ------------------------------------------------------
        // Lexend SemiBold 40, centered on x = 214, top = 253
        const Positioned(
          left: -5,
          top: 253,
          width: 438,
          child: _WelcomeText(
            color: Colors.black,
            textAlign: TextAlign.center,
            shrinkToFit: true, // long names scale down instead of wrapping
          ),
        ),

        // ---- Recent documents panel --------------------------------------
        Positioned(
          left: 165 + _dx,
          top: 426,
          child: Text(
            recentTitle,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        // Back card (light blue) 202x292 at (164, 453)
        Positioned(
          left: 164 + _dx,
          top: 453,
          child: Container(
            width: 202,
            height: 292,
            decoration: const BoxDecoration(
              color: AppColors.inputFill,
              boxShadow: _shadow,
            ),
          ),
        ),
        // Front card (white) 202x292 at (195, 476)
        Positioned(
          left: 195 + _dx,
          top: 476,
          child: Container(
            width: 202,
            height: 292,
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: _shadow,
            ),
          ),
        ),
        // Document preview 196x262 at (198, 491)
        Positioned(
          left: 198 + _dx,
          top: 491,
          width: 196,
          height: 262,
          child: _DocumentPreview(),
        ),

        // ---- Action tiles + captions -------------------------------------
        ..._actionWidgets(),
      ],
    );
  }
}

// Phone header at real size: Menu (left), Search, Profile (right). Same visuals as the Figma frame, laid out by width.
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({this.onMenuTap, this.onProfileTap, this.onSearchTap});

  final VoidCallback? onMenuTap;
  final ValueChanged<Rect>? onProfileTap;
  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: AppColors.menuButton,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onMenuTap,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.menu_rounded, color: Colors.white, size: 29),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Material(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(50),
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: onSearchTap,
              child: const SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text(
                      'Search',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0x80000000), // black @ 50%
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        _ProfileButton(onTap: onProfileTap), // 58 x 58
      ],
    );
  }
}

// =============================================================================
// WIDE LAYOUT (tablet / browser): web-app dashboard
// =============================================================================
class _WideHome extends StatelessWidget {
  const _WideHome({
    required this.recentTitle,
    required this.actions,
    this.columns = 1,
    this.onMenuTap,
    this.onProfileTap,
    this.onSearchTap,
  });

  final String recentTitle;
  final List<HomeAction> actions;
  final int columns;
  final VoidCallback? onMenuTap;
  final ValueChanged<Rect>? onProfileTap;
  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Fixed bar: never scrolls, always spans the whole window.
        _WebTopBar(
          onMenuTap: onMenuTap,
          onProfileTap: onProfileTap,
          onSearchTap: onSearchTap,
        ),
        Expanded(
          child: _WebBody(
              recentTitle: recentTitle, actions: actions, columns: columns),
        ),
      ],
    );
  }
}

/// White bar across the top of the window.
///
/// Menu button = first thing on the far left, Profile button = last thing on
/// the far right, whatever the window size. The search bar takes the space in
/// between. On big windows the app name + logo appear next to the menu button.
class _WebTopBar extends StatelessWidget {
  const _WebTopBar({this.onMenuTap, this.onProfileTap, this.onSearchTap});

  final VoidCallback? onMenuTap;
  final ValueChanged<Rect>? onProfileTap;
  final VoidCallback? onSearchTap;

  static const double _height = 72;
  static const double _showBrandFrom = 1000;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      height: _height + topInset,
      // right is 5px smaller: the profile circle sits 5px inside its 58px box
      padding: EdgeInsets.fromLTRB(20, topInset, 15, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.menuDivider)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final showBrand = c.maxWidth >= _showBrandFrom;
          return Row(
            children: [
              _MenuButton(onTap: onMenuTap),
              if (showBrand) ...[
                const SizedBox(width: 16),
                SvgPicture.asset('assets/images/logo.svg',
                    width: 34, height: 34),
                const SizedBox(width: 12),
                const Text(
                  'Student Portfolio System',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandText,
                  ),
                ),
              ],
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _WideSearchBar(onTap: onSearchTap),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _ProfileButton(onTap: onProfileTap),
            ],
          );
        },
      ),
    );
  }
}

/// The blue scrolling area under the top bar: welcome text + two panels
/// ("Quick Actions" and the recent documents). The panels sit side by side on
/// big windows and stack on smaller ones.
class _WebBody extends StatelessWidget {
  const _WebBody({
    required this.recentTitle,
    required this.actions,
    this.columns = 1,
  });

  final String recentTitle;
  final List<HomeAction> actions;
  final int columns; // tiles per row

  static const double _maxContent = 1200;
  static const double _desktopFrom = 1120;
  static const double _recentWidth = 340;

  /// Height of the stacked recent-document cards.
  static const double _stackHeight = 315;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AppColors.instructorGradientStart,
            AppColors.instructorGradientEnd,
          ],
          stops: [0.040192, 0.95981],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final desktop = c.maxWidth >= _desktopFrom;
          final hPad = c.maxWidth >= 900 ? 40.0 : 24.0;

          final actionsPanel = _Panel(
            title: 'Quick Actions',
            expand: desktop,
            child: ConstrainedBox(
              // Side by side, both panels are stretched to the taller one
              // (see the IntrinsicHeight row below); never shorter than the
              // stacked recent cards.
              constraints:
                  BoxConstraints(minHeight: desktop ? _stackHeight : 0),
              child: Align(
                alignment: Alignment.center,
                // Fixed width = exactly [columns] tiles per row (tile 140,
                // gap 20): 3 columns = 2 rows x 3 for six tiles.
                child: SizedBox(
                  width: columns * 140.0 + (columns - 1) * 20.0,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    runSpacing: 28,
                    children: [
                      for (final a in actions) _WideTile(action: a),
                    ],
                  ),
                ),
              ),
            ),
          );

          final recentPanel = _Panel(
            title: recentTitle,
            expand: desktop,
            child: const Center(child: _RecentStack()),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // Big faint logo in the corner (decoration only)
              Positioned(
                right: -90,
                bottom: -90,
                width: 460,
                height: 460,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.07,
                    child: SvgPicture.asset(
                      'assets/images/logo.svg',
                      colorFilter:
                          const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPad, 40, hPad, 56),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxContent),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _WelcomeText(color: Colors.white),
                        const SizedBox(height: 32),
                        if (desktop)
                          // Same height: the row is as tall as the taller panel
                          // and both panels stretch to it.
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: actionsPanel),
                                const SizedBox(width: 24),
                                SizedBox(
                                    width: _recentWidth, child: recentPanel),
                              ],
                            ),
                          )
                        else ...[
                          actionsPanel,
                          const SizedBox(height: 24),
                          recentPanel,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A translucent white card on the blue background, with a heading.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.expand = false,
  });

  final String title;
  final Widget child;

  /// True when the panel is stretched to the height of its row (side by
  /// side layout): the content then fills the rest and is centered in it.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          if (expand) Expanded(child: Center(child: child)) else child,
        ],
      ),
    );
  }
}

/// Menu button of the web top bar. It never changes color; on hover / press it
/// grows, shrinks and gets a halo like the profile button does.
class _MenuButton extends StatelessWidget {
  const _MenuButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _HoverEffect(
      radius: 20,
      haloColor: AppColors.menuButton,
      onTap: onTap,
      semanticLabel: 'Open menu',
      builder: (context, active, pressed) {
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.menuButton,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Icon(Icons.menu_rounded, size: 29, color: Colors.white),
          ),
        );
      },
    );
  }
}

class _WideSearchBar extends StatelessWidget {
  const _WideSearchBar({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: onTap,
        child: const SizedBox(
          width: double.infinity,
          height: 48,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text(
                'Search',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0x80000000), // black @ 50%
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white tile with its caption underneath (same look as the phone tiles).
/// On hover / press the tile behaves like the profile button: it turns light
/// blue, grows a little, and gets a soft halo. The caption stays still.
class _WideTile extends StatelessWidget {
  const _WideTile({required this.action});
  final HomeAction action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverEffect(
            radius: 14,
            // The tiles sit on blue, so the halo is white here.
            haloColor: Colors.white,
            hoverHalo: 0.18,
            pressedHalo: 0.30,
            onTap: action.onTap,
            semanticLabel: action.label,
            builder: (context, active, pressed) {
              final fill = pressed
                  ? _pressedFill
                  : (active ? AppColors.inputFill : Colors.white);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: action.buildIcon(
                    action.iconSize * 1.2,
                    AppColors.homeIcon,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            action.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// The stacked "recent document" cards (same sizes as the phone frame).
class _RecentStack extends StatelessWidget {
  const _RecentStack();

  @override
  Widget build(BuildContext context) {
    // Back card 202x292 at (0, 0); front card at (31, 23); preview at (34, 38)
    return SizedBox(
      width: 233,
      height: 315,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 202,
              height: 292,
              decoration: const BoxDecoration(
                color: AppColors.inputFill,
                boxShadow: _Frame._shadow,
              ),
            ),
          ),
          Positioned(
            left: 31,
            top: 23,
            child: Container(
              width: 202,
              height: 292,
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: _Frame._shadow,
              ),
            ),
          ),
          const Positioned(
            left: 34,
            top: 38,
            width: 196,
            height: 262,
            child: _DocumentPreview(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SHARED HOVER / PRESS EFFECT (web layout)
// =============================================================================

/// Pressed color of the light-blue hover fill (a bit deeper than inputFill).
const Color _pressedFill = Color(0xFFB9D8FF);

/// Same effect as the profile button, for any rounded button:
///  - hover (mouse) or keyboard focus: grows to 106%, soft halo, hand cursor
///  - pressed: shrinks to 92%, stronger halo, springs back on release
/// The widget returned by [builder] is the button itself; it receives
/// `active` (hover/focus) and `pressed` so it can change its own fill.
/// Enter / Space also trigger [onTap] when the button is focused.
class _HoverEffect extends StatefulWidget {
  const _HoverEffect({
    required this.builder,
    required this.radius,
    required this.haloColor,
    this.hoverHalo = 0.12,
    this.pressedHalo = 0.24,
    this.onTap,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, bool active, bool pressed)
      builder;

  /// Corner radius of the button (the halo follows it).
  final double radius;
  final Color haloColor;
  final double hoverHalo;
  final double pressedHalo;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<_HoverEffect> createState() => _HoverEffectState();
}

class _HoverEffectState extends State<_HoverEffect> {
  static const double _inflate = 6;

  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hover || _focus;
    final haloOpacity = _pressed
        ? widget.pressedHalo
        : (active ? widget.hoverHalo : 0.0);
    final scale = _pressed ? 0.92 : (active ? 1.06 : 1.0);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Soft halo behind the button
              Positioned(
                left: -_inflate,
                top: -_inflate,
                right: -_inflate,
                bottom: -_inflate,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(widget.radius + _inflate),
                      color: widget.haloColor.withOpacity(haloOpacity),
                    ),
                  ),
                ),
              ),
              // The button itself (grows on hover, shrinks when pressed)
              AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 130),
                curve: Curves.easeOut,
                child: widget.builder(context, active, _pressed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PROFILE BUTTON (used by both layouts)
// =============================================================================

/// The white circle + blue profile icon, with hover and click effects.
///
/// - Resting: identical to the Figma design (58x58 box, 48px white circle).
/// - Hover (mouse): the button grows a little and a soft blue halo appears.
///   The colors never change. The mouse cursor becomes a hand.
/// - Pressed (mouse down / finger down): the button shrinks slightly and the
///   halo gets stronger. It springs back when released.
class _ProfileButton extends ConsumerStatefulWidget {
  const _ProfileButton({this.onTap});

  /// Called with the button's on-screen rectangle (un-animated, so the
  /// dropdown always lines up with the real position).
  final ValueChanged<Rect>? onTap;

  @override
  ConsumerState<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends ConsumerState<_ProfileButton> {
  final _boxKey = GlobalKey();
  bool _hover = false;
  bool _pressed = false;

  void _handleTap() {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // Global (screen) rect, correct even when a parent scales the content.
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    );
    widget.onTap?.call(rect);
  }

  @override
  Widget build(BuildContext context) {
    final haloOpacity = _pressed ? 0.24 : (_hover ? 0.12 : 0.0);
    final scale = _pressed ? 0.92 : (_hover ? 1.06 : 1.0);
    // Real unread notifications of the account (0 = no badge).
    final unread = ref.watch(unreadNotificationCountProvider);

    return Semantics(
      button: true,
      label: unread > 0
          ? 'Profile menu, $unread unread notifications'
          : 'Profile menu',
      child: SizedBox(
        key: _boxKey,
        width: 58,
        height: 58,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _handleTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Soft halo behind the button
                Positioned(
                  left: -6,
                  top: -6,
                  width: 70,
                  height: 70,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.menuButton.withOpacity(haloOpacity),
                      ),
                    ),
                  ),
                ),
                // The button itself (grows on hover, shrinks when pressed)
                AnimatedScale(
                  scale: scale,
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOut,
                  child: Stack(
                    children: [
                      // White circle 48x48 at (5, 6) inside the 58x58 box
                      Positioned(
                        left: 5,
                        top: 6,
                        width: 48,
                        height: 48,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const Icon(Icons.account_circle,
                          size: 58, color: AppColors.menuButton),
                    ],
                  ),
                ),
                // Unread notifications badge (top right of the button).
                if (unread > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: IgnorePointer(
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 22, minHeight: 22),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.menuButton,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: Colors.white,
                          ),
                        ),
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

// =============================================================================
// SAMPLE DOCUMENT (used by both layouts)
// =============================================================================

/// Figma "image 1" (the sample document). Drop the exported PNG at
/// assets/images/recent_doc.png to use the real image; until then a drawn
/// placeholder page is shown.
class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/recent_doc.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _PlaceholderPage(),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bee Movie Script',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < 38; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3.2),
              child: Container(
                height: 1.6,
                width: i % 7 == 6 ? 90 : double.infinity,
                color: const Color(0xFF9A9A9A),
              ),
            ),
        ],
      ),
    );
  }
}
