import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/class_service.dart';
import '../theme/app_colors.dart';
import '../utils/slide_route.dart';
import '../widgets/primary_action_button.dart';
import 'instructor_class_detail_screen.dart';
import 'my_portfolio_screen.dart' show kPortfolioWideBreakpoint;

/// One student enrolled in a class section.
/// Fill the lists later from your backend (e.g. Supabase).
class ClassStudent {
  const ClassStudent(
      {required this.name, required this.studentId, this.memberId});

  final String name;
  final String studentId;

  /// Enrollment record id (used to remove the student); null when the row did
  /// not come from the backend.
  final String? memberId;
}

/// One class section (e.g. "CpE - 3A") and its students.
class ClassSection {
  const ClassSection({
    required this.name,
    required this.students,
    this.id,
    this.code = '',
    this.description = '',
    this.requests = const <ClassMember>[],
  });

  final String name;
  final List<ClassStudent> students;

  /// Students who asked to join with the class code and wait for approval.
  final List<ClassMember> requests;

  /// Backend id and unique class code (null / empty for sections that were
  /// not loaded from the backend).
  final String? id;
  final String code;
  final String description;

  /// Expand/collapse key (two classes may share a name).
  String get key => id ?? name;
}

// Colors read from the Figma frame (Tailwind gray scale).
const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _sectionBg = Color(0xFFF3F4F6);
const _rowBorder = Color(0xFFE5E7EB);
const _folderBlue = AppColors.menuButton; // #0068B8
const _mcDanger = Color(0xFFB42318);
const _mcAmber = Color(0xFFB54708);

const _sectionTitleStyle = TextStyle(
  fontFamily: 'Lexend',
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: _ink,
);
const _studentNameStyle = TextStyle(
  fontFamily: 'Lexend',
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: _ink,
);
const _studentIdStyle = TextStyle(
  fontFamily: 'Lexend',
  fontSize: 12,
  fontWeight: FontWeight.w400,
  color: _muted,
);

/// Figma frame: "4.1 My Classes Panel" (instructor).
///
/// Responsive (same breakpoint as My Portfolio): narrower than
/// [kPortfolioWideBreakpoint] shows the phone layout from the Figma frame,
/// wider shows the desktop web layout. Both share the same data and the same
/// expand/collapse state.
class MyClassesScreen extends StatefulWidget {
  const MyClassesScreen(
      {super.key, this.onStudentTap, this.openClassId, this.openTaskId});

  /// Opened from a notification: go straight to this class and, inside it,
  /// to the submissions of this task.
  final String? openClassId;
  final String? openTaskId;

  /// Called when a student row is tapped.
  final void Function(ClassSection section, ClassStudent student)? onStudentTap;

  @override
  State<MyClassesScreen> createState() => _MyClassesScreenState();
}

class _MyClassesScreenState extends State<MyClassesScreen> {
  final Set<String> _collapsed = <String>{};
  final TextEditingController _search = TextEditingController();

  List<ClassSection> _sections = const <ClassSection>[];
  List<InstructorClass> _loaded = const <InstructorClass>[];
  final Set<String> _busy = <String>{}; // enrollment ids being changed
  bool _loading = true;
  String? _error;
  bool _handledEntry = false; // the notification destination runs only once

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Loads the instructor's classes (with their enrolled students) from the
  /// Instructor project. [silent] keeps the current list on screen.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await InstructorClassApi.classes();
      if (!mounted) return;
      setState(() {
        _loaded = data;
        _sections = [
          for (final c in data)
            ClassSection(
              id: c.room.id,
              name: c.room.name,
              code: c.room.code,
              description: c.room.description,
              students: [
                for (final m in c.members)
                  ClassStudent(name: m.name, studentId: m.label, memberId: m.id),
              ],
              requests: c.requests,
            ),
        ];
        _loading = false;
        _error = null;
      });
      _handleEntry();
    } on ClassFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _sections.isEmpty) _error = e.message;
      });
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB42318) : _ink,
      ));
  }

  Future<void> _newClass() async {
    final created = await showDialog<ClassRoom>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NewClassDialog(),
    );
    if (created == null || !mounted) return;
    await _load(silent: true);
    if (!mounted) return;
    _toast('Class "${created.name}" created.');
  }

  /// Notification destination: the relevant class (then its task).
  void _handleEntry() {
    if (_handledEntry || widget.openClassId == null) return;
    _handledEntry = true;
    ClassSection? target;
    for (final s in _sections) {
      if (s.id == widget.openClassId) target = s;
    }
    if (target == null) {
      _toast('This class is not available anymore.', error: true);
      return;
    }
    final section = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _manage(section, openTaskId: widget.openTaskId);
    });
  }

  Future<void> _manage(ClassSection section, {String? openTaskId}) async {
    InstructorClass? match;
    for (final c in _loaded) {
      if (c.room.id == section.id) match = c;
    }
    if (match == null) return;
    await Navigator.of(context).push(
      SlideFromRightRoute(
          page: InstructorClassDetailScreen(
              room: match.room, openTaskId: openTaskId)),
    );
    if (mounted) _load(silent: true); // roster may have changed
  }

  /// Approve / reject a join request (only the class owner can; enforced by
  /// the database).
  Future<void> _decide(
      ClassSection section, ClassMember request, bool approve) async {
    if (_busy.contains(request.id)) return;
    setState(() => _busy.add(request.id));
    try {
      await InstructorClassApi.decideRequest(request.id, approve: approve);
      if (mounted) {
        _toast(approve
            ? '${request.name} was approved and added to ${section.name}.'
            : 'The request from ${request.name} was rejected.');
      }
    } on ClassFailure catch (e) {
      if (mounted) _toast(e.message, error: true);
    }
    await _load(silent: true);
    if (mounted) setState(() => _busy.remove(request.id));
  }

  /// Removes a student from the class after a confirmation. Access is revoked
  /// at once; the account, other classes and past submissions are untouched.
  Future<void> _remove(ClassSection section, ClassStudent student) async {
    final id = student.memberId;
    if (id == null || _busy.contains(id)) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove ${student.name}?',
            style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _ink)),
        content: Text(
          '${student.name} will immediately lose access to "${section.name}", '
          'its materials and assignments.\n\nTheir account, other classes and '
          'past submissions are not deleted.',
          style: _studentIdStyle.copyWith(fontSize: 14, color: _ink),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _mcDanger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await InstructorClassApi.removeStudent(id);
      if (mounted) _toast('${student.name} was removed from ${section.name}.');
    } on ClassFailure catch (e) {
      if (mounted) _toast(e.message, error: true);
    }
    await _load(silent: true);
    if (mounted) setState(() => _busy.remove(id));
  }

  void _toggle(String key) => setState(() {
        if (!_collapsed.remove(key)) _collapsed.add(key);
      });

  void _setAll({required bool collapse}) => setState(() {
        _collapsed.clear();
        if (collapse) _collapsed.addAll(_sections.map((s) => s.key));
      });

  @override
  Widget build(BuildContext context) {
    return _ClassActions(
      onDecide: _decide,
      onRemove: _remove,
      busy: {..._busy},
      child: LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kPortfolioWideBreakpoint
          ? _MyClassesWeb(
              sections: _sections,
              loading: _loading,
              error: _error,
              onRetry: _load,
              onNew: _newClass,
              onManage: _manage,
              collapsed: _collapsed,
              search: _search,
              onSearchChanged: () => setState(() {}),
              onToggle: _toggle,
              onSetAll: _setAll,
              onStudentTap: widget.onStudentTap,
            )
          : _MyClassesMobile(
              sections: _sections,
              loading: _loading,
              error: _error,
              onRetry: _load,
              onRefresh: () => _load(silent: true),
              onNew: _newClass,
              onManage: _manage,
              collapsed: _collapsed,
              onToggle: _toggle,
              onStudentTap: widget.onStudentTap,
            ),
    ),
    );
  }
}

// =============================================================================
// SHARED PIECES
// =============================================================================

/// Gives the section blocks (phone and desktop layouts alike) the actions
/// "approve / reject request" and "remove student" without passing them
/// through every layout widget.
class _ClassActions extends InheritedWidget {
  const _ClassActions({
    required this.onDecide,
    required this.onRemove,
    required this.busy,
    required super.child,
  });

  final Future<void> Function(ClassSection, ClassMember, bool approve) onDecide;
  final Future<void> Function(ClassSection, ClassStudent) onRemove;
  final Set<String> busy;

  static _ClassActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ClassActions>();

  @override
  bool updateShouldNotify(_ClassActions old) => !setEquals(busy, old.busy);
}

/// Gray section bar (folder + name + chevron) followed by its student rows.
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.section,
    required this.collapsed,
    required this.onToggle,
    required this.onStudentTap,
    this.onManage,
    this.multiColumn = false,
  });

  final ClassSection section;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onManage;
  final void Function(ClassSection, ClassStudent)? onStudentTap;
  final bool multiColumn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _sectionBg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined,
                      size: 20, color: _folderBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sectionTitleStyle,
                    ),
                  ),
                  if (section.code.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(section.code,
                        style: _studentIdStyle.copyWith(
                            fontWeight: FontWeight.w600, letterSpacing: 1)),
                  ],
                  if (onManage != null)
                    Tooltip(
                      message: 'Manage class',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: onManage,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.tune_rounded,
                              size: 20, color: _folderBlue),
                        ),
                      ),
                    ),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        size: 20, color: _muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity, height: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (section.requests.isNotEmpty)
                        _RequestRows(
                            section: section, multiColumn: multiColumn),
                      _StudentRows(
                        section: section,
                        multiColumn: multiColumn,
                        onTap: onStudentTap,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Phone: single column, 4 px gap (Figma). Desktop: responsive grid.
class _StudentRows extends StatelessWidget {
  const _StudentRows({
    required this.section,
    required this.multiColumn,
    required this.onTap,
  });

  final ClassSection section;
  final bool multiColumn;
  final void Function(ClassSection, ClassStudent)? onTap;

  @override
  Widget build(BuildContext context) {
    final students = section.students;
    if (students.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text('No students have joined yet.', style: _studentIdStyle),
      );
    }
    final actions = _ClassActions.maybeOf(context);
    Widget row(ClassStudent s) {
      final id = s.memberId;
      return _StudentRow(
        student: s,
        onTap: onTap == null ? null : () => onTap!(section, s),
        onRemove: (actions == null || id == null)
            ? null
            : () => actions.onRemove(section, s),
        removing: id != null && (actions?.busy.contains(id) ?? false),
      );
    }

    if (!multiColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < students.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            row(students[i]),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final cols = c.maxWidth >= 860 ? 3 : (c.maxWidth >= 520 ? 2 : 1);
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in students) SizedBox(width: w, child: row(s)),
          ],
        );
      },
    );
  }
}

/// White bordered row: name + student number, chevron on the right.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.onTap,
    this.onRemove,
    this.removing = false,
  });

  final ClassStudent student;
  final VoidCallback? onTap;

  /// "Remove student" (kick out); null hides the button.
  final VoidCallback? onRemove;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _rowBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: _sectionBg,
        onTap: onTap ?? () {},
        child: Padding(
          padding: onRemove == null && !removing
              ? const EdgeInsets.all(12)
              : const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      student.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _studentNameStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      student.studentId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _studentIdStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (removing)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (onRemove != null)
                IconButton(
                  tooltip: 'Remove student',
                  onPressed: onRemove,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.person_remove_alt_1_outlined,
                      size: 20, color: _mcDanger),
                ),
              const Icon(Icons.chevron_right, size: 16, color: _muted),
              if (onRemove != null || removing) const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Join requests of one class: Approve / Reject.
class _RequestRows extends StatelessWidget {
  const _RequestRows({required this.section, required this.multiColumn});

  final ClassSection section;
  final bool multiColumn;

  @override
  Widget build(BuildContext context) {
    final actions = _ClassActions.maybeOf(context);
    if (actions == null) return const SizedBox.shrink();

    Widget row(ClassMember r) {
      final busy = actions.busy.contains(r.id);
      return Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _rowBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _studentNameStyle),
              const SizedBox(height: 2),
              Text(r.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _studentIdStyle),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => actions.onDecide(section, r, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(0, 40)),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => actions.onDecide(section, r, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _mcDanger,
                        minimumSize: const Size(0, 40)),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final reqs = section.requests;
    final Widget list;
    if (!multiColumn) {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < reqs.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            row(reqs[i]),
          ],
        ],
      );
    } else {
      list = LayoutBuilder(
        builder: (context, c) {
          const gap = 8.0;
          final cols = c.maxWidth >= 860 ? 3 : (c.maxWidth >= 520 ? 2 : 1);
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final r in reqs) SizedBox(width: w, child: row(r))],
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text('Pending requests (${reqs.length})',
                style: _studentIdStyle.copyWith(
                    fontWeight: FontWeight.w700, color: _mcAmber)),
          ),
          list,
        ],
      ),
    );
  }
}

class _McEmpty extends StatelessWidget {
  const _McEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: _muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: _studentIdStyle.copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PHONE LAYOUT (Figma frame, narrower than kPortfolioWideBreakpoint)
// =============================================================================
class _MyClassesMobile extends StatelessWidget {
  const _MyClassesMobile({
    required this.sections,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onRefresh,
    required this.onNew,
    required this.onManage,
    required this.collapsed,
    required this.onToggle,
    required this.onStudentTap,
  });

  final List<ClassSection> sections;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final VoidCallback onNew;
  final void Function(ClassSection) onManage;
  final Set<String> collapsed;
  final void Function(String) onToggle;
  final void Function(ClassSection, ClassStudent)? onStudentTap;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);

    Widget body;
    if (loading) {
      body = const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    } else if (error != null && sections.isEmpty) {
      body = _McError(message: error!, onRetry: onRetry);
    } else if (sections.isEmpty) {
      body = const _McEmpty(
        icon: Icons.people_outline,
        title: 'No classes yet',
        message: 'Tap + to create your first class.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _SectionBlock(
                section: sections[i],
                collapsed: collapsed.contains(sections[i].key),
                onToggle: () => onToggle(sections[i].key),
                onManage: () => onManage(sections[i]),
                onStudentTap: onStudentTap,
              ),
            ],
          ],
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _McHeader(
              topPad: inset.top,
              onBack: () => Navigator.of(context).maybePop(),
              onAdd: onNew,
            ),
            // Only the roster scrolls (Figma: roster-content).
            Expanded(child: body),
            // Home button: 104x48, 36 from the left (Figma).
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
}

class _McError extends StatelessWidget {
  const _McError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: _muted),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: _studentIdStyle.copyWith(fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Figma: header (62 high, gradient 270deg #007EDE -> #0064B1 -> #004478),
/// 40 px back button at 20% white, Lexend SemiBold 18 title, 40 px spacer.
class _McHeader extends StatelessWidget {
  const _McHeader({
    required this.topPad,
    required this.onBack,
    required this.onAdd,
  });

  final double topPad;
  final VoidCallback onBack;
  final VoidCallback onAdd;

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
            'My Classes',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Tooltip(
            message: 'New class',
            child: Material(
              color: const Color(0x33FFFFFF), // white @ 20%
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onAdd,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.add, size: 20, color: Colors.white),
                ),
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
class _MyClassesWeb extends StatelessWidget {
  const _MyClassesWeb({
    required this.sections,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onNew,
    required this.onManage,
    required this.collapsed,
    required this.search,
    required this.onSearchChanged,
    required this.onToggle,
    required this.onSetAll,
    required this.onStudentTap,
  });

  final List<ClassSection> sections;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onNew;
  final void Function(ClassSection) onManage;
  final Set<String> collapsed;
  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final void Function(String) onToggle;
  final void Function({required bool collapse}) onSetAll;
  final void Function(ClassSection, ClassStudent)? onStudentTap;

  List<ClassSection> _visible() {
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return sections;
    final result = <ClassSection>[];
    for (final s in sections) {
      final sectionMatches = s.name.toLowerCase().contains(q) ||
          s.code.toLowerCase() == q;
      final students = sectionMatches
          ? s.students
          : s.students
              .where((st) =>
                  st.name.toLowerCase().contains(q) ||
                  st.studentId.toLowerCase().contains(q))
              .toList();
      if (students.isNotEmpty) {
        result.add(ClassSection(
          id: s.id,
          code: s.code,
          description: s.description,
          name: s.name,
          students: students,
        ));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    final shown = _visible();
    final studentCount =
        sections.fold<int>(0, (sum, s) => sum + s.students.length);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _McTopBar(onBack: back),
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
                                  const BoxConstraints(maxWidth: 1200),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _McPageHeader(
                                    sectionCount: sections.length,
                                    studentCount: studentCount,
                                    onHome: back,
                                    onNew: onNew,
                                  ),
                                  const SizedBox(height: 20),
                                  Expanded(
                                    child: _McCard(
                                      search: search,
                                      onSearchChanged: onSearchChanged,
                                      allCollapsed: sections.isNotEmpty &&
                                          collapsed.length == sections.length,
                                      onToggleAll: () => onSetAll(
                                        collapse: !(collapsed.length ==
                                            sections.length),
                                      ),
                                      totalCount: sections.length,
                                      loading: loading,
                                      error: error,
                                      onRetry: onRetry,
                                      onManage: onManage,
                                      searching:
                                          search.text.trim().isNotEmpty,
                                      shown: shown,
                                      collapsed: collapsed,
                                      onToggle: onToggle,
                                      onStudentTap: onStudentTap,
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

class _McTopBar extends StatelessWidget {
  const _McTopBar({required this.onBack});
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
                'My Classes',
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

class _McPageHeader extends StatelessWidget {
  const _McPageHeader({
    required this.sectionCount,
    required this.studentCount,
    required this.onHome,
    required this.onNew,
  });

  final int sectionCount;
  final int studentCount;
  final VoidCallback onHome;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final summary = '$sectionCount ${sectionCount == 1 ? 'section' : 'sections'}'
        ' · $studentCount ${studentCount == 1 ? 'student' : 'students'}';
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
              'My Classes',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your class sections and the students enrolled in them.',
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
                  const Icon(Icons.people_outline,
                      size: 22, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    summary,
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
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onNew,
                child: const SizedBox(
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 22, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'New class',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

class _McCard extends StatelessWidget {
  const _McCard({
    required this.search,
    required this.onSearchChanged,
    required this.allCollapsed,
    required this.onToggleAll,
    required this.totalCount,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onManage,
    required this.searching,
    required this.shown,
    required this.collapsed,
    required this.onToggle,
    required this.onStudentTap,
  });

  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final bool allCollapsed;
  final VoidCallback onToggleAll;
  final int totalCount;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final void Function(ClassSection) onManage;
  final bool searching;
  final List<ClassSection> shown;
  final Set<String> collapsed;
  final void Function(String) onToggle;
  final void Function(ClassSection, ClassStudent)? onStudentTap;

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
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Class sections',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 12,
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
                            color: _ink),
                        decoration: InputDecoration(
                          hintText: 'Search students or class code',
                          hintStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: _muted),
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 20, color: _muted),
                          filled: true,
                          fillColor:
                              AppColors.inputFill.withValues(alpha: 0.5),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: allCollapsed
                          ? 'Expand all sections'
                          : 'Collapse all sections',
                      child: TextButton.icon(
                        onPressed: totalCount == 0 ? null : onToggleAll,
                        icon: Icon(
                            allCollapsed
                                ? Icons.unfold_more_rounded
                                : Icons.unfold_less_rounded,
                            size: 18,
                            color: _folderBlue),
                        label: Text(
                          allCollapsed ? 'Expand all' : 'Collapse all',
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _folderBlue),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.menuDivider),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                : (error != null && totalCount == 0)
                ? _McError(message: error!, onRetry: onRetry)
                : totalCount == 0
                ? const _McEmpty(
                    icon: Icons.people_outline,
                    title: 'No classes yet',
                    message: 'Use New class to create your first class.',
                  )
                : shown.isEmpty
                    ? const _McEmpty(
                        icon: Icons.search_off_rounded,
                        title: 'No matching students',
                        message: 'Try a different name or student number.',
                      )
                    : Scrollbar(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 16),
                          itemBuilder: (_, i) => _SectionBlock(
                            section: shown[i],
                            // While searching, matching sections stay open.
                            collapsed: !searching &&
                                collapsed.contains(shown[i].key),
                            onToggle: () => onToggle(shown[i].key),
                            onManage: () => onManage(shown[i]),
                            onStudentTap: onStudentTap,
                            multiColumn: true,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// NEW CLASS DIALOG: creates the class in the Instructor project; the unique
// class code is generated by the database and shown right after.
// =============================================================================
class _NewClassDialog extends StatefulWidget {
  const _NewClassDialog();

  @override
  State<_NewClassDialog> createState() => _NewClassDialogState();
}

class _NewClassDialogState extends State<_NewClassDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;
  ClassRoom? _created;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a class name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final room =
          await InstructorClassApi.createClass(_name.text, _description.text);
      if (!mounted) return;
      setState(() {
        _created = room;
        _saving = false;
      });
    } on ClassFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: _muted),
        filled: true,
        fillColor: AppColors.inputFill.withValues(alpha: 0.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        created == null ? 'New class' : 'Class created',
        style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _ink),
      ),
      content: SizedBox(
        width: 400,
        child: created == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Class name (e.g. CpE - 3A)')
                        .copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 4,
                    decoration: _decoration('Description (optional)')
                        .copyWith(counterText: ''),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Color(0xFFB42318))),
                  ],
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(created.name, style: _studentNameStyle),
                  const SizedBox(height: 12),
                  const Text('Students can join with this class code:',
                      style: _studentIdStyle),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            created.code,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4,
                              color: AppColors.menuButton,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy code',
                          icon: const Icon(Icons.copy_rounded,
                              size: 20, color: _folderBlue),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: created.code));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Class code copied.')));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (created == null) ...[
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _create,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(created),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Done'),
          ),
      ],
    );
  }
}
