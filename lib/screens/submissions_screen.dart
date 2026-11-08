import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/class_service.dart';
import '../theme/app_colors.dart';
import '../utils/slide_route.dart';
import '../widgets/primary_action_button.dart';
import 'instructor_class_detail_screen.dart' show InstructorTaskScreen;
import 'my_portfolio_screen.dart' show kPortfolioWideBreakpoint;

/// One task that students have submitted work for (finalized submissions
/// only, never drafts). Built from the Instructor database.
class SubmissionItem {
  const SubmissionItem({
    required this.course, // class name
    required this.task, // task title
    required this.count, // number of submissions
    this.summary, // the task, to open its submissions
  });

  final String course;
  final String task;
  final int count;
  final TaskSubmissionSummary? summary;

  /// Badge text: "20+" from 20 submissions up (Figma).
  String get badge => count >= 20 ? '20+' : '$count';
}

const _navy = Color(0xFF0A2381);
const _tabText = Color(0xFF001B6E);

/// Figma frame: "3.2 - Submissions Pending" (instructor only).
///
/// Responsive (same breakpoint as My Portfolio): narrower than
/// [kPortfolioWideBreakpoint] shows the phone layout from the Figma frame,
/// wider shows the desktop web layout. Both share the same state and data.
class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({super.key});

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  int _tab = 0; // 0 = Pending, 1 = Reviewed
  List<SubmissionItem> _pending = const [];
  List<SubmissionItem> _reviewed = const [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // New student submissions show up on their own while this page is open.
    _poll = Timer.periodic(
        const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _setTab(int i) => setState(() => _tab = i);

  /// Reads the finalized submissions of the instructor's classes from the
  /// Instructor database. [silent] refreshes in the background: no spinner
  /// and a failure keeps what is already shown.
  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final all = await InstructorClassApi.submissionOverview();
      final pending = <SubmissionItem>[];
      final reviewed = <SubmissionItem>[];
      for (final t in all) {
        if (t.pending > 0) {
          pending.add(SubmissionItem(
              course: t.className,
              task: t.task.title,
              count: t.pending,
              summary: t));
        }
        if (t.reviewed > 0) {
          reviewed.add(SubmissionItem(
              course: t.className,
              task: t.task.title,
              count: t.reviewed,
              summary: t));
        }
      }
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _reviewed = reviewed;
        _loading = false;
        _error = null;
      });
    } on ClassFailure catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// Opens the submissions of one task (files, preview / download, review),
  /// then refreshes the counts because a review moves it to "Reviewed".
  Future<void> _open(SubmissionItem item) async {
    final t = item.summary;
    if (t == null) return;
    await Navigator.of(context).push(
      SlideFromRightRoute(
        page: InstructorTaskScreen(task: t.task, className: t.className),
      ),
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kPortfolioWideBreakpoint
          ? _SubmissionsWeb(
              pending: _pending,
              reviewed: _reviewed,
              tab: _tab,
              onTab: _setTab,
              loading: _loading,
              error: _error,
              onRefresh: _load,
              onOpen: _open,
            )
          : _SubmissionsMobile(
              items: _tab == 0 ? _pending : _reviewed,
              tab: _tab,
              onTab: _setTab,
              loading: _loading,
              error: _error,
              onRefresh: _load,
              onOpen: _open,
            ),
    );
  }
}

// =============================================================================
// SHARED PIECES
// =============================================================================

/// Open-folder icon (Figma: 49 x 36).
class _FolderIcon extends StatelessWidget {
  const _FolderIcon();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(49, 36), painter: _FolderPainter());
}

class _FolderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 49, sy = size.height / 36;
    canvas.scale(sx, sy);
    final stroke = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // back panel with tab
    final back = Path()
      ..moveTo(3, 33)
      ..lineTo(3, 4)
      ..lineTo(17, 4)
      ..lineTo(21, 8.5)
      ..lineTo(40, 8.5)
      ..lineTo(40, 16);
    canvas.drawPath(back, stroke);
    // front flap
    final flap = Path()
      ..moveTo(11, 16)
      ..lineTo(48, 16)
      ..lineTo(41, 34.5)
      ..lineTo(2, 34.5)
      ..close();
    canvas.drawPath(
        flap,
        Paint()
          ..color = _navy
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        flap,
        Paint()
          ..color = _navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Blue count badge on the folder (Figma: 30 x 30, white bold number).
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final size = text.length >= 3 ? 10.0 : (text.length == 2 ? 13.0 : 15.0);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.menuButton,
        shape: BoxShape.circle,
        border: Border.all(color: _navy.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Bootstrap "filter-right" icon (bi:filter-right, 16 x 16 viewBox).
const String _filterRightSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
    '<path fill="#0A2381" d="M14 10.5a.5.5 0 0 0-.5-.5h-3a.5.5 0 0 0 0 1h3a.5.5 0 0 0 .5-.5zm0-3a.5.5 0 0 0-.5-.5h-7a.5.5 0 0 0 0 1h7a.5.5 0 0 0 .5-.5zm0-3a.5.5 0 0 0-.5-.5h-11a.5.5 0 0 0 0 1h11a.5.5 0 0 0 .5-.5z"/>'
    '</svg>';

// =============================================================================
// MOBILE LAYOUT (Figma frame, narrower than kPortfolioWideBreakpoint)
// =============================================================================
class _SubmissionsMobile extends StatelessWidget {
  const _SubmissionsMobile({
    required this.items,
    required this.tab,
    required this.onTab,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<SubmissionItem> items;
  final int tab;
  final ValueChanged<int> onTab;
  final bool loading;
  final String? error;
  final Future<void> Function({bool silent}) onRefresh;
  final ValueChanged<SubmissionItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    final bottomPad = inset.bottom + 12; // small margin below the Home button

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // Header: 114 high gradient, "Submission" 20 bold at the bottom
            Container(
              width: double.infinity,
              height: math.max(114, inset.top + 62),
              padding: const EdgeInsets.fromLTRB(23, 0, 24, 21),
              alignment: Alignment.bottomLeft,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    AppColors.instructorGradientStart, // #007EDE
                    AppColors.instructorGradientEnd, // #004478
                  ],
                ),
              ),
              child: const Text(
                'Submission',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 24 / 20,
                  color: Colors.white,
                ),
              ),
            ),
            // Tabs: Pending | Reviewed (60 high)
            _MobileTabs(tab: tab, onTab: onTab),
            // Filter button (48x48, right side) - no function yet
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 7, right: 16),
                child: IconButton(
                  onPressed: () {
                    // TODO: filter / sort the submissions
                  },
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  padding: EdgeInsets.zero,
                  icon: SvgPicture.string(_filterRightSvg,
                      width: 48, height: 48),
                ),
              ),
            ),
            Expanded(
              child: _LoadGate(
                loading: loading,
                error: error,
                onRetry: () => onRefresh(),
                child: items.isEmpty
                    ? _EmptyState(
                        title: tab == 0
                            ? 'No pending submissions'
                            : 'No reviewed submissions yet',
                        message: tab == 0
                            ? 'Submissions from your students will appear here.'
                            : 'Submissions you review will appear here.',
                      )
                    : RefreshIndicator(
                        onRefresh: () => onRefresh(silent: true),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(15, 9, 16, 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 9),
                          itemBuilder: (_, i) => _MobileCard(
                              item: items[i], onTap: () => onOpen(items[i])),
                        ),
                      ),
              ),
            ),
            // Home button: 104x48, 38 from the left
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(38, 8, 0, 54 + bottomPad),
                child: PrimaryActionButton(
                  label: 'Home',
                  width: 104,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileTabs extends StatelessWidget {
  const _MobileTabs({required this.tab, required this.onTab});
  final int tab;
  final ValueChanged<int> onTab;

  Widget _label(String text, int index) {
    return Expanded(
      child: InkWell(
        onTap: () => onTab(index),
        child: Center(
          child: Opacity(
            opacity: 0.7,
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 24 / 20,
                color: _tabText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          // inactive track (25% navy) under both tabs
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 4,
            child: ColoredBox(color: _navy.withValues(alpha: 0.25)),
          ),
          // active indicator under the selected tab
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 4,
            child: Row(
              children: [
                Expanded(
                  child: ColoredBox(
                      color: tab == 0 ? _navy : Colors.transparent),
                ),
                Expanded(
                  child: ColoredBox(
                      color: tab == 1 ? _navy : Colors.transparent),
                ),
              ],
            ),
          ),
          Row(children: [_label('Pending', 0), _label('Reviewed', 1)]),
        ],
      ),
    );
  }
}

/// Figma card: 86 high, radius 25, #D3E7FF; folder + badge on the left,
/// course label and task title on the right.
class _MobileCard extends StatelessWidget {
  const _MobileCard({required this.item, required this.onTap});
  final SubmissionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill, // #D3E7FF
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        borderRadius: BorderRadius.circular(25),
        onTap: onTap,
        child: SizedBox(
          height: 86,
          child: Stack(
            children: [
              const Positioned(left: 13.5, top: 31, child: _FolderIcon()),
              Positioned(
                  left: 43, top: 30, child: _CountBadge(text: item.badge)),
              Positioned(
                left: 69,
                top: 15,
                right: 16,
                child: Opacity(
                  opacity: 0.7,
                  child: Text(
                    item.course,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 24 / 15,
                      color: Color(0xBF000000), // black @ 75%
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 69,
                top: 42,
                right: 16,
                child: Opacity(
                  opacity: 0.7,
                  child: Text(
                    item.task,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 24 / 20,
                      color: Colors.black,
                    ),
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

/// Spinner while loading, an error with "Try again", otherwise [child].
class _LoadGate extends StatelessWidget {
  const _LoadGate({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.child,
  });
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.menuButton));
    }
    if (error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.menuButton,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return child;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.inputFill,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_outlined,
                  size: 48, color: AppColors.menuButton),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.menuButton,
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: 0.8,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.menuButton,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DESKTOP WEB LAYOUT (kPortfolioWideBreakpoint and wider)
// =============================================================================
class _SubmissionsWeb extends StatefulWidget {
  const _SubmissionsWeb({
    required this.pending,
    required this.reviewed,
    required this.tab,
    required this.onTab,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<SubmissionItem> pending;
  final List<SubmissionItem> reviewed;
  final int tab;
  final ValueChanged<int> onTab;
  final bool loading;
  final String? error;
  final Future<void> Function({bool silent}) onRefresh;
  final ValueChanged<SubmissionItem> onOpen;

  @override
  State<_SubmissionsWeb> createState() => _SubmissionsWebState();
}

class _SubmissionsWebState extends State<_SubmissionsWeb> {
  final _search = TextEditingController();
  bool _ascending = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SubmissionItem> _visible() {
    final q = _search.text.trim().toLowerCase();
    final source = widget.tab == 0 ? widget.pending : widget.reviewed;
    final list = source
        .where((i) =>
            q.isEmpty ||
            i.task.toLowerCase().contains(q) ||
            i.course.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) => _ascending
        ? a.course.toLowerCase().compareTo(b.course.toLowerCase())
        : b.course.toLowerCase().compareTo(a.course.toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    final shown = _visible();
    final total = widget.pending.fold<int>(0, (s, i) => s + i.count);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _SubTopBar(onBack: back),
            Expanded(
              child: DecoratedBox(
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
                    final hPad = c.maxWidth >= 900 ? 40.0 : 24.0;
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
                        Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 24),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 1000),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SubPageHeader(
                                      pendingTotal: total, onHome: back),
                                  const SizedBox(height: 20),
                                  Expanded(
                                    child: _SubListCard(
                                      tab: widget.tab,
                                      onTab: widget.onTab,
                                      pendingCount: widget.pending.length,
                                      reviewedCount: widget.reviewed.length,
                                      search: _search,
                                      onSearchChanged: () => setState(() {}),
                                      ascending: _ascending,
                                      onToggleSort: () => setState(
                                          () => _ascending = !_ascending),
                                      hasAny: (widget.tab == 0
                                              ? widget.pending
                                              : widget.reviewed)
                                          .isNotEmpty,
                                      shown: shown,
                                      loading: widget.loading,
                                      error: widget.error,
                                      onRefresh: widget.onRefresh,
                                      onOpen: widget.onOpen,
                                    ),
                                  ),
                                ],
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

class _SubTopBar extends StatelessWidget {
  const _SubTopBar({required this.onBack});
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
                'Submissions',
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

class _SubPageHeader extends StatelessWidget {
  const _SubPageHeader({required this.pendingTotal, required this.onHome});
  final int pendingTotal;
  final VoidCallback onHome;

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
              'Submissions',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Review the work your students have handed in.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_outlined,
                      size: 22, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    '$pendingTotal pending',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                hoverColor: AppColors.inputFill,
                onTap: onHome,
                child: const SizedBox(
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.home_rounded,
                            size: 22, color: AppColors.menuButton),
                        SizedBox(width: 10),
                        Text(
                          'Home',
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
        ),
      ],
    );
  }
}

class _SubListCard extends StatelessWidget {
  const _SubListCard({
    required this.tab,
    required this.onTab,
    required this.pendingCount,
    required this.reviewedCount,
    required this.search,
    required this.onSearchChanged,
    required this.ascending,
    required this.onToggleSort,
    required this.hasAny,
    required this.shown,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
  });

  final int tab;
  final ValueChanged<int> onTab;
  final int pendingCount;
  final int reviewedCount;
  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final bool ascending;
  final VoidCallback onToggleSort;
  final bool hasAny;
  final List<SubmissionItem> shown;
  final bool loading;
  final String? error;
  final Future<void> Function({bool silent}) onRefresh;
  final ValueChanged<SubmissionItem> onOpen;

  Widget _tabButton(String label, int count, int index) {
    final selected = tab == index;
    return InkWell(
      onTap: () => onTab(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? _navy : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: selected ? _tabText : _tabText.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                _tabButton('Pending', pendingCount, 0),
                _tabButton('Reviewed', reviewedCount, 1),
                const Spacer(),
              ],
            ),
          ),
          Container(height: 1, color: _navy.withValues(alpha: 0.12)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  height: 44,
                  child: TextField(
                    controller: search,
                    onChanged: (_) => onSearchChanged(),
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.menuText),
                    decoration: InputDecoration(
                      hintText: 'Search course or task',
                      hintStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.menuMuted),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 20, color: AppColors.menuMuted),
                      filled: true,
                      fillColor: AppColors.inputFill.withValues(alpha: 0.5),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: ascending ? 'Course A to Z' : 'Course Z to A',
                  child: TextButton.icon(
                    onPressed: onToggleSort,
                    icon: Icon(
                        ascending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 18,
                        color: _navy),
                    label: const Text('Course',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _navy)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _LoadGate(
              loading: loading,
              error: error,
              onRetry: () => onRefresh(),
              child: !hasAny
                ? _EmptyState(
                    title: tab == 0
                        ? 'No pending submissions'
                        : 'No reviewed submissions yet',
                    message: tab == 0
                        ? 'Submissions from your students will appear here.'
                        : 'Submissions you review will appear here.',
                  )
                : shown.isEmpty
                    ? const _EmptyState(
                        title: 'No matching submissions',
                        message: 'Try a different search.',
                      )
                    : Scrollbar(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) => _SubRow(
                              item: shown[i], onTap: () => onOpen(shown[i])),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubRow extends StatefulWidget {
  const _SubRow({required this.item, required this.onTap});
  final SubmissionItem item;
  final VoidCallback onTap;

  @override
  State<_SubRow> createState() => _SubRowState();
}

class _SubRowState extends State<_SubRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover
            ? AppColors.inputFill
            : AppColors.inputFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(25),
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 24, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  height: 56,
                  child: Stack(
                    children: [
                      const Positioned(
                          left: 4, top: 14, child: _FolderIcon()),
                      Positioned(
                          left: 34,
                          top: 12,
                          child: _CountBadge(text: item.badge)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: 0.7,
                        child: Text(
                          item.course,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 24 / 15,
                            color: Color(0xBF000000),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: 0.7,
                        child: Text(
                          item.task,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 24 / 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${item.count} ${item.count == 1 ? 'submission' : 'submissions'}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.menuMuted,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    size: 24, color: _navy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
