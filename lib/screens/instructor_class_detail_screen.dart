import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/class_service.dart';
import '../theme/app_colors.dart';

const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _rowBorder = Color(0xFFE5E7EB);
const _panel = Color(0xFFF3F4F6);
const _danger = Color(0xFFB42318);

const _titleStyle = TextStyle(
    fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.w600, color: _ink);
const _captionStyle = TextStyle(
    fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w400, color: _muted);

String _dateText(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '${m[d.month - 1]} ${d.day}, ${d.year} $h:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
}

void _toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? _danger : _ink,
    ));
}

/// Same header as the other phone pages (gradient, back button, title); on
/// wide windows the content below is centered in a readable column.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return Container(
      width: double.infinity,
      height: 62 + top,
      padding: EdgeInsets.fromLTRB(24, 12 + top, 24, 12),
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
        children: [
          Material(
            color: const Color(0x33FFFFFF),
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 36, color: _muted),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: _captionStyle.copyWith(fontSize: 13)),
          ],
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message, this.onRetry);
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 36, color: _muted),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: _captionStyle.copyWith(fontSize: 13)),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.child, this.onTap});
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
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(12), child: child),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
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

InputDecoration _field(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: _muted),
      filled: true,
      fillColor: AppColors.inputFill.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

// =============================================================================
// CLASS DETAIL: code, students, invitations, tasks
// =============================================================================
class InstructorClassDetailScreen extends StatefulWidget {
  const InstructorClassDetailScreen(
      {super.key, required this.room, this.openTaskId});
  final ClassRoom room;

  /// Opened from a notification: show the Tasks tab and open the submissions
  /// of this task right away.
  final String? openTaskId;

  @override
  State<InstructorClassDetailScreen> createState() =>
      _InstructorClassDetailScreenState();
}

class _InstructorClassDetailScreenState
    extends State<InstructorClassDetailScreen> {
  List<ClassMember>? _members;
  List<SentInvitation>? _invites;
  List<ClassTask>? _tasks;
  String? _error;
  final _email = TextEditingController();
  bool _inviting = false;
  bool _openedTask = false; // the notification task opens only once

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Notification destination: the task's submissions (files, review).
  void _openRequestedTask() {
    final id = widget.openTaskId;
    if (id == null || _openedTask) return;
    _openedTask = true;
    ClassTask? task;
    for (final t in _tasks ?? const <ClassTask>[]) {
      if (t.id == id) task = t;
    }
    if (task == null) {
      _toast(context, 'This task is not available anymore.', error: true);
      return;
    }
    final found = task;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              InstructorTaskScreen(task: found, className: widget.room.name),
        ),
      );
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final id = widget.room.id;
      final r = await Future.wait([
        InstructorClassApi.members(id),
        InstructorClassApi.invitations(id),
        InstructorClassApi.tasks(id),
      ]);
      if (!mounted) return;
      setState(() {
        _members = r[0] as List<ClassMember>;
        _invites = r[1] as List<SentInvitation>;
        _tasks = r[2] as List<ClassTask>;
      });
      _openRequestedTask();
    } on ClassFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _invite() async {
    if (_inviting) return;
    setState(() => _inviting = true);
    try {
      await InstructorClassApi.invite(widget.room.id, _email.text);
      _email.clear();
      if (mounted) _toast(context, 'Invitation sent.');
      await _load();
    } on ClassFailure catch (e) {
      if (mounted) _toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _newTask() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewTaskDialog(classId: widget.room.id),
    );
    if (ok == true && mounted) {
      _toast(context, 'Task published.');
      _load();
    }
  }

  Color _statusColor(String s) => switch (s) {
        'accepted' => const Color(0xFF027A48),
        'declined' => _danger,
        'expired' => _muted,
        _ => const Color(0xFFB54708),
      };

  Widget _list(Widget Function() build, bool loaded) {
    if (_error != null && !loaded) return _ErrorBox(_error!, _load);
    if (!loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    return build();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.openTaskId != null ? 2 : 0, // Tasks tab
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _Header(title: room.name, onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: _CodeCard(room: room),
                      ),
                      const TabBar(
                        labelColor: AppColors.menuButton,
                        unselectedLabelColor: _muted,
                        indicatorColor: AppColors.menuButton,
                        labelStyle: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                        tabs: [
                          Tab(text: 'Students'),
                          Tab(text: 'Invitations'),
                          Tab(text: 'Tasks'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // ---- Students
                            RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.all(24),
                                children: [
                                  _list(() {
                                    final m = _members!;
                                    if (m.isEmpty) {
                                      return const _Empty(Icons.people_outline,
                                          'No students have joined yet.\nShare the class code or send an invitation.');
                                    }
                                    return Column(children: [
                                      for (final s in m)
                                        _Row(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(s.name, style: _titleStyle),
                                              const SizedBox(height: 2),
                                              Text(
                                                  s.number.isEmpty
                                                      ? s.email
                                                      : '${s.number} · ${s.email}',
                                                  style: _captionStyle),
                                            ],
                                          ),
                                        ),
                                    ]);
                                  }, _members != null),
                                ],
                              ),
                            ),
                            // ---- Invitations
                            RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.all(24),
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _email,
                                          keyboardType: TextInputType.emailAddress,
                                          onSubmitted: (_) => _invite(),
                                          decoration: _field('Student email address'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        height: 48,
                                        child: FilledButton(
                                          onPressed: _inviting ? null : _invite,
                                          style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.primary,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12))),
                                          child: _inviting
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white))
                                              : const Text('Invite'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _list(() {
                                    final inv = _invites!;
                                    if (inv.isEmpty) {
                                      return const _Empty(Icons.mail_outline,
                                          'No invitations sent yet.');
                                    }
                                    return Column(children: [
                                      for (final i in inv)
                                        _Row(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(i.email,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: _titleStyle),
                                                    const SizedBox(height: 2),
                                                    Text(_dateText(i.createdAt),
                                                        style: _captionStyle),
                                                  ],
                                                ),
                                              ),
                                              _Chip(
                                                  '${i.status[0].toUpperCase()}${i.status.substring(1)}',
                                                  _statusColor(i.status)),
                                            ],
                                          ),
                                        ),
                                    ]);
                                  }, _invites != null),
                                ],
                              ),
                            ),
                            // ---- Tasks
                            RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.all(24),
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      onPressed: _newTask,
                                      style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          minimumSize: const Size(0, 48),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                      icon: const Icon(Icons.add, size: 20),
                                      label: const Text('New task'),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _list(() {
                                    final t = _tasks!;
                                    if (t.isEmpty) {
                                      return const _Empty(Icons.assignment_outlined,
                                          'No tasks yet. Create one for your students.');
                                    }
                                    final total = _members?.length ?? 0;
                                    return Column(children: [
                                      for (final task in t)
                                        _Row(
                                          onTap: () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => InstructorTaskScreen(
                                                    task: task, className: room.name),
                                              ),
                                            );
                                            if (mounted) _load();
                                          },
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(task.title,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: _titleStyle),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                        task.deadline == null
                                                            ? 'No deadline'
                                                            : 'Due ${_dateText(task.deadline)}',
                                                        style: _captionStyle),
                                                  ],
                                                ),
                                              ),
                                              _Chip(
                                                  '${task.submissionCount}/$total submitted',
                                                  AppColors.menuButton),
                                              const Icon(Icons.chevron_right,
                                                  size: 16, color: _muted),
                                            ],
                                          ),
                                        ),
                                    ]);
                                  }, _tasks != null),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.room});
  final ClassRoom room;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (room.description.isNotEmpty) ...[
                    Text(room.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: _captionStyle.copyWith(fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                  const Text('Class code', style: _captionStyle),
                  SelectableText(
                    room.code,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: AppColors.menuButton,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_rounded, color: AppColors.menuButton),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: room.code));
                _toast(context, 'Class code copied.');
              },
            ),
          ],
        ),
      );
}

// =============================================================================
// NEW TASK DIALOG
// =============================================================================
class _NewTaskDialog extends StatefulWidget {
  const _NewTaskDialog({required this.classId});
  final String classId;

  @override
  State<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<_NewTaskDialog> {
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  final _requirements = TextEditingController();
  DateTime? _deadline;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _requirements.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;
    setState(() => _deadline =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a task title.');
      return;
    }
    if (_deadline != null && _deadline!.isBefore(DateTime.now())) {
      setState(() => _error = 'The deadline must be in the future.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await InstructorClassApi.createTask(
        classId: widget.classId,
        title: _title.text,
        instructions: _instructions.text,
        requirements: _requirements.text,
        deadline: _deadline,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ClassFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('New task',
          style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _ink)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                maxLength: 120,
                decoration: _field('Title').copyWith(counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructions,
                minLines: 3,
                maxLines: 5,
                decoration: _field('Instructions'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _requirements,
                minLines: 2,
                maxLines: 4,
                decoration:
                    _field('Submission requirements (e.g. one PDF, max 10 pages)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDeadline,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(_deadline == null
                          ? 'Set deadline (optional)'
                          : _dateText(_deadline)),
                    ),
                  ),
                  if (_deadline != null)
                    IconButton(
                      tooltip: 'Remove deadline',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _deadline = null),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 12, color: _danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Publish'),
        ),
      ],
    );
  }
}

// =============================================================================
// TASK: submitted files, open + review
// =============================================================================
class InstructorTaskScreen extends StatefulWidget {
  const InstructorTaskScreen(
      {super.key, required this.task, required this.className});
  final ClassTask task;
  final String className;

  @override
  State<InstructorTaskScreen> createState() => _InstructorTaskScreenState();
}

class _InstructorTaskScreenState extends State<InstructorTaskScreen> {
  List<TaskSubmission>? _subs;
  String? _error;
  final Set<String> _opening = <String>{}; // file ids being opened

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await InstructorClassApi.submissions(widget.task.id);
      if (mounted) setState(() => _subs = s);
    } on ClassFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// View / download one submitted file through a temporary signed link.
  /// The system browser / viewer is used on phones as well as on desktop web.
  Future<void> _openFile(SubmissionFile f, {required bool download}) async {
    final path = f.storagePath;
    if (path == null || _opening.contains(f.id)) return;
    setState(() => _opening.add(f.id));
    try {
      final url = await InstructorClassApi.fileUrl(
        path,
        downloadAs: download ? f.fileName : null,
      );
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        // a download keeps the app page; a preview opens in a new tab
        webOnlyWindowName: download ? '_self' : '_blank',
      );
      if (!ok && mounted) {
        _toast(context, 'Could not open the file.', error: true);
      }
    } on ClassFailure catch (e) {
      if (mounted) _toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) _toast(context, 'Could not open the file.', error: true);
    } finally {
      if (mounted) setState(() => _opening.remove(f.id));
    }
  }

  Future<void> _review(TaskSubmission s) async {
    final controller = TextEditingController(text: s.feedback ?? '');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Review ${s.studentName}',
            style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _ink)),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            decoration: _field('Feedback (optional)'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Mark as reviewed'),
          ),
        ],
      ),
    );
    final feedback = controller.text;
    controller.dispose();
    if (go != true) return;
    try {
      await InstructorClassApi.markReviewed(s.id!, feedback);
      if (mounted) _toast(context, 'Marked as reviewed.');
      await _load();
    } on ClassFailure catch (e) {
      if (mounted) _toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final subs = _subs;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(title: task.title, onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.className, style: _captionStyle),
                            if (task.instructions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(task.instructions,
                                  style: _captionStyle.copyWith(
                                      fontSize: 13, color: _ink)),
                            ],
                            if (task.requirements.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Requirements: ${task.requirements}',
                                  style: _captionStyle.copyWith(fontSize: 13)),
                            ],
                            const SizedBox(height: 8),
                            Text(
                                task.deadline == null
                                    ? 'No deadline'
                                    : 'Due ${_dateText(task.deadline)}',
                                style: _captionStyle.copyWith(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_error != null && subs == null)
                        _ErrorBox(_error!, _load)
                      else if (subs == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary)),
                        )
                      else if (subs.isEmpty)
                        const _Empty(Icons.inbox_outlined,
                            'No submissions yet.')
                      else
                        for (final s in subs)
                          _Row(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                        child: Text(
                                            s.studentName.isEmpty
                                                ? s.studentEmail
                                                : s.studentName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: _titleStyle)),
                                    _Chip(
                                      s.reviewed ? 'Reviewed' : 'Submitted',
                                      s.reviewed
                                          ? const Color(0xFF027A48)
                                          : AppColors.menuButton,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                    '${s.files.length} '
                                    '${s.files.length == 1 ? 'file' : 'files'}'
                                    ' · Submitted ${_dateText(s.submittedAt)}',
                                    style: _captionStyle),
                                const SizedBox(height: 8),
                                if (s.files.isEmpty)
                                  Text('No files.', style: _captionStyle)
                                else
                                  for (final f in s.files)
                                    _SubmittedFile(
                                      file: f,
                                      busy: _opening.contains(f.id),
                                      onView: () =>
                                          _openFile(f, download: false),
                                      onDownload: () =>
                                          _openFile(f, download: true),
                                    ),
                                if ((s.feedback ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('Feedback: ${s.feedback}',
                                      style: _captionStyle.copyWith(color: _ink)),
                                ],
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _review(s),
                                  style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 40)),
                                  icon: const Icon(Icons.rate_review_outlined,
                                      size: 16),
                                  label: Text(
                                      s.reviewed ? 'Edit review' : 'Review'),
                                ),
                              ],
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
    );
  }
}


IconData _fileIcon(String ext) {
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
      return Icons.image_outlined;
    case 'mp4':
    case 'mov':
    case 'webm':
      return Icons.movie_outlined;
    case 'mp3':
    case 'wav':
      return Icons.audiotrack_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

/// One submitted file with View / Download (touch-friendly, wraps on phones).
/// Types a browser can show are previewed; for the others "Open" hands the
/// file to the device's own app (or downloads it).
class _SubmittedFile extends StatelessWidget {
  const _SubmittedFile({
    required this.file,
    required this.busy,
    required this.onView,
    required this.onDownload,
  });

  final SubmissionFile file;
  final bool busy;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final ext = file.extension;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_fileIcon(ext), size: 20, color: AppColors.menuButton),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _titleStyle.copyWith(fontSize: 13)),
                    Text(
                        '${ext.isEmpty ? 'FILE' : ext.toUpperCase()} · '
                        '${formatFileSize(file.sizeBytes)}',
                        style: _captionStyle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onView,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        file.previewable
                            ? Icons.visibility_outlined
                            : Icons.open_in_new,
                        size: 16),
                label: Text(file.previewable ? 'View' : 'Open'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onDownload,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
