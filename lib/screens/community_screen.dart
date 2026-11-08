import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/auth_provider.dart';
import '../providers/notification_count_provider.dart';
import '../services/comment_service.dart';
import '../services/community_service.dart';
import '../services/storage_service.dart' show UploadFailure;
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../utils/logout_flow.dart';
import '../utils/slide_route.dart';
import '../widgets/app_menu.dart';
import '../widgets/profile_dropdown.dart';
import 'backups_screen.dart';
import 'favorites_screen.dart';
import 'instructor_profile_screen.dart';
import 'my_classes_screen.dart';
import 'my_portfolio_screen.dart';
import 'notifications_screen.dart';
import 'student_classes_screen.dart';
import 'student_profile_screen.dart';
import 'submissions_screen.dart';

part '../widgets/comments_panel.dart';

/// Figma frame: "Community Search Results" (428 x 926), both accounts.
///
/// Phone layout = the Figma frame, measured from the top of the header
/// content (the system status bar is real, not drawn). Tablets / browsers
/// (>= 600 px) keep the same design: Menu and Profile stay at the window
/// edges, everything else sits in a centered column.
///
/// The results are the REAL public files (visibility = 'public') of the
/// logged-in user's Supabase project, searched by file name or author
/// (see supabase/community.sql).
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

enum _Load { loading, ready, error }

enum _Sort { newest, oldest, name, author }

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  static const double _wideBreakpoint = 600;
  static const double _wideColumn = 640;

  // Colors read from Figma.
  static const _navy = Color(0xFF0A2381); // icons
  static const _title = Color(0xFF173650); // "Results:", file names

  final _search = TextEditingController();
  Timer? _debounce;
  int _seq = 0; // newer searches win over older answers

  _Load _state = _Load.loading;
  String _error = '';
  List<CommunityFile> _files = const [];
  _Sort _sort = _Sort.newest;

  /// The public file whose "File Viewing" page is open (null = results list).
  CommunityFile? _viewing;

  /// True while the Comments page of [_viewing] is open (Figma: the
  /// "Comments" panel of the File Viewing frame).
  bool _commenting = false;

  /// File likes are kept on this device only (there is no file-likes table).
  final _liked = <String>{};

  @override
  void initState() {
    super.initState();
    _fetch(first: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _fetch);
  }

  Future<void> _fetch({bool first = false}) async {
    _debounce?.cancel();
    final mine = ++_seq;
    if (!first) setState(() => _state = _Load.loading);
    try {
      final rows = await searchCommunityFiles(
        ref.read(authProvider),
        query: _search.text,
      );
      if (!mounted || mine != _seq) return;
      setState(() {
        _files = rows;
        _state = _Load.ready;
      });
    } on UploadFailure catch (e) {
      if (!mounted || mine != _seq) return;
      setState(() {
        _error = e.message;
        _state = _Load.error;
      });
    } catch (_) {
      if (!mounted || mine != _seq) return;
      setState(() {
        _error = 'Could not load public files. Try again.';
        _state = _Load.error;
      });
    }
  }

  List<CommunityFile> get _sorted {
    final list = [..._files];
    int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Sort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _Sort.name:
        list.sort((a, b) => byText(a.name, b.name));
      case _Sort.author:
        list.sort((a, b) => byText(a.authorName, b.authorName));
    }
    return list;
  }

  /// Tap on a result -> Figma frame "File Viewing".
  void _open(CommunityFile file) => setState(() => _viewing = file);

  void _closeViewer() => setState(() {
        _viewing = null;
        _commenting = false;
      });

  void _openComments() => setState(() => _commenting = true);

  void _closeComments() => setState(() => _commenting = false);

  void _toggleLike(CommunityFile file) => setState(() {
        if (!_liked.add(file.id)) _liked.remove(file.id);
      });

  /// Copies a temporary (1 hour) link to the file.
  Future<void> _share(CommunityFile file) async {
    try {
      final url = await communityFileUrl(ref.read(authProvider), file);
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        showPortfolioMessage(context, 'Link copied. It works for 1 hour.');
      }
    } on UploadFailure catch (e) {
      if (mounted) showPortfolioMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showPortfolioMessage(context, 'Could not copy the link.', error: true);
      }
    }
  }

  /// Opens the real file (new browser tab) - the placeholder is tappable.
  void _openInBrowser(CommunityFile file) {
    openPortfolioUrl(
      context,
      () => communityFileUrl(ref.read(authProvider), file),
      inline: true,
    );
  }

  // ------------------------------------------------------- menu / profile

  bool get _isInstructor => ref.read(authProvider).role == UserRole.instructor;

  void _go(Widget page) => Navigator.of(context)
      .pushReplacement(SlideFromRightRoute(page: page)); // Back = Home

  void _goHome() => Navigator.of(context).popUntil((r) => r.isFirst);

  void _openMenu() {
    final instructor = _isInstructor;
    showAppMenu(
      context,
      accountName: ref.read(authProvider).displayName,
      accountRole: instructor ? 'Instructor account' : 'Student account',
      items: [
        AppMenuItem(
          label: 'Home',
          icon: Icons.home_outlined,
          onTap: _goHome,
        ),
        if (instructor) ...[
          AppMenuItem(
            label: 'Submissions',
            icon: Icons.assignment_outlined,
            onTap: () => _go(const SubmissionsScreen()),
          ),
          AppMenuItem(
            label: 'My Classes',
            icon: Icons.people_outline,
            onTap: () => _go(const MyClassesScreen()),
          ),
        ] else ...[
          AppMenuItem(
            label: 'My Portfolio',
            icon: Icons.folder_outlined,
            onTap: () => _go(const MyPortfolioScreen()),
          ),
          AppMenuItem(
            label: 'Favorites',
            icon: Icons.star_outline_rounded,
            onTap: () => _go(const FavoritesScreen()),
          ),
          AppMenuItem(
            label: 'Backups',
            icon: Icons.history,
            onTap: () => _go(const BackupsScreen()),
          ),
          AppMenuItem(
            label: 'My Classes',
            icon: Icons.people_outline,
            onTap: () => _go(const StudentClassesScreen()),
          ),
        ],
        const AppMenuItem(
          label: 'Community',
          icon: kCommunityFallbackIcon,
          iconBuilder: communityIconBuilder,
          selected: true, // already here -> menu just closes
        ),
      ],
      onAccountTap: () => _go(
        instructor
            ? const InstructorProfileScreen()
            : const StudentProfileScreen(),
      ),
      onLogout: _logout,
    );
  }

  void _logout() => logoutAndReturnToLogin(
        context,
        ref,
        _isInstructor ? UserRole.instructor : UserRole.student,
      );

  void _openProfileDropdown(Rect anchor) {
    final instructor = _isInstructor;
    showProfileDropdown(
      context,
      anchor: anchor,
      onMyProfile: () => _go(
        instructor
            ? const InstructorProfileScreen()
            : const StudentProfileScreen(),
      ),
      onNotifications: () => _go(
        instructor
            ? const NotificationsScreen(instructor: true)
            : const NotificationsScreen(student: true),
      ),
      onLogout: _logout,
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    final viewing = _viewing;
    return PopScope(
      // System Back closes Comments, then the file page, then Community.
      canPop: viewing == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_commenting) {
          _closeComments(); // Comments -> file page
        } else if (_viewing != null) {
          _closeViewer(); // file page -> results
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final wide = w >= _wideBreakpoint;
            final cw = wide ? math.min(w, _wideColumn) : w;
            // Figma y = 57 (Profile button top) is where the content starts.
            final top = inset.top + 8;

            Widget page({required bool viewer}) {
              // Results: header ends at y = 189. File viewing: y = 137.
              final headerH = top + (viewer ? 80 : 132);
              return Column(
                children: [
                  _header(
                    w: w,
                    cw: cw,
                    wide: wide,
                    top: top,
                    headerH: headerH,
                    viewing: viewer,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: cw,
                        child: !viewer
                            ? _results(wide: wide, bottom: inset.bottom)
                            : _commenting
                                ? _CommentsPage(
                                    // New file -> fresh comments.
                                    key: ValueKey('comments-${_viewing!.id}'),
                                    file: _viewing!,
                                    onBack: _closeComments,
                                    bottom: inset.bottom,
                                  )
                                : _fileView(_viewing!, bottom: inset.bottom),
                      ),
                    ),
                  ),
                ],
              );
            }

            // The results stay mounted underneath, so going back keeps the
            // scroll position and the search text. The file page dissolves in
            // (Figma prototype: dissolve, ease out).
            return Stack(
              children: [
                Positioned.fill(child: page(viewer: false)),
                if (viewing != null)
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(viewing.id),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      builder: (_, t, child) => Opacity(opacity: t, child: child),
                      child: Material(
                        color: Colors.white,
                        child: page(viewer: true),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ------------------------------------------------------- file viewing

  /// Figma frame: "File Viewing" (428 x 926). Positions below are measured
  /// from the frame: back button y = 151, file info y = 207, buttons y = 788.
  Widget _fileView(CommunityFile file, {required double bottom}) {
    final liked = _liked.contains(file.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14), // header ends y = 137, back button y = 151
        Padding(
          padding: const EdgeInsets.only(left: 19),
          child: _BackCircle(onTap: _closeViewer),
        ),
        const SizedBox(height: 16), // back button ends y = 191, info y = 207
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: _FileInfo(file: file),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Center(
              child: _FilePlaceholder(
                type: file.fileType,
                onTap: () => _openInBrowser(file),
              ),
            ),
          ),
        ),
        Padding(
          // Three 56 x 56 buttons at x = 59 / 186 / 313 of a 428 frame.
          padding: EdgeInsets.fromLTRB(59, 0, 59, bottom + 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ActionCircle(
                label: liked ? 'Remove like' : 'Like',
                onTap: () => _toggleLike(file),
                child: Icon(
                  Icons.thumb_up,
                  size: 34,
                  color: liked ? AppColors.menuButton : _navy,
                ),
              ),
              _ActionCircle(
                label: 'Add a comment',
                onTap: _openComments,
                child: const Icon(Icons.add_comment, size: 36, color: _navy),
              ),
              _ActionCircle(
                label: 'Share',
                onTap: () => _share(file),
                child: const Icon(Icons.share, size: 30, color: _navy),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header({
    required double w,
    required double cw,
    required bool wide,
    required double top,
    required double headerH,
    bool viewing = false,
  }) {
    // Figma: 220.99deg, #007EDE (4.02%) -> #004478 (95.98%) on the full
    // 428 x 928 frame; only its top part shows. Same line, any width.
    const gh = 928.0;
    const sx = 0.6561; // |sin 220.99deg|
    const sy = 0.7547; // |cos 220.99deg|
    final len = w * sx + gh * sy;
    final ax = sx * len / w;
    final ay = -sy * len / gh;

    return SizedBox(
      height: headerH,
      width: w,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: gh,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(ax, ay),
                    end: Alignment(-ax, -ay),
                    colors: const [
                      AppColors.instructorGradientStart,
                      AppColors.instructorGradientEnd,
                    ],
                    stops: const [0.040192, 0.95981],
                  ),
                ),
              ),
            ),
            // Decorative swoosh (Figma "Vector": white @ 10%, x -238, y 16).
            Positioned(
              left: -238,
              top: top - 41,
              width: 329,
              height: 331,
              child: IgnorePointer(
                child: SvgPicture.string(
                  '<svg xmlns="http://www.w3.org/2000/svg" width="329" '
                  'height="331" viewBox="0 0 329 331"><path fill="#FFFFFF" '
                  'fill-opacity="0.1" d="$_swooshPath"/></svg>',
                ),
              ),
            ),
            // Title + search bar, in the (centered) column.
            Positioned.fill(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: cw,
                  child: Stack(
                    children: [
                      if (!viewing)
                        Positioned(
                          left: wide ? 43 : 71,
                          right: wide ? 43 : 62,
                          top: top + 20,
                          child: const Text(
                            'Community Search',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      // File viewing: search bar sits beside the Menu button
                      // (Figma x = 69, 341 wide, y = 63).
                      Positioned(
                        left: viewing ? 69 : 43,
                        right: viewing ? 18 : 44,
                        top: viewing ? top + 6 : top + 60,
                        height: 54,
                        child: _searchBar(viewing: viewing),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Menu button (left edge) and Profile button (right edge).
            Positioned(
              left: 12,
              top: top + 6,
              child: _MenuButton(onTap: _openMenu),
            ),
            // The File Viewing frame has no Profile button (the search bar
            // takes its place).
            if (!viewing)
              Positioned(
                right: 2,
                top: top,
                child: _ProfileButton(onTap: _openProfileDropdown),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar({bool viewing = false}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned(
            left: 7,
            right: 63,
            top: 0,
            bottom: 0,
            child: Center(
              child: TextField(
                controller: _search,
                // On the file page, searching closes it and shows the results.
                onChanged: viewing ? null : _onChanged,
                onSubmitted: (_) {
                  if (viewing) _closeViewer();
                  _fetch();
                },
                textInputAction: TextInputAction.search,
                textAlign: TextAlign.center,
                maxLines: 1,
                cursorColor: AppColors.menuButton,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search Public files by name or author',
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0x80000000), // black @ 50%
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 21,
            top: 16,
            child: IgnorePointer(
              child: _svg(
                '<circle cx="8.5" cy="8.5" r="8.5"/>'
                '<path d="M19 19 L14.514 14.506"/>',
                w: 21,
                h: 21,
                viewBox: '-1 -1 21 21',
                stroke: _navy,
                strokeWidth: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results({required bool wide, required double bottom}) {
    final sorted = _sorted;
    final left = wide ? 43.0 : 50.0;
    final filterRight = wide ? 43.0 : 51.0;

    Widget body;
    switch (_state) {
      case _Load.loading:
        body = const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 60),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.menuButton,
              ),
            ),
          ),
        );
      case _Load.error:
        body = Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error, textAlign: TextAlign.center, style: _endStyle),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _fetch,
                  child: const Text(
                    'Try again',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.link,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _Load.ready:
        final empty = sorted.isEmpty;
        body = ListView.builder(
          padding: EdgeInsets.fromLTRB(
            wide ? 43 : 39,
            20,
            wide ? 43 : 49,
            bottom + 24,
          ),
          itemCount: empty ? 1 : sorted.length + 1,
          itemBuilder: (context, i) {
            if (empty) {
              return Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Text(
                  _search.text.trim().isEmpty
                      ? 'No public files yet'
                      : 'No results found',
                  textAlign: TextAlign.center,
                  style: _endStyle,
                ),
              );
            }
            if (i == sorted.length) {
              // Figma: 35 px under the last card (9 of it is the card gap).
              return const Padding(
                padding: EdgeInsets.only(top: 26),
                child: Text(
                  'End of results',
                  textAlign: TextAlign.center,
                  style: _endStyle,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _ResultCard(file: sorted[i], onTap: () => _open(sorted[i])),
            );
          },
        );
    }

    return Column(
      children: [
        const SizedBox(height: 19),
        SizedBox(
          height: 48,
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: 12,
                child: const Text(
                  'Results:',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _title,
                  ),
                ),
              ),
              Positioned(right: filterRight, top: 0, child: _filterButton()),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  static const _endStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0x4D000000), // black @ 30%
  );

  Widget _filterButton() {
    const labels = {
      _Sort.newest: 'Newest first',
      _Sort.oldest: 'Oldest first',
      _Sort.name: 'Name A-Z',
      _Sort.author: 'Author A-Z',
    };
    return PopupMenuButton<_Sort>(
      tooltip: 'Sort results',
      position: PopupMenuPosition.under,
      color: Colors.white,
      elevation: 6,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (s) => setState(() => _sort = s),
      itemBuilder: (_) => [
        for (final s in _Sort.values)
          PopupMenuItem<_Sort>(
            value: s,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: s == _sort
                      ? const Icon(Icons.check, size: 18, color: _navy)
                      : null,
                ),
                Text(
                  labels[s]!,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _title,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: [
            Positioned(
              left: 6,
              top: 12,
              child: _svg(
                '<rect x="24" y="18" width="12" height="3" rx="1.5"/>'
                '<rect x="12" y="9" width="24" height="3" rx="1.5"/>'
                '<rect x="0" y="0" width="36" height="3" rx="1.5"/>',
                w: 36,
                h: 21,
                fill: _navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Pieces
// =============================================================================

/// Inline SVG helper: [body] drawn in a [w] x [h] box (optionally with its own
/// [viewBox]), filled with [fill] or stroked with [stroke].
Widget _svg(
  String body, {
  required double w,
  required double h,
  String? viewBox,
  Color? fill,
  Color? stroke,
  double strokeWidth = 2,
}) {
  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  final paint = fill != null
      ? 'fill="${hex(fill)}"'
      : 'fill="none" stroke="${hex(stroke!)}" stroke-width="$strokeWidth" '
          'stroke-linecap="round"';
  return SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
    'viewBox="${viewBox ?? '0 0 $w $h'}" $paint>$body</svg>',
    width: w,
    height: h,
  );
}

/// Figma "Menu Button": #FBFBFB, radius 20, 48 x 48, three #0068B8 lines.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open menu',
      child: Material(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: _svg(
                '<path d="M0 0 H16.917 M0 7.25 H16.917 M0 14.5 H16.917"/>',
                w: 18.917,
                h: 16.5,
                viewBox: '-1 -1 18.917 16.5',
                stroke: AppColors.menuButton,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma "Profile Button" (58 x 58), same look as the Home screens, with the
/// real unread-notifications badge.
class _ProfileButton extends ConsumerStatefulWidget {
  const _ProfileButton({required this.onTap});

  /// Called with the button's on-screen rectangle (for the dropdown).
  final ValueChanged<Rect> onTap;

  @override
  ConsumerState<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends ConsumerState<_ProfileButton> {
  final _boxKey = GlobalKey();
  bool _pressed = false;

  void _handleTap() {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    );
    widget.onTap(rect);
  }

  @override
  Widget build(BuildContext context) {
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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _handleTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  scale: _pressed ? 0.92 : 1.0,
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOut,
                  // White disc, blue person (white-blue, not blue-white).
                  child: SvgPicture.string(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="58" '
                    'height="58" viewBox="0 0 58 58"><defs><clipPath id="c">'
                    '<circle cx="29" cy="29" r="24"/></clipPath></defs>'
                    '<circle cx="29" cy="29" r="29" fill="#FFFFFF"/>'
                    '<circle cx="29" cy="29" r="26" fill="none" '
                    'stroke="#0068B8" stroke-width="3"/>'
                    '<g clip-path="url(#c)" fill="#0068B8">'
                    '<circle cx="29" cy="23" r="9"/>'
                    '<ellipse cx="29" cy="52" rx="19" ry="15"/></g></svg>',
                    width: 58,
                    height: 58,
                  ),
                ),
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

/// One result: #D3E7FF, radius 8, 68 high (Figma "Group 3/4/5").
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.file, required this.onTap});

  final CommunityFile file;
  final VoidCallback onTap;

  static const _navy = Color(0xFF0A2381);
  static const _grey = Color(0x86000000); // black @ 75% x 70% opacity

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December', //
  ];

  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// Figma icons: file-text (PDF), file-type (Word-like) and file (the rest).
  static String _iconBody(String type) {
    switch (type) {
      case 'pdf':
        return '$_fileBase$_textLines';
      case 'doc':
      case 'docx':
      case 'rtf':
      case 'txt':
        return '$_fileBase$_typeLines';
      default:
        return _fileBase;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = file.fileType.toLowerCase();
    return Material(
      color: const Color(0xFFD3E7FF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 68,
          child: Stack(
            children: [
              // White tile 30 x 30, radius 12, with the 24 x 24 icon.
              Positioned(
                left: 8,
                top: 5,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _svg(
                    '<g transform="translate(4.0008 1.9992)">'
                    '${_iconBody(type)}</g>',
                    w: 24,
                    h: 24,
                    viewBox: '0 0 24 24',
                    stroke: _navy,
                    strokeWidth: 2,
                  ),
                ),
              ),
              Positioned(
                left: 44,
                top: 5,
                child: Text(
                  type.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 24 / 15,
                    color: _grey,
                  ),
                ),
              ),
              Positioned(
                left: 42,
                right: 8,
                top: 27,
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF173650),
                  ),
                ),
              ),
              Positioned(
                left: 44,
                right: 8,
                top: 42,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Author: ${file.authorName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _small,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_date(file.createdAt), style: _small),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _small = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 2, // 24 px line, like Figma
    color: _grey,
  );
}

// -----------------------------------------------------------------------------
// File Viewing pieces
// -----------------------------------------------------------------------------

/// Figma "back-btn": #D3E7FF, radius 20, 40 x 40, chevron 20 x 20.
class _BackCircle extends StatelessWidget {
  const _BackCircle({required this.onTap, this.label = 'Back to results'});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: _svg(
                '<path d="M12 4 L6 10 L12 16"/>',
                w: 20,
                h: 20,
                stroke: const Color(0xFF0A2381),
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma "back-btn" used as an action: #D3E7FF, radius 20, 56 x 56.
class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SizedBox(width: 56, height: 56, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Figma "Group 5": file icon, type, name, author and date (384 x 60).
class _FileInfo extends StatelessWidget {
  const _FileInfo({required this.file});
  final CommunityFile file;

  static const _navy = Color(0xFF0A2381);

  @override
  Widget build(BuildContext context) {
    final type = file.fileType.toLowerCase();
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          // White tile 33.8 x 29.5, radius 12, with the 24 x 24 icon.
          Positioned(
            left: 0,
            top: 2,
            child: Container(
              width: 34,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _svg(
                '<g transform="translate(4.0008 1.9992)">'
                '${_ResultCard._iconBody(type)}</g>',
                w: 24,
                h: 24,
                viewBox: '0 0 24 24',
                stroke: _navy,
                strokeWidth: 2,
              ),
            ),
          ),
          Positioned(
            left: 39,
            right: 0,
            top: 0,
            child: Text(
              type.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 24 / 15,
                color: _ResultCard._grey,
              ),
            ),
          ),
          Positioned(
            left: 37,
            right: 0,
            top: 21,
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF173650),
              ),
            ),
          ),
          Positioned(
            left: 39,
            right: 33, // the date ends at x = 373 of the 428 frame
            top: 36,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Author: ${file.authorName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _ResultCard._small,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_ResultCard._date(file.createdAt),
                    style: _ResultCard._small),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands in for the file itself: it never shows the real content, only the
/// file type (PDF, PNG, JPG, DOCX ...). Tapping it opens the real file.
class _FilePlaceholder extends StatelessWidget {
  const _FilePlaceholder({required this.type, required this.onTap});

  final String type;
  final VoidCallback onTap;

  static const _navy = Color(0xFF0A2381);

  static String _kind(String t) {
    switch (t) {
      case 'pdf':
        return 'PDF document';
      case 'doc':
      case 'docx':
      case 'rtf':
      case 'txt':
        return 'Document';
      case 'xls':
      case 'xlsx':
      case 'csv':
        return 'Spreadsheet';
      case 'ppt':
      case 'pptx':
        return 'Presentation';
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return 'Image';
      case 'mp4':
      case 'mov':
      case 'webm':
        return 'Video';
      case 'mp3':
      case 'wav':
        return 'Audio';
      case 'zip':
        return 'Archive';
      default:
        return 'File';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = type.toLowerCase();
    final label = t.isEmpty ? 'FILE' : t.toUpperCase();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384, maxHeight: 440),
      child: AspectRatio(
        aspectRatio: 0.85,
        child: Semantics(
          button: true,
          label: '$label file, tap to open',
          child: Material(
            color: const Color(0x73D3E7FF), // #D3E7FF @ 45%
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.dropdownBorder),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _svg(
                          '<g transform="translate(4.0008 1.9992)">'
                          '${_ResultCard._iconBody(t)}</g>',
                          w: 96,
                          h: 96,
                          viewBox: '0 0 24 24',
                          stroke: _navy,
                          strokeWidth: 0.9,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF173650),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_kind(t), style: _ResultCard._small),
                        const SizedBox(height: 12),
                        const Text(
                          'Tap to open file',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.menuButton,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Vector data copied from the Figma frame (rounded for size).
// -----------------------------------------------------------------------------

/// Decorative swoosh "Vector" (329 x 331).
const String _swooshPath =
    'M 169.8 219.6 C 192.1 246.4 225.8 247.1 249.1 219.1 L 319.6 133.7 C 322.9 129.3 322.9 122.6 319.5 118.7 C 315.9 114.9 311 114.9 307.4 119.1 L 237.5 203.8 C 220.9 223.8 197.7 223.8 182.3 204.7 C 166.6 185.2 166.4 157.5 182.9 137.5 L 271.1 31 C 282 17.8 296.8 17.6 306 28.4 C 315 39.2 314.9 57.1 303.8 70.5 L 217.9 175.1 C 214.5 179.5 209.9 179.3 206.7 175.1 C 203.1 170.9 203.3 165.5 206.9 161.2 L 267.6 87.6 C 271.2 83.2 271.1 77.3 267.9 73.3 C 264.6 69.5 259.9 69.3 256.3 73.8 L 195.1 147.8 C 185 160 185 178.8 194.4 189.9 C 204.3 201.6 218.8 201.6 229 189.2 L 315.5 84.6 C 333.4 62.7 333.1 34 316.9 14.3 C 300.8 -4.8 276.5 -5.3 259 16.1 L 170.4 123.4 C 147.1 151.6 147.8 193 169.8 219.6 Z M 44.5 331 L 281.3 331 C 311 331 325.8 313.4 325.8 277.9 L 325.8 168.1 L 302.7 196.7 L 302.7 276.5 C 302.7 294.3 295.1 303 281 303 L 44.8 303 C 30.6 303 23.1 294.3 23.1 276.5 L 23.1 80.3 C 23.1 62.5 30.6 53.7 44.8 53.7 L 192.2 53.7 L 215.2 25.8 L 44.5 25.8 C 14.8 25.8 0 43.2 0 78.9 L 0 277.9 C 0 313.4 14.8 331 44.5 331';

/// File outline shared by the three file icons (16 x 20 inside the 24 box).
const String _fileBase =
    '<path d="M 9.999 0 L 2 0 C 1.4694 0 0.9608 0.2107 0.5857 0.5858 C 0.2107 0.9609 0 1.4697 0 2.0002 L 0 18.0014 C 0 18.5319 0.2107 19.0407 0.5857 19.4158 C 0.9608 19.7909 1.4694 20.0016 2 20.0016 L 13.9986 20.0016 C 14.529 20.0016 15.0376 19.7909 15.4127 19.4158 C 15.7877 19.0407 15.9984 18.5319 15.9984 18.0014 L 15.9984 6.0005 M 9.999 0 C 10.3155 -0.0005 10.629 0.0616 10.9214 0.1828 C 11.2139 0.304 11.4794 0.4818 11.7028 0.7061 L 15.2905 4.2943 C 15.5153 4.5179 15.6936 4.7837 15.8151 5.0766 C 15.9366 5.3694 15.9989 5.6834 15.9984 6.0005 M 9.999 0 L 9.999 5.0004 C 9.999 5.2656 10.1043 5.52 10.2919 5.7076 C 10.4794 5.8951 10.7337 6.0005 10.9989 6.0005 L 15.9984 6.0005"/>';

/// PDF: text lines.
const String _textLines =
    '<path d=" M 6 7.0006 L 4 7.0006 M 12 11.0009 L 4 11.0009 M 12 15.0012 L 4 15.0012"/>';

/// Word-like: the "T" mark.
const String _typeLines =
    '<path d=" M 7 16.0013 L 9 16.0013 M 8 10.0008 L 8 16.0013 M 5 11.0009 L 5 10.5008 C 5 10.3682 5.0522 10.241 5.1459 10.1473 C 5.2397 10.0535 5.3669 10.0008 5.4994 10.0008 L 10.4989 10.0008 C 10.6315 10.0008 10.7587 10.0535 10.8525 10.1473 C 10.9462 10.241 10.9989 10.3682 10.9989 10.5008 L 10.9989 11.0009"/>';
