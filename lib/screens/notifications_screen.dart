import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/notification_count_provider.dart';
import '../services/class_service.dart';
import '../theme/app_colors.dart';
import '../utils/slide_route.dart';
import 'my_classes_screen.dart' show MyClassesScreen;
import 'my_portfolio_screen.dart' show kPortfolioWideBreakpoint;
import 'student_class_detail_screen.dart';
import 'student_classes_screen.dart';

/// One notification. Fill the list later from your backend (e.g. Supabase).
class AppNotification {
  const AppNotification({
    required this.title,
    required this.message,
    required this.timeAgo,
    this.isUnread = false,
    this.onTap,
  });

  final String title;
  final String message;
  final String timeAgo; // relevant date / time text
  final bool isUnread;
  final VoidCallback? onTap; // opens what the notification is about
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
  'Dec',
];

/// "5 min ago · Nov 6, 2026 3:05 PM" (the relative part only for recent ones).
String _whenText(DateTime? d) {
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final abs = '${_monthNames[d.month - 1]} ${d.day}, ${d.year} '
      '$h:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
  final diff = DateTime.now().difference(d);
  String? rel;
  if (diff.inMinutes < 1) {
    rel = 'Just now';
  } else if (diff.inMinutes < 60) {
    rel = '${diff.inMinutes} min ago';
  } else if (diff.inHours < 24) {
    rel = '${diff.inHours} h ago';
  } else if (diff.inDays < 7) {
    rel = '${diff.inDays} d ago';
  }
  return rel == null ? abs : '$rel · $abs';
}

/// Figma frame: "Instructor Notification Panel" (used for both roles).
///
/// With [student] = true the notifications of the logged-in student are read
/// from the Instructor project (through a secure Edge Function): class
/// request accepted, class invitation, new assignment and submission
/// reviewed. Tapping one opens the class / invitations it is about. Without
/// it the page shows [notifications] (empty for instructors for now).
///
/// Responsive (same breakpoint as My Portfolio): narrower than
/// [kPortfolioWideBreakpoint] shows the original phone layout, wider shows
/// the desktop web layout.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({
    super.key,
    this.notifications = const <AppNotification>[],
    this.student = false,
    this.instructor = false,
  });

  final List<AppNotification> notifications;
  final bool student;

  /// Instructor: one notification per task ("2 students submitted Task 3.");
  /// tapping it opens My Classes -> the class -> the task's submissions.
  final bool instructor;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<StudentNotification> _items = const [];
  List<InstructorNotification> _teacherItems = const [];
  bool _loading = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.student || widget.instructor) {
      _loading = true;
      _load();
      // New notifications show up on their own while the page is open.
      _poll = Timer.periodic(
          const Duration(seconds: 30), (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (widget.instructor) {
        final list = await InstructorClassApi.notifications();
        if (!mounted) return;
        setState(() {
          _teacherItems = list;
          _loading = false;
          _error = null;
        });
        // Badge = all unread tasks (the list shows at most the latest 100).
        ref.read(unreadNotificationCountProvider.notifier).refresh();
        return;
      }
      final list = await StudentClassApi.notifications();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
      ref
          .read(unreadNotificationCountProvider.notifier)
          .setCount(list.where((n) => !n.isRead).length);
    } on ClassFailure catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// Marks the notification as read, then opens its destination.
  Future<void> _open(StudentNotification n) async {
    if (!n.isRead) {
      setState(() => _items = [
            for (final x in _items) x.id == n.id ? x.asRead() : x,
          ]);
      final badge = ref.read(unreadNotificationCountProvider.notifier);
      badge.markedRead();
      StudentClassApi.markNotificationsRead([n.id])
          .catchError((_) {})
          .whenComplete(badge.refresh);
    }
    final Widget? page;
    switch (n.type) {
      case kNotifRequestAccepted:
        // My Classes -> the actual class
        page = StudentClassesScreen(openClassId: n.classId);
      case kNotifInvitation:
        // My Classes -> the invitations
        page = const StudentClassesScreen(focusInvitations: true);
      case kNotifNewAssignment:
      case kNotifSubmissionReviewed:
        // the actual class -> its task section
        final id = n.classId;
        if (id == null) {
          page = null;
        } else {
          page = StudentClassDetailScreen(
            room: n.room ??
                ClassRoom(
                    id: id,
                    name: 'Class',
                    description: '',
                    code: '',
                    instructorName: ''),
            focusTaskId: n.assignmentId,
          );
        }
      default:
        page = null;
    }
    if (page == null || !mounted) return;
    await Navigator.of(context).push(SlideFromRightRoute(page: page));
    if (mounted) _load(silent: true);
  }

  /// Marks the task notification read, then opens My Classes -> the class ->
  /// the task -> its submissions (each screen pushes the next one).
  Future<void> _openTask(InstructorNotification n) async {
    if (!n.isRead) {
      setState(() => _teacherItems = [
            for (final x in _teacherItems) x.id == n.id ? x.asRead() : x,
          ]);
      final badge = ref.read(unreadNotificationCountProvider.notifier);
      badge.markedRead();
      InstructorClassApi.markNotificationRead(n.id)
          .catchError((_) {})
          .whenComplete(badge.refresh);
    }
    await Navigator.of(context).push(
      SlideFromRightRoute(
        page: MyClassesScreen(
            openClassId: n.classId, openTaskId: n.assignmentId),
      ),
    );
    if (mounted) _load(silent: true); // new submissions may have arrived
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.student || widget.instructor;
    final empty = widget.instructor ? _teacherItems.isEmpty : _items.isEmpty;
    if (live && _loading) {
      return const _NfStatus(loading: true);
    }
    if (live && _error != null && empty) {
      return _NfStatus(error: _error, onRetry: _load);
    }
    final list = widget.instructor
        ? [
            for (final n in _teacherItems)
              AppNotification(
                title: n.title,
                message: n.message,
                timeAgo: _whenText(n.updatedAt),
                isUnread: !n.isRead,
                onTap: () => _openTask(n),
              ),
          ]
        : widget.student
        ? [
            for (final n in _items)
              AppNotification(
                title: n.title,
                message: n.message,
                timeAgo: _whenText(n.createdAt),
                isUnread: !n.isRead,
                onTap: () => _open(n),
              ),
          ]
        : widget.notifications;
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kPortfolioWideBreakpoint
          ? _NotificationsWeb(notifications: list)
          : _NotificationsMobile(notifications: list),
    );
  }
}

/// Spinner while the first load runs, or the error with "Try again" / "Back".
class _NfStatus extends StatelessWidget {
  const _NfStatus({this.loading = false, this.error, this.onRetry});
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: loading
              ? const CircularProgressIndicator(color: AppColors.menuButton)
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          size: 40, color: AppColors.menuButton),
                      const SizedBox(height: 12),
                      Text(
                        error ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14,
                          color: AppColors.menuButton,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                              onPressed: onRetry,
                              child: const Text('Try again')),
                          TextButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              child: const Text('Back')),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Original phone layout (unchanged).
class _NotificationsMobile extends StatelessWidget {
  const _NotificationsMobile({required this.notifications});

  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context) {
    final unread = notifications.where((n) => n.isUnread).toList();
    final earlier = notifications.where((n) => !n.isUnread).toList();
    final inset = MediaQuery.viewPaddingOf(context);
    final topPad = inset.top + 12; // small margin above the header
    final bottomPad = inset.bottom + 12; // small margin below the Back button

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _Header(
                topPad: topPad, onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: notifications.isEmpty
                  ? const _EmptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      children: [
                        if (unread.isNotEmpty)
                          _Section(title: 'Unread', items: unread),
                        if (unread.isNotEmpty && earlier.isNotEmpty)
                          const SizedBox(height: 24),
                        if (earlier.isNotEmpty)
                          _Section(title: 'Earlier', items: earlier),
                      ],
                    ),
            ),
            // Back Button: 160x56, radius 10, 50 from the bottom
            SizedBox(
              width: 160,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(height: 50 + bottomPad),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.topPad, required this.onBack});
  final double topPad;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 62 + topPad,
      padding: EdgeInsets.fromLTRB(24, 12 + topPad, 24, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            AppColors.instructorGradientStart, // #007EDE
            AppColors.profileGradientMid, // #0064B1
            AppColors.instructorGradientEnd, // #004478
          ],
          stops: [0.001, 0.51843, 0.99952],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            color: const Color(0x33FFFFFF), // white @ 20%
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onBack,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.chevron_left, size: 20, color: Colors.white),
              ),
            ),
          ),
          const Text(
            'Notifications',
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
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});
  final String title;
  final List<AppNotification> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.menuButton, // #0068B8
          ),
        ),
        for (final n in items) ...[
          const SizedBox(height: 16),
          _NotificationCard(item: n),
        ],
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});
  final AppNotification item;

  static const _blue = AppColors.menuButton; // #0068B8

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.isUnread ? 1 : 0.8,
      child: Material(
        color: AppColors.inputFill, // #D3E7FF
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _blue,
                        ),
                      ),
                    ),
                    if (item.isUnread)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: _blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: 0.8,
                  child: Text(
                    item.message,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: _blue,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: 0.6,
                  child: Text(
                    item.timeAgo,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _blue,
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

/// Shown while there are no notifications (not part of the Figma frame).
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none,
              size: 56, color: AppColors.menuButton),
          SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.menuButton,
            ),
          ),
          SizedBox(height: 8),
          Opacity(
            opacity: 0.8,
            child: Text(
              "You're all caught up.",
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.menuButton,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// =============================================================================
// DESKTOP WEB LAYOUT (kPortfolioWideBreakpoint and wider)
// =============================================================================
class _NotificationsWeb extends StatefulWidget {
  const _NotificationsWeb({required this.notifications});
  final List<AppNotification> notifications;

  @override
  State<_NotificationsWeb> createState() => _NotificationsWebState();
}

class _NotificationsWebState extends State<_NotificationsWeb> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    final all = widget.notifications;
    final unread = all.where((n) => n.isUnread).toList();
    final earlier =
        _unreadOnly ? <AppNotification>[] : all.where((n) => !n.isUnread).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _NfTopBar(onBack: back),
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
                              constraints: const BoxConstraints(maxWidth: 900),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _NfPageHeader(
                                      unreadCount: unread.length, onBack: back),
                                  const SizedBox(height: 20),
                                  Expanded(
                                    child: _NfListCard(
                                      total: all.length,
                                      unreadOnly: _unreadOnly,
                                      onFilter: (v) =>
                                          setState(() => _unreadOnly = v),
                                      unread: unread,
                                      earlier: earlier,
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

class _NfTopBar extends StatelessWidget {
  const _NfTopBar({required this.onBack});
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
                'Notifications',
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

class _NfPageHeader extends StatelessWidget {
  const _NfPageHeader({required this.unreadCount, required this.onBack});
  final int unreadCount;
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
              'Notifications',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              unreadCount == 0
                  ? "You're all caught up."
                  : 'You have $unreadCount unread '
                      '${unreadCount == 1 ? 'notification' : 'notifications'}.',
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

class _NfListCard extends StatelessWidget {
  const _NfListCard({
    required this.total,
    required this.unreadOnly,
    required this.onFilter,
    required this.unread,
    required this.earlier,
  });

  final int total;
  final bool unreadOnly;
  final ValueChanged<bool> onFilter;
  final List<AppNotification> unread;
  final List<AppNotification> earlier;

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.menuButton,
      backgroundColor: AppColors.inputFill.withValues(alpha: 0.5),
      side: BorderSide.none,
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppColors.menuText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = unread.isEmpty && earlier.isEmpty;
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
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _chip('All', !unreadOnly, () => onFilter(false)),
                const SizedBox(width: 8),
                _chip('Unread', unreadOnly, () => onFilter(true)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.menuDivider),
          Expanded(
            child: empty
                ? _NfEmpty(
                    title: total == 0
                        ? 'No notifications yet'
                        : 'No unread notifications',
                    message: "You're all caught up.",
                  )
                : Scrollbar(
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        if (unread.isNotEmpty)
                          _NfSection(title: 'Unread', items: unread),
                        if (unread.isNotEmpty && earlier.isNotEmpty)
                          const SizedBox(height: 24),
                        if (earlier.isNotEmpty)
                          _NfSection(title: 'Earlier', items: earlier),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NfSection extends StatelessWidget {
  const _NfSection({required this.title, required this.items});
  final String title;
  final List<AppNotification> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.menuButton,
          ),
        ),
        for (final n in items) ...[
          const SizedBox(height: 12),
          _NfCard(item: n),
        ],
      ],
    );
  }
}

class _NfCard extends StatefulWidget {
  const _NfCard({required this.item});
  final AppNotification item;

  @override
  State<_NfCard> createState() => _NfCardState();
}

class _NfCardState extends State<_NfCard> {
  bool _hover = false;
  static const _blue = AppColors.menuButton;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Opacity(
        opacity: item.isUnread ? 1 : 0.8,
        child: Material(
          color: _hover
              ? AppColors.inputFill
              : AppColors.inputFill.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: item.onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.isUnread
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none,
                      size: 24,
                      color: _blue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: 0.8,
                          child: Text(
                            item.message,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: _blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Opacity(
                        opacity: 0.6,
                        child: Text(
                          item.timeAgo,
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _blue,
                          ),
                        ),
                      ),
                      if (item.isUnread) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: _blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NfEmpty extends StatelessWidget {
  const _NfEmpty({required this.title, required this.message});
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
              child: const Icon(Icons.notifications_none,
                  size: 48, color: AppColors.menuButton),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Lexend',
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
                  fontFamily: 'Lexend',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
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
