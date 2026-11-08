import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/class_service.dart';
import '../theme/app_colors.dart';
import '../utils/slide_route.dart';
import '../widgets/primary_action_button.dart';
import 'my_portfolio_screen.dart' show kPortfolioWideBreakpoint;
import 'student_class_detail_screen.dart';

const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _sectionBg = Color(0xFFF3F4F6);
const _rowBorder = Color(0xFFE5E7EB);
const _danger = Color(0xFFB42318);
const _amber = Color(0xFFB54708);

const _sectionTitle = TextStyle(
    fontFamily: 'Lexend', fontSize: 16, fontWeight: FontWeight.w700, color: _ink);
const _itemTitle = TextStyle(
    fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.w600, color: _ink);
const _caption = TextStyle(
    fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w400, color: _muted);

/// Student "My Classes": join with a class code, answer invitations and open
/// the joined classes. All data comes from the Instructor project through
/// [StudentClassApi]; nothing class-related is stored in the Student project.
///
/// Opened from a notification it can go straight to a class ([openClassId])
/// or to the invitations ([focusInvitations]).
class StudentClassesScreen extends StatefulWidget {
  const StudentClassesScreen(
      {super.key, this.openClassId, this.focusInvitations = false});

  final String? openClassId;
  final bool focusInvitations;

  @override
  State<StudentClassesScreen> createState() => _StudentClassesScreenState();
}

class _StudentClassesScreenState extends State<StudentClassesScreen> {
  final _code = TextEditingController();
  List<ClassRoom> _rooms = const [];
  List<ReceivedInvitation> _invites = const [];
  bool _loading = true;
  bool _joining = false;
  String? _error;
  final Set<String> _answering = <String>{};
  final _invitesKey = GlobalKey();
  bool _handledEntry = false; // the notification destination runs only once

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await Future.wait([
        StudentClassApi.classes(),
        StudentClassApi.invitations(),
      ]);
      if (!mounted) return;
      setState(() {
        _rooms = r[0] as List<ClassRoom>;
        _invites = r[1] as List<ReceivedInvitation>;
        _loading = false;
        _error = null;
      });
      _handleEntry();
    } on ClassFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _rooms.isEmpty) _error = e.message;
      });
    }
  }

  /// Notification destinations: the actual class, or the invitations.
  void _handleEntry() {
    if (_handledEntry) return;
    _handledEntry = true;
    final classId = widget.openClassId;
    if (classId != null) {
      ClassRoom? room;
      for (final r in _joined) {
        if (r.id == classId) room = r;
      }
      if (room != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _open(room!);
        });
      } else {
        _toast('This class is not available to you anymore.', error: true);
      }
    } else if (widget.focusInvitations) {
      if (_invites.isEmpty) {
        _toast('There are no pending invitations.');
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _invitesKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 300), alignment: 0.05);
          }
        });
      }
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? _danger : _ink,
      ));
  }

  /// Classes the student can open (approved) / requests still waiting or
  /// declined. Only approved students have access to a class.
  List<ClassRoom> get _joined => [for (final r in _rooms) if (r.isApproved) r];
  List<ClassRoom> get _requests =>
      [for (final r in _rooms) if (!r.isApproved) r];

  Future<void> _join() async {
    if (_joining) return;
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      _toast('Enter the 6-character class code.', error: true);
      return;
    }
    setState(() => _joining = true);
    try {
      final room = await StudentClassApi.joinByCode(code);
      _code.clear();
      if (mounted) {
        _toast('Request sent to ${room.name}. You will get access once the '
            'instructor approves it.');
      }
      await _load(silent: true);
    } on ClassFailure catch (e) {
      if (mounted) _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _answer(ReceivedInvitation inv, {required bool accept}) async {
    if (_answering.contains(inv.id)) return;
    setState(() => _answering.add(inv.id));
    try {
      await StudentClassApi.respond(inv.id, accept: accept);
      if (mounted) {
        _toast(accept
            ? 'You joined ${inv.room.name}.'
            : 'Invitation declined.');
      }
    } on ClassFailure catch (e) {
      if (mounted) _toast(e.message, error: true);
    }
    if (mounted) setState(() => _answering.remove(inv.id));
    await _load(silent: true);
  }

  Future<void> _open(ClassRoom room) async {
    await Navigator.of(context).push(
      SlideFromRightRoute(page: StudentClassDetailScreen(room: room)),
    );
    if (mounted) _load(silent: true); // submission counts may have changed
  }

  Widget _content() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null && _rooms.isEmpty && _invites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: _muted),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: _caption.copyWith(fontSize: 13)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          const Text('Join a class', style: _sectionTitle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  ],
                  onSubmitted: (_) => _join(),
                  style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: _ink),
                  decoration: InputDecoration(
                    hintText: 'Class code',
                    hintStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        letterSpacing: 0,
                        color: _muted),
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.inputFill.withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _joining ? null : _join,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _joining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Join'),
                ),
              ),
            ],
          ),
          if (_invites.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Invitations', key: _invitesKey, style: _sectionTitle),
            const SizedBox(height: 8),
            for (final inv in _invites)
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.room.name, style: _itemTitle),
                    const SizedBox(height: 2),
                    Text(
                        inv.room.instructorName.isEmpty
                            ? 'Invited to join this class'
                            : 'Invited by ${inv.room.instructorName}',
                        style: _caption),
                    if (inv.room.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(inv.room.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _caption.copyWith(fontSize: 13)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _answering.contains(inv.id)
                              ? null
                              : () => _answer(inv, accept: true),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary),
                          child: const Text('Accept'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _answering.contains(inv.id)
                              ? null
                              : () => _answer(inv, accept: false),
                          child: const Text('Decline'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          if (_requests.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Join requests', style: _sectionTitle),
            const SizedBox(height: 8),
            for (final r in _requests)
              _Card(
                child: Row(
                  children: [
                    Icon(
                        r.enrollmentStatus == 'rejected'
                            ? Icons.cancel_outlined
                            : Icons.schedule_rounded,
                        size: 22,
                        color: r.enrollmentStatus == 'rejected'
                            ? _danger
                            : _amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _itemTitle),
                          const SizedBox(height: 2),
                          Text(
                              r.enrollmentStatus == 'rejected'
                                  ? 'The instructor declined this request. '
                                      'You can request again with the class code.'
                                  : 'Waiting for the instructor to approve '
                                      'your request.',
                              style: _caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(
                      r.enrollmentStatus == 'rejected' ? 'Rejected' : 'Pending',
                      r.enrollmentStatus == 'rejected' ? _danger : _amber,
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 24),
          const Text('Joined classes', style: _sectionTitle),
          const SizedBox(height: 8),
          if (_joined.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Icon(Icons.people_outline, size: 40, color: _muted),
                  const SizedBox(height: 12),
                  const Text('No classes yet',
                      style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _ink)),
                  const SizedBox(height: 4),
                  Text('Enter a class code or accept an invitation.\nYou can open a class once the instructor approves you.',
                      textAlign: TextAlign.center,
                      style: _caption.copyWith(fontSize: 13)),
                ],
              ),
            )
          else
            for (final room in _joined)
              _Card(
                onTap: () => _open(room),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined,
                        size: 22, color: AppColors.menuButton),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(room.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _itemTitle),
                          const SizedBox(height: 2),
                          Text(
                              room.instructorName.isEmpty
                                  ? 'Instructor'
                                  : room.instructorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _caption),
                          const SizedBox(height: 2),
                          Text(
                              '${room.taskCount} ${room.taskCount == 1 ? 'task' : 'tasks'}'
                              ' · ${room.submittedCount} submitted',
                              style: _caption),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kPortfolioWideBreakpoint
          ? _wide(context)
          : _mobile(context),
    );
  }

  // Phone: same page structure as the instructor My Classes (Figma).
  Widget _mobile(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Container(
              width: double.infinity,
              height: 62 + inset.top,
              padding: EdgeInsets.fromLTRB(24, 12 + inset.top, 24, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    AppColors.instructorGradientStart,
                    AppColors.profileGradientMid,
                    AppColors.instructorGradientEnd,
                  ],
                  stops: [0.001, 0.51843, 0.99952],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.chevron_left,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                  const Text('My Classes',
                      style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(child: _content()),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(36, 16, 0, 64 + inset.bottom),
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

  // Desktop: white top bar + blue dashboard with one white card.
  Widget _wide(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppColors.menuDivider)),
              ),
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  children: [
                    Tooltip(
                      message: 'Back',
                      child: Material(
                        color: AppColors.menuButton,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: back,
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.chevron_left_rounded,
                                size: 29, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    if (c.maxWidth >= 1000) ...[
                      const SizedBox(width: 16),
                      SvgPicture.asset('assets/images/logo.svg',
                          width: 34, height: 34),
                      const SizedBox(width: 12),
                      const Text('Student Portfolio System',
                          maxLines: 1,
                          style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brandText)),
                    ],
                    const SizedBox(width: 24),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: back,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('Home',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.menuMuted)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.menuMuted),
                    ),
                    const Text('My Classes',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.menuText)),
                  ],
                ),
              ),
            ),
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
                    return Padding(
                      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 24),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('My Classes',
                                  style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 40,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                              const SizedBox(height: 6),
                              Text(
                                'Join classes, answer invitations and submit your tasks.',
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.85)),
                              ),
                              const SizedBox(height: 20),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Color(0x26000000),
                                          blurRadius: 24,
                                          offset: Offset(0, 8)),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _content(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _rowBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: _sectionBg,
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(12), child: child),
          ),
        ),
      );
}
