import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/class_service.dart';
import '../services/storage_service.dart' show validateUploadFile;
import '../theme/app_colors.dart';

const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _panel = Color(0xFFF3F4F6);
const _rowBorder = Color(0xFFE5E7EB);
const _danger = Color(0xFFB42318);
const _green = Color(0xFF027A48);
const _amber = Color(0xFFB54708);

const _itemTitle = TextStyle(
    fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.w600, color: _ink);
const _caption = TextStyle(
    fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w400, color: _muted);

String _dateText(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '${m[d.month - 1]} ${d.day}, ${d.year} $h:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// One joined class: instructor, description and its tasks. A task is handed
/// in in two steps: the student first collects up to 10 files in a DRAFT
/// (nothing is visible to the instructor), then explicitly presses "Submit
/// Assignment" and confirms. Everything is read from / sent to the Instructor
/// project's backend ([StudentClassApi]).
///
/// Opened from a notification, [focusTaskId] scrolls to that task and
/// highlights it.
class StudentClassDetailScreen extends StatefulWidget {
  const StudentClassDetailScreen(
      {super.key, required this.room, this.focusTaskId});
  final ClassRoom room;
  final String? focusTaskId;

  @override
  State<StudentClassDetailScreen> createState() =>
      _StudentClassDetailScreenState();
}

class _StudentClassDetailScreenState extends State<StudentClassDetailScreen> {
  StudentClassView? _view;
  String? _error;
  final Set<String> _adding = <String>{}; // task ids: files being uploaded
  final Set<String> _submitting = <String>{}; // task ids: confirming / submitting
  final Set<String> _removing = <String>{}; // file ids
  final Map<String, String> _progress = <String, String>{};
  bool _picking = false;
  final Map<String, GlobalKey> _taskKeys = <String, GlobalKey>{};
  bool _focused = false; // the notification target is scrolled to only once

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final v = await StudentClassApi.detail(widget.room.id);
      if (mounted) {
        setState(() => _view = v);
        _focusTask();
      }
    } on ClassFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Scrolls to the task a notification is about (task section of the class).
  void _focusTask() {
    final id = widget.focusTaskId;
    if (id == null || _focused) return;
    _focused = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _taskKeys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
    });
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? _danger : _ink,
      ));
  }

  ClassTask? _task(String id) {
    final v = _view;
    if (v == null) return null;
    for (final t in v.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Shows the submission the backend just returned, without reloading.
  void _patch(String taskId, TaskSubmission? sub) {
    final v = _view;
    if (v == null || !mounted) return;
    setState(() => _view = StudentClassView(
          room: v.room,
          tasks: [
            for (final t in v.tasks) t.id == taskId ? t.withSubmission(sub) : t,
          ],
        ));
  }

  /// Several files at once (the picker also lets the student pick just one).
  Future<List<PlatformFile>> _pickMany() async {
    final dynamic res = await FilePicker.pickFiles();
    if (res == null) return const [];
    final list = res is List ? res : (res.files as List);
    return [for (final f in list) f as PlatformFile];
  }

  /// Adds files to the DRAFT. Nothing is submitted here.
  Future<void> _addFiles(ClassTask task) async {
    if (_picking || _adding.contains(task.id) || _submitting.contains(task.id)) {
      return;
    }
    _picking = true;
    var picked = const <PlatformFile>[];
    try {
      picked = await _pickMany();
    } catch (_) {
      if (mounted) {
        _toast('Could not open the file picker. Please try again.', error: true);
      }
    } finally {
      _picking = false;
    }
    if (picked.isEmpty || !mounted) return;

    final have = _task(task.id)?.submission?.draftFiles.length ?? 0;
    if (have + picked.length > kMaxSubmissionFiles) {
      _toast(
        'You can attach up to $kMaxSubmissionFiles files per submission. '
        'You have $have and selected ${picked.length}.',
        error: true,
      );
      return;
    }

    var skipped = 0;
    String? firstProblem;
    final ok = <PlatformFile>[];
    for (final f in picked) {
      final problem = validateUploadFile(f.name, null); // type
      if (problem != null) {
        skipped++;
        firstProblem ??= problem;
      } else {
        ok.add(f);
      }
    }

    var added = 0;
    String? failure;
    setState(() => _adding.add(task.id));
    try {
      for (var i = 0; i < ok.length; i++) {
        final f = ok[i];
        if (mounted) {
          setState(() =>
              _progress[task.id] = 'Uploading ${i + 1} of ${ok.length}...');
        }
        final bytes = await f.readAsBytes();
        final problem = validateUploadFile(f.name, bytes.length); // size
        if (problem != null) {
          skipped++;
          firstProblem ??= problem;
          continue;
        }
        final sub = await StudentClassApi.addFile(
          assignmentId: task.id,
          fileName: f.name,
          bytes: bytes,
        );
        added++;
        _patch(task.id, sub);
      }
    } on ClassFailure catch (e) {
      failure = e.message;
    } catch (_) {
      failure = 'Could not read the selected file. Pick it again.';
    }
    if (mounted) {
      setState(() {
        _adding.remove(task.id);
        _progress.remove(task.id);
      });
      if (failure != null) {
        _toast(failure, error: true);
        await _load(); // show what really reached the server
      } else if (skipped > 0) {
        _toast(
          '${added > 0 ? '$added added. ' : ''}$skipped skipped: $firstProblem',
          error: added == 0,
        );
      } else if (added > 0) {
        _toast('${added == 1 ? 'File' : '$added files'} added to your draft. '
            'Press "Submit Assignment" when you are ready.');
      }
    }
  }

  Future<void> _removeFile(ClassTask task, SubmissionFile f) async {
    if (_removing.contains(f.id)) return;
    setState(() => _removing.add(f.id));
    try {
      _patch(task.id, await StudentClassApi.removeFile(task.id, f.id));
    } on ClassFailure catch (e) {
      if (mounted) _toast(e.message, error: true);
      await _load();
    } finally {
      if (mounted) setState(() => _removing.remove(f.id));
    }
  }

  /// "Submit Assignment": confirm, then make the draft official.
  Future<void> _submit(ClassTask task) async {
    if (_submitting.contains(task.id) || _adding.contains(task.id)) return;
    final sub = task.submission;
    final drafts = sub?.draftFiles.length ?? 0;
    if (drafts == 0) {
      _toast('Add at least one file before submitting.', error: true);
      return;
    }
    final replacing = sub?.files.length ?? 0;
    setState(() => _submitting.add(task.id)); // blocks repeated taps
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Submit assignment?',
            style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _ink)),
        content: Text(
          'You are about to submit $drafts ${drafts == 1 ? 'file' : 'files'} '
          'for "${task.title}".'
          '${replacing > 0 ? '\n\nThis replaces your previous submission '
              '($replacing ${replacing == 1 ? 'file' : 'files'}).' : ''}'
          '\n\nYour instructor will see it right away. After it is reviewed '
          'it can no longer be changed.',
          style: _caption.copyWith(fontSize: 14, color: _ink),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (go != true) {
      if (mounted) setState(() => _submitting.remove(task.id));
      return;
    }
    try {
      _patch(task.id, await StudentClassApi.submit(task.id));
      if (mounted) _toast('Assignment submitted successfully.');
    } on ClassFailure catch (e) {
      if (mounted) _toast(e.message, error: true);
      await _load();
    } finally {
      if (mounted) setState(() => _submitting.remove(task.id));
    }
  }

  Widget _chip(String label, Color color) => Container(
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

  Widget _panelBox({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );

  Widget _taskCard(ClassTask t) {
    final sub = t.submission;
    final past = t.isPastDeadline;
    final (label, color) = switch (sub) {
      TaskSubmission(reviewed: true) => ('Reviewed', _green),
      TaskSubmission(isDraft: true) => ('Draft', _amber),
      TaskSubmission() => ('Submitted', AppColors.menuButton),
      null when past => ('Overdue', _danger),
      null => ('Not Submitted', _amber),
    };
    final locked = (sub?.reviewed ?? false) || past;
    final adding = _adding.contains(t.id);
    final submitting = _submitting.contains(t.id);
    final busy = adding || submitting;
    final official = (sub != null && !sub.isDraft) ? sub : null;
    final drafts = sub?.draftFiles ?? const <SubmissionFile>[];
    final full = drafts.length >= kMaxSubmissionFiles;

    final focus = t.id == widget.focusTaskId;
    return Padding(
      key: _taskKeys.putIfAbsent(t.id, () => GlobalKey()),
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: focus ? AppColors.menuButton : _rowBorder,
              width: focus ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.title, style: _itemTitle)),
                const SizedBox(width: 8),
                _chip(label, color),
              ],
            ),
            const SizedBox(height: 2),
            Text(
                t.deadline == null
                    ? 'No deadline'
                    : 'Due ${_dateText(t.deadline)}',
                style: _caption),
            if (t.instructions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t.instructions,
                  style: _caption.copyWith(fontSize: 13, color: _ink)),
            ],
            if (t.requirements.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Requirements: ${t.requirements}',
                  style: _caption.copyWith(fontSize: 13)),
            ],
            // ---- official submission (what the instructor sees)
            if (official != null) ...[
              const SizedBox(height: 8),
              _panelBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Submitted ${_dateText(official.submittedAt)} · '
                        '${official.files.length} '
                        '${official.files.length == 1 ? 'file' : 'files'}',
                        style: _itemTitle.copyWith(fontSize: 13)),
                    const SizedBox(height: 6),
                    for (final f in official.files) _FileRow(file: f),
                    if ((official.feedback ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Feedback: ${official.feedback}',
                          style: _caption.copyWith(color: _ink)),
                    ],
                  ],
                ),
              ),
            ],
            // ---- draft (not submitted yet)
            if (!locked && drafts.isNotEmpty) ...[
              const SizedBox(height: 8),
              _panelBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Draft · ${drafts.length}/$kMaxSubmissionFiles files',
                        style: _itemTitle.copyWith(fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                        'Not submitted yet. Your instructor can not see these '
                        'files until you submit.',
                        style: _caption),
                    const SizedBox(height: 6),
                    for (final f in drafts)
                      _FileRow(
                        file: f,
                        removing: _removing.contains(f.id),
                        onRemove: busy ? null : () => _removeFile(t, f),
                      ),
                  ],
                ),
              ),
            ],
            // ---- actions
            if (!locked) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: (busy || full) ? null : () => _addFiles(t),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon: adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.attach_file, size: 18),
                    label: Text(adding
                        ? (_progress[t.id] ?? 'Uploading...')
                        : (drafts.isNotEmpty
                            ? 'Add more files'
                            : (official == null ? 'Add files' : 'Replace files'))),
                  ),
                  if (drafts.isNotEmpty)
                    FilledButton.icon(
                      onPressed: busy ? null : () => _submit(t),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size(0, 44)),
                      icon: submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(submitting
                          ? 'Submitting...'
                          : (official == null
                              ? 'Submit Assignment'
                              : 'Resubmit Assignment')),
                    ),
                ],
              ),
              if (full) ...[
                const SizedBox(height: 6),
                Text('Maximum of $kMaxSubmissionFiles files reached.',
                    style: _caption),
              ] else if (drafts.isEmpty && official != null) ...[
                const SizedBox(height: 6),
                Text('Add files, then submit again to replace your submission.',
                    style: _caption),
              ] else if (drafts.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                    'Up to $kMaxSubmissionFiles files. Nothing is sent until '
                    'you press "Submit Assignment".',
                    style: _caption),
              ],
            ] else if (sub == null) ...[
              const SizedBox(height: 8),
              Text('The deadline has passed.', style: _caption),
            ] else if (sub.isDraft) ...[
              const SizedBox(height: 8),
              Text('The deadline has passed. This draft was never submitted.',
                  style: _caption),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    final view = _view;
    final room = view?.room ?? widget.room;

    Widget body;
    if (_error != null && view == null) {
      body = Center(
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
      );
    } else if (view == null) {
      body = const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 18, color: AppColors.menuButton),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            room.instructorName.isEmpty
                                ? 'Instructor'
                                : room.instructorName,
                            style: _itemTitle),
                      ),
                    ],
                  ),
                  if (room.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(room.description,
                        style: _caption.copyWith(fontSize: 13, color: _ink)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Tasks',
                style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ink)),
            const SizedBox(height: 8),
            if (view.tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    const Icon(Icons.assignment_outlined,
                        size: 36, color: _muted),
                    const SizedBox(height: 10),
                    Text('No tasks assigned yet.',
                        style: _caption.copyWith(fontSize: 13)),
                  ],
                ),
              )
            else
              for (final t in view.tasks) _taskCard(t),
          ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
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
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.chevron_left,
                          size: 20, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(width: 52),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: body,
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

/// One file: name, type and size; with a remove button for draft files.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, this.onRemove, this.removing = false});
  final SubmissionFile file;
  final VoidCallback? onRemove;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    final ext = file.extension;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(_fileIcon(ext), size: 20, color: AppColors.menuButton),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _itemTitle.copyWith(fontSize: 13)),
                Text(
                    '${ext.isEmpty ? 'FILE' : ext.toUpperCase()} · '
                    '${formatFileSize(file.sizeBytes)}',
                    style: _caption),
              ],
            ),
          ),
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
              tooltip: 'Remove file',
              onPressed: onRemove,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.close_rounded, size: 20, color: _danger),
            ),
        ],
      ),
    );
  }
}
