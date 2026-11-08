import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

/// Same width breakpoint as My Portfolio / Favorites / Backups.
const double _kProfileWideBreakpoint = 600;

/// One "Label ........ Value" line inside an info card.
class ProfileRow {
  const ProfileRow(this.label, this.value);
  final String label;
  final String value;
}

/// A light-blue card: a title + its rows.
class ProfileSection {
  const ProfileSection(this.title, this.rows);
  final String title;
  final List<ProfileRow> rows;
}

/// Layout shared by Figma "Instructor Profile" and "Student Profile".
///
/// Lexend is used for everything except the Back button (Inter Bold).
/// NOTE: pubspec currently declares Lexend 600 only. Add Lexend-Regular (400)
/// and Lexend-Bold (700) to match Figma exactly (see instructions).
class ProfileLayout extends StatelessWidget {
  const ProfileLayout({
    super.key,
    required this.name,
    required this.roleLabel,
    required this.sections,
    required this.backIcon,
    required this.backButtonFontSize,
    required this.backButtonBottom,
  });

  final String name;
  final String roleLabel;
  final List<ProfileSection> sections;

  /// Instructor uses a chevron, student uses an arrow (as in Figma).
  final IconData backIcon;

  /// Instructor: 16, Student: 18 (as in Figma).
  final double backButtonFontSize;

  /// Distance from the bottom of the screen to the Back button.
  /// Instructor: 50, Student: 52 (as in Figma, frame height 926).
  final double backButtonBottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= _kProfileWideBreakpoint
          ? _ProfileWeb(
              name: name,
              roleLabel: roleLabel,
              sections: sections,
              onBack: () => Navigator.of(context).maybePop(),
            )
          : _buildMobile(context),
    );
  }

  /// Original phone layout (unchanged).
  Widget _buildMobile(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    final topPad = inset.top + 12; // small margin above the header content
    final bottomPad = inset.bottom + 12; // small margin below the Back button
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    _Header(
                      topPad: topPad,
                      name: name,
                      roleLabel: roleLabel,
                      backIcon: backIcon,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                    // content: padding 24 sides, 32 top, 24 between cards
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                      child: Column(
                        children: [
                          for (var i = 0; i < sections.length; i++) ...[
                            if (i > 0) const SizedBox(height: 24),
                            _InfoCard(section: sections[i]),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Back Button: 160x56, radius 10
                    SizedBox(
                      width: 160,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Back',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: backButtonFontSize,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: backButtonBottom + bottomPad),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.topPad,
    required this.name,
    required this.roleLabel,
    required this.backIcon,
    required this.onBack,
  });

  final double topPad;
  final String name;
  final String roleLabel;
  final IconData backIcon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 171 + topPad,
      padding: EdgeInsets.fromLTRB(24, 16 + topPad, 24, 0),
      decoration: const BoxDecoration(
        // CSS 269.8deg: light blue on the right -> dark blue on the left
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            AppColors.instructorGradientStart, // #007EDE
            AppColors.profileGradientMid, // #0064B1
            AppColors.instructorGradientEnd, // #004478
          ],
          stops: [0.00100, 0.51845, 0.99952],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // top-bar: back button | My Profile | spacer (all 40 wide)
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Material(
                  color: const Color(0x33FFFFFF), // white @ 20%
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onBack,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(backIcon, size: 20, color: Colors.white),
                    ),
                  ),
                ),
                const Text(
                  'My Profile',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // identity-area: avatar 80 + 16 gap + name/role
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.inputFill,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline,
                    size: 48, color: AppColors.menuButton),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF), // white @ 20%
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        roleLabel,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.section});
  final ProfileSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.menuButton, // #0068B8
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < section.rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.rows[i].label,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.profileLabel, // 70% opacity
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.rows[i].value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.menuButton,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


// =============================================================================
// DESKTOP WEB LAYOUT (_kProfileWideBreakpoint and wider)
// =============================================================================
class _ProfileWeb extends StatelessWidget {
  const _ProfileWeb({
    required this.name,
    required this.roleLabel,
    required this.sections,
    required this.onBack,
  });

  final String name;
  final String roleLabel;
  final List<ProfileSection> sections;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _WebTopBar(onBack: onBack),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      AppColors.instructorGradientStart,
                      AppColors.profileGradientMid,
                      AppColors.instructorGradientEnd,
                    ],
                    stops: [0.00100, 0.51845, 0.99952],
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final hPad = c.maxWidth >= 900 ? 40.0 : 24.0;
                    final twoCol = c.maxWidth >= 900;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
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
                                colorFilter: const ColorFilter.mode(
                                    Colors.white, BlendMode.srcIn),
                              ),
                            ),
                          ),
                        ),
                        Scrollbar(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 32),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1200),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _WebPageHeader(onBack: onBack),
                                    const SizedBox(height: 24),
                                    if (twoCol)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 320,
                                            child: _IdentityCard(
                                                name: name, role: roleLabel),
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(
                                            child: _WebSections(
                                                sections: sections),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _IdentityCard(
                                          name: name, role: roleLabel),
                                      const SizedBox(height: 24),
                                      _WebSections(sections: sections),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebTopBar extends StatelessWidget {
  const _WebTopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.menuDivider)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final showBrand = c.maxWidth >= 1000;
          return Row(
            children: [
              Tooltip(
                message: 'Back',
                child: Material(
                  color: AppColors.menuButton,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onBack,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.chevron_left_rounded,
                          size: 29, color: Colors.white),
                    ),
                  ),
                ),
              ),
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
              const SizedBox(width: 24),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onBack,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Home',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.menuMuted,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.menuMuted),
              ),
              const Text(
                'My Profile',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.menuText,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WebPageHeader extends StatelessWidget {
  const _WebPageHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'My Profile',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your account and academic details.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: AppColors.inputFill,
            onTap: onBack,
            child: const SizedBox(
              height: 48,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded,
                        size: 22, color: AppColors.menuButton),
                    SizedBox(width: 10),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.menuButton,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.name, required this.role});
  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              color: AppColors.inputFill,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_outline,
                size: 64, color: AppColors.menuButton),
          ),
          const SizedBox(height: 20),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.menuText,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.menuButton,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSections extends StatelessWidget {
  const _WebSections({required this.sections});
  final List<ProfileSection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 24),
          _WebInfoCard(section: sections[i]),
        ],
      ],
    );
  }
}

class _WebInfoCard extends StatelessWidget {
  const _WebInfoCard({required this.section});
  final ProfileSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.menuButton,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < section.rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AppColors.menuDivider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final label = Text(
                    section.rows[i].label,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.profileLabel,
                    ),
                  );
                  final value = SelectableText(
                    section.rows[i].value,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.menuText,
                    ),
                  );
                  if (c.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [label, const SizedBox(height: 4), value],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 200, child: label),
                      const SizedBox(width: 16),
                      Expanded(child: value),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
