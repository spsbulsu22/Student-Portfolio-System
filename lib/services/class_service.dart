import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'supabase_clients.dart';

/// Private bucket (Instructor project) that holds submitted files.
const kClassBucket = 'class-submissions';

/// An error whose message is safe to show to the user as it is.
class ClassFailure implements Exception {
  const ClassFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

// ----------------------------------------------------------------------------
// Models
// ----------------------------------------------------------------------------
DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v as String)?.toLocal();

/// Maximum number of files in one assignment submission (also enforced by the
/// backend).
const int kMaxSubmissionFiles = 10;

String fileExtension(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 || i == name.length - 1 ? '' : name.substring(i + 1).toLowerCase();
}

/// "1.2 MB" (decimal units, like the 50 MB upload limit).
String formatFileSize(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) {
    return '${(bytes / 1000).toStringAsFixed(bytes < 10000 ? 1 : 0)} KB';
  }
  return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
}

const _previewExt = {
  'pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'txt', 'mp4', 'webm', 'mp3', 'wav',
};

/// Types a browser / phone can usually show without extra software. Others
/// (Word, Excel, PowerPoint, ZIP...) are opened with the device's own app or
/// downloaded.
bool isPreviewableFile(String name) => _previewExt.contains(fileExtension(name));

class ClassRoom {
  const ClassRoom({
    required this.id,
    required this.name,
    required this.description,
    required this.code,
    required this.instructorName,
    this.taskCount = 0,
    this.submittedCount = 0,
    this.enrollmentStatus = 'approved',
  });

  final String id;
  final String name;
  final String description;
  final String code;
  final String instructorName;
  final int taskCount; // student view only
  final int submittedCount; // student view only

  /// Student view: approved | pending | rejected. Only approved students have
  /// access to the class.
  final String enrollmentStatus;
  bool get isApproved => enrollmentStatus == 'approved';

  factory ClassRoom.fromMap(Map<String, dynamic> m) => ClassRoom(
        id: m['id'] as String,
        name: m['name'] as String,
        description: (m['description'] as String?) ?? '',
        code: (m['code'] as String?) ?? '',
        instructorName: (m['instructor_name'] as String?) ?? '',
        taskCount: (m['task_count'] as num?)?.toInt() ?? 0,
        submittedCount: (m['submitted_count'] as num?)?.toInt() ?? 0,
        enrollmentStatus: (m['enrollment_status'] as String?) ?? 'approved',
      );
}

class ClassMember {
  const ClassMember({
    required this.id,
    required this.studentId,
    required this.name,
    required this.number,
    required this.email,
    this.status = 'approved',
    this.requestedAt,
  });

  /// Id of the enrollment record (used to approve / reject / remove).
  final String id;
  final String status; // pending | approved | rejected | removed
  final DateTime? requestedAt;
  final String studentId;
  final String name;
  final String number;
  final String email;

  /// Student number when known, otherwise the e-mail.
  String get label => number.isNotEmpty ? number : email;

  factory ClassMember.fromMap(Map<String, dynamic> m) => ClassMember(
        id: (m['id'] as String?) ?? '',
        status: (m['status'] as String?) ?? 'approved',
        requestedAt: _date(m['requested_at']),
        studentId: m['student_id'] as String,
        name: ((m['student_name'] as String?) ?? '').isEmpty
            ? (m['student_email'] as String)
            : m['student_name'] as String,
        number: (m['student_number'] as String?) ?? '',
        email: (m['student_email'] as String?) ?? '',
      );
}

/// A class of the logged-in instructor with its approved students and the
/// join requests waiting for a decision.
class InstructorClass {
  const InstructorClass({
    required this.room,
    required this.members,
    this.requests = const [],
  });
  final ClassRoom room;
  final List<ClassMember> members; // approved
  final List<ClassMember> requests; // pending
}

/// Invitation as the instructor sees it.
class SentInvitation {
  const SentInvitation({
    required this.id,
    required this.email,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String status; // pending | accepted | declined | expired
  final DateTime? createdAt;

  factory SentInvitation.fromMap(Map<String, dynamic> m) {
    var status = m['status'] as String;
    final expires = _date(m['expires_at']);
    if (status == 'pending' && expires != null && expires.isBefore(DateTime.now())) {
      status = 'expired';
    }
    return SentInvitation(
      id: m['id'] as String,
      email: m['invited_email'] as String,
      status: status,
      createdAt: _date(m['created_at']),
    );
  }
}

/// Invitation as the student sees it.
class ReceivedInvitation {
  const ReceivedInvitation({required this.id, required this.room});
  final String id;
  final ClassRoom room;

  factory ReceivedInvitation.fromMap(Map<String, dynamic> m) =>
      ReceivedInvitation(
        id: m['id'] as String,
        room: ClassRoom.fromMap(Map<String, dynamic>.from(m['classes'] as Map)),
      );
}

/// One file of a submission.
class SubmissionFile {
  const SubmissionFile({
    required this.id,
    required this.fileName,
    this.mimeType = '',
    this.sizeBytes = 0,
    this.storagePath,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String? storagePath; // instructor view only

  String get extension => fileExtension(fileName);
  bool get previewable => isPreviewableFile(fileName);

  factory SubmissionFile.fromMap(Map<String, dynamic> m) => SubmissionFile(
        id: m['id'] as String,
        fileName: m['file_name'] as String,
        mimeType: (m['mime_type'] as String?) ?? '',
        sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
        storagePath: m['storage_path'] as String?,
      );
}

List<SubmissionFile> _fileList(dynamic v, {bool Function(Map)? where}) {
  final rows = <Map>[
    for (final e in (v as List? ?? const []))
      if (e is Map && (where == null || where(e))) e,
  ]..sort((a, b) =>
      '${a['created_at'] ?? ''}'.compareTo('${b['created_at'] ?? ''}'));
  return [
    for (final e in rows) SubmissionFile.fromMap(Map<String, dynamic>.from(e)),
  ];
}

class TaskSubmission {
  const TaskSubmission({
    this.id,
    this.assignmentId,
    this.studentName = '',
    this.studentEmail = '',
    required this.status,
    this.feedback,
    this.files = const [],
    this.draftFiles = const [],
    this.submittedAt,
    this.reviewedAt,
  });

  final String? id; // instructor view
  final String? assignmentId;
  final String studentName;
  final String studentEmail;

  /// draft | submitted | reviewed. A draft is never visible to the
  /// instructor and has no submission time.
  final String status;
  final String? feedback;

  /// The official (submitted) files.
  final List<SubmissionFile> files;

  /// Student view: files selected but not submitted yet.
  final List<SubmissionFile> draftFiles;
  final DateTime? submittedAt; // set only when really submitted
  final DateTime? reviewedAt;

  bool get reviewed => status == 'reviewed';
  bool get isDraft => status == 'draft';

  /// "report.pdf" or "3 files".
  String get fileName => files.isEmpty
      ? ''
      : (files.length == 1 ? files.first.fileName : '${files.length} files');

  factory TaskSubmission.fromMap(Map<String, dynamic> m) => TaskSubmission(
        id: m['id'] as String?,
        assignmentId: m['assignment_id'] as String?,
        studentName: (m['student_name'] as String?) ?? '',
        studentEmail: (m['student_email'] as String?) ?? '',
        status: m['status'] as String,
        feedback: m['feedback'] as String?,
        // student shape: files / draft_files; instructor shape: embedded rows
        files: m.containsKey('submission_files')
            ? _fileList(m['submission_files'], where: (f) => f['is_draft'] != true)
            : _fileList(m['files']),
        draftFiles: _fileList(m['draft_files']),
        submittedAt: _date(m['submitted_at']),
        reviewedAt: _date(m['reviewed_at']),
      );
}

class ClassTask {
  const ClassTask({
    required this.id,
    required this.title,
    required this.instructions,
    required this.requirements,
    required this.deadline,
    required this.createdAt,
    this.submissionCount = 0,
    this.submission,
  });

  final String id;
  final String title;
  final String instructions;
  final String requirements;
  final DateTime? deadline;
  final DateTime? createdAt;
  final int submissionCount; // instructor view
  final TaskSubmission? submission; // student view (null = pending)

  bool get isPastDeadline =>
      deadline != null && deadline!.isBefore(DateTime.now());

  /// Same task with another (possibly no) submission.
  ClassTask withSubmission(TaskSubmission? s) => ClassTask(
        id: id,
        title: title,
        instructions: instructions,
        requirements: requirements,
        deadline: deadline,
        createdAt: createdAt,
        submissionCount: submissionCount,
        submission: s,
      );

  factory ClassTask.fromMap(Map<String, dynamic> m) {
    var count = 0;
    final subs = m['submissions'];
    if (subs is List && subs.isNotEmpty && subs.first is Map) {
      count = ((subs.first as Map)['count'] as num?)?.toInt() ?? 0;
    }
    final sub = m['submission'];
    return ClassTask(
      id: m['id'] as String,
      title: m['title'] as String,
      instructions: (m['instructions'] as String?) ?? '',
      requirements: (m['requirements'] as String?) ?? '',
      deadline: _date(m['deadline']),
      createdAt: _date(m['created_at']),
      submissionCount: count,
      submission: sub is Map
          ? TaskSubmission.fromMap(Map<String, dynamic>.from(sub))
          : null,
    );
  }
}

/// One assignment of the instructor with the number of OFFICIAL submissions
/// (never drafts) waiting for review and already reviewed. Used by the
/// Instructor Submissions page.
class TaskSubmissionSummary {
  const TaskSubmissionSummary({
    required this.task,
    required this.classId,
    required this.className,
    required this.pending,
    required this.reviewed,
  });

  final ClassTask task;
  final String classId;
  final String className;
  final int pending; // status = submitted
  final int reviewed; // status = reviewed
}

// ----------------------------------------------------------------------------
// Student notifications: exactly these four kinds exist.
// ----------------------------------------------------------------------------
const kNotifRequestAccepted = 'request_accepted';
const kNotifInvitation = 'class_invitation';
const kNotifNewAssignment = 'new_assignment';
const kNotifSubmissionReviewed = 'submission_reviewed';

class StudentNotification {
  const StudentNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    this.classId,
    this.assignmentId,
    this.room,
  });

  final String id;
  final String type;
  final String title;
  final String message;
  final DateTime? createdAt;
  final bool isRead;
  final String? classId;
  final String? assignmentId;

  /// The class the notification is about (when the student can still see it).
  final ClassRoom? room;

  StudentNotification asRead() => StudentNotification(
        id: id,
        type: type,
        title: title,
        message: message,
        createdAt: createdAt,
        isRead: true,
        classId: classId,
        assignmentId: assignmentId,
        room: room,
      );

  factory StudentNotification.fromMap(Map<String, dynamic> m) {
    final c = m['class'];
    ClassRoom? room;
    if (c is Map && c['id'] is String && c['name'] is String) {
      final cm = Map<String, dynamic>.from(c);
      cm['enrollment_status'] = 'approved';
      room = ClassRoom.fromMap(cm);
    }
    return StudentNotification(
      id: m['id'] as String,
      type: (m['type'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      message: (m['message'] as String?) ?? '',
      createdAt: _date(m['created_at']),
      isRead: m['is_read'] == true,
      classId: m['class_id'] as String?,
      assignmentId: m['assignment_id'] as String?,
      room: room,
    );
  }
}

/// Instructor notification: ONE per task ("2 students submitted Task 3.").
class InstructorNotification {
  const InstructorNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.classId,
    required this.assignmentId,
    required this.studentCount,
    required this.updatedAt,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String message;
  final String classId;
  final String assignmentId;
  final int studentCount;
  final DateTime? updatedAt; // moves forward with every new submission
  final bool isRead;

  InstructorNotification asRead() => InstructorNotification(
        id: id,
        title: title,
        message: message,
        classId: classId,
        assignmentId: assignmentId,
        studentCount: studentCount,
        updatedAt: updatedAt,
        isRead: true,
      );

  factory InstructorNotification.fromMap(Map<String, dynamic> m) =>
      InstructorNotification(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        message: (m['message'] as String?) ?? '',
        classId: (m['class_id'] as String?) ?? '',
        assignmentId: (m['assignment_id'] as String?) ?? '',
        studentCount: (m['student_count'] as num?)?.toInt() ?? 0,
        updatedAt: _date(m['updated_at']),
        isRead: m['is_read'] == true,
      );
}

class StudentClassView {
  const StudentClassView({required this.room, required this.tasks});
  final ClassRoom room;
  final List<ClassTask> tasks;
}

String _postgrestMessage(PostgrestException e) {
  if (e.code == '23505') return 'That already exists.';
  if (e.code == '42501') return 'You are not allowed to do that.';
  if (e.code == '42P01' || e.code == 'PGRST205') {
    return 'Classes are not set up yet. Run supabase/instructor_classes.sql.';
  }
  return 'Something went wrong. Please try again.';
}

const _timeout = Duration(seconds: 25);
const _offline = ClassFailure(
  'Could not reach the server. Check your connection and try again.',
);

// ----------------------------------------------------------------------------
// INSTRUCTOR: talks to the Instructor project with the instructor's own login;
// Row Level Security limits every query to the instructor's own classes.
// ----------------------------------------------------------------------------
class InstructorClassApi {
  InstructorClassApi._();

  static SupabaseClient get _db => AppSupabase.instructor;

  static Future<T> _run<T>(Future<T> Function() job) async {
    try {
      return await job().timeout(_timeout);
    } on ClassFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw ClassFailure(_postgrestMessage(e));
    } on StorageException {
      throw const ClassFailure('Could not open the file.');
    } on TimeoutException {
      throw const ClassFailure('The server took too long. Try again.');
    } catch (_) {
      throw _offline;
    }
  }

  static String _displayName() {
    final u = _db.auth.currentUser;
    final m = u?.userMetadata ?? const <String, dynamic>{};
    final n = (m['full_name'] ?? m['name'])?.toString().trim() ?? '';
    if (n.isNotEmpty) return n;
    return (u?.email ?? 'Instructor').split('@').first;
  }

  static const _classCols = 'id, name, description, code, instructor_name';

  static Future<List<InstructorClass>> classes() => _run(() async {
        final rows = await _db
            .from('classes')
            .select('$_classCols, class_members(id, student_id, student_name, '
                'student_number, student_email, joined_at, requested_at, status)')
            .order('created_at');
        return [
          for (final r in rows) _classWithPeople(Map<String, dynamic>.from(r)),
        ];
      });

  static InstructorClass _classWithPeople(Map<String, dynamic> r) {
    final all = [
      for (final m in (r['class_members'] as List? ?? const []))
        ClassMember.fromMap(Map<String, dynamic>.from(m as Map)),
    ];
    final requests = [for (final m in all) if (m.status == 'pending') m]
      ..sort((a, b) => (a.requestedAt ?? DateTime(0))
          .compareTo(b.requestedAt ?? DateTime(0)));
    return InstructorClass(
      room: ClassRoom.fromMap(r),
      members: [for (final m in all) if (m.status == 'approved') m],
      requests: requests,
    );
  }

  /// Approve or reject a pending join request. Only the owner of the class can
  /// do it (Row Level Security); the database also rejects any other change.
  static Future<void> decideRequest(String memberId,
          {required bool approve}) =>
      _run(() async {
        final rows = await _db
            .from('class_members')
            .update({'status': approve ? 'approved' : 'rejected'})
            .eq('id', memberId)
            .eq('status', 'pending')
            .select('id');
        if (rows.isEmpty) {
          throw const ClassFailure(
              'This request was already handled or can not be changed.');
        }
      });

  /// Takes the student out of the class: access is revoked at once. Nothing
  /// else is deleted (account, other classes, past submissions).
  static Future<void> removeStudent(String memberId) => _run(() async {
        final rows = await _db
            .from('class_members')
            .update({'status': 'removed'})
            .eq('id', memberId)
            .eq('status', 'approved')
            .select('id');
        if (rows.isEmpty) {
          throw const ClassFailure(
              'This student was already removed or can not be changed.');
        }
      });

  /// The unique class code is generated by the database on insert.
  static Future<ClassRoom> createClass(String name, String description) =>
      _run(() async {
        final row = await _db
            .from('classes')
            .insert({
              'name': name.trim(),
              'description': description.trim(),
              'instructor_name': _displayName(),
            })
            .select(_classCols)
            .single();
        return ClassRoom.fromMap(Map<String, dynamic>.from(row));
      });

  static Future<List<SentInvitation>> invitations(String classId) =>
      _run(() async {
        final rows = await _db
            .from('class_invitations')
            .select('id, invited_email, status, created_at, expires_at')
            .eq('class_id', classId)
            .order('created_at', ascending: false);
        return [
          for (final r in rows)
            SentInvitation.fromMap(Map<String, dynamic>.from(r)),
        ];
      });

  static Future<void> invite(String classId, String email) async {
    final mail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      throw const ClassFailure('Enter a valid student email address.');
    }
    try {
      await _run(() async {
        final enrolled = await _db
            .from('class_members')
            .select('id')
            .eq('class_id', classId)
            .eq('student_email', mail)
            .eq('status', 'approved')
            .maybeSingle();
        if (enrolled != null) {
          throw const ClassFailure('That student is already in this class.');
        }
        await _db
            .from('class_invitations')
            .insert({'class_id': classId, 'invited_email': mail});
      });
    } on ClassFailure catch (e) {
      if (e.message == 'That already exists.') {
        throw const ClassFailure(
            'An invitation to that student is already pending.');
      }
      rethrow;
    }
  }

  static Future<List<ClassMember>> members(String classId) => _run(() async {
        final rows = await _db
            .from('class_members')
            .select()
            .eq('class_id', classId)
            .eq('status', 'approved')
            .order('joined_at');
        return [
          for (final r in rows)
            ClassMember.fromMap(Map<String, dynamic>.from(r)),
        ];
      });

  static Future<List<ClassTask>> tasks(String classId) => _run(() async {
        final rows = await _db
            .from('assignments')
            .select('*, submissions(count)')
            .eq('class_id', classId)
            .order('created_at', ascending: false);
        return [
          for (final r in rows) ClassTask.fromMap(Map<String, dynamic>.from(r)),
        ];
      });

  static Future<void> createTask({
    required String classId,
    required String title,
    required String instructions,
    required String requirements,
    DateTime? deadline,
  }) =>
      _run(() async {
        await _db.from('assignments').insert({
          'class_id': classId,
          'title': title.trim(),
          'instructions': instructions.trim(),
          'requirements': requirements.trim(),
          'deadline': deadline?.toUtc().toIso8601String(),
        });
      });

  static Future<List<TaskSubmission>> submissions(String assignmentId) =>
      _run(() async {
        final rows = await _db
            .from('submissions')
            .select('*, submission_files(id, file_name, mime_type, size_bytes, '
                'storage_path, is_draft, created_at)')
            .eq('assignment_id', assignmentId)
            .neq('status', 'draft') // drafts are never official submissions
            .order('submitted_at', ascending: false);
        return [
          for (final r in rows)
            TaskSubmission.fromMap(Map<String, dynamic>.from(r)),
        ];
      });

  /// Every assignment of the instructor's classes that has at least one
  /// finalized submission, with the pending / reviewed counts. Drafts are
  /// ignored. Row Level Security limits it to the instructor's own classes.
  static Future<List<TaskSubmissionSummary>> submissionOverview() =>
      _run(() async {
        final rows = await _db
            .from('assignments')
            .select('*, classes(id, name), submissions(id, status)')
            .order('created_at', ascending: false);
        final out = <TaskSubmissionSummary>[];
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r);
          var pending = 0, reviewed = 0;
          for (final e in (m['submissions'] as List? ?? const [])) {
            if (e is! Map) continue;
            final st = e['status'];
            if (st == 'submitted') pending++;
            if (st == 'reviewed') reviewed++;
          }
          if (pending + reviewed == 0) continue;
          final c = m['classes'];
          final Map? cls = c is Map
              ? c
              : (c is List && c.isNotEmpty && c.first is Map
                  ? c.first as Map
                  : null);
          m.remove('submissions'); // the count shape ClassTask expects differs
          out.add(TaskSubmissionSummary(
            task: ClassTask.fromMap(m),
            classId: (m['class_id'] as String?) ?? '',
            className: (cls?['name'] as String?) ?? '',
            pending: pending,
            reviewed: reviewed,
          ));
        }
        return out;
      });

  /// The instructor's task notifications (newest activity first). Row Level
  /// Security shows only the notifications of the instructor's own classes.
  static Future<List<InstructorNotification>> notifications() =>
      _run(() async {
        final rows = await _db
            .from('instructor_notifications')
            .select('id, title, message, class_id, assignment_id, '
                'student_count, is_read, updated_at')
            .order('updated_at', ascending: false)
            .limit(100);
        return [
          for (final r in rows)
            InstructorNotification.fromMap(Map<String, dynamic>.from(r)),
        ];
      });

  /// Number of unread task notifications (one row per task, so each task
  /// counts once however many students submitted).
  static Future<int> unreadNotificationCount() => _run(() async {
        final rows = await _db
            .from('instructor_notifications')
            .select('id')
            .eq('is_read', false)
            .limit(1000);
        return rows.length;
      });

  /// Only `is_read` can be changed by the app (column-level grant).
  static Future<void> markNotificationRead(String id) => _run(() async {
        await _db
            .from('instructor_notifications')
            .update({'is_read': true}).eq('id', id);
      });

  static Future<void> markReviewed(String submissionId, String feedback) =>
      _run(() async {
        await _db.from('submissions').update({
          'status': 'reviewed',
          'feedback': feedback.trim().isEmpty ? null : feedback.trim(),
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', submissionId);
      });

  /// Temporary link (1 hour) to a submitted file. With [downloadAs] the link
  /// makes the browser / phone save the file instead of showing it.
  static Future<String> fileUrl(String storagePath, {String? downloadAs}) =>
      _run(() async {
        final url = await _db.storage
            .from(kClassBucket)
            .createSignedUrl(storagePath, 3600);
        if (downloadAs == null) return url;
        return '$url${url.contains('?') ? '&' : '?'}'
            'download=${Uri.encodeComponent(downloadAs)}';
      });
}

// ----------------------------------------------------------------------------
// STUDENT: never touches the Instructor database. Every call goes to the
// `student-classes` Edge Function of the Instructor project, carrying the
// student's own access token, which the function verifies against the Student
// project before doing anything.
// ----------------------------------------------------------------------------
class StudentClassApi {
  StudentClassApi._();

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> body,
      {String function = 'student-classes'}) async {
    var session = AppSupabase.student.auth.currentSession;
    if (session == null) {
      throw const ClassFailure('Please log in again.');
    }
    if (session.isExpired) {
      try {
        session = (await AppSupabase.student.auth.refreshSession()).session;
      } catch (_) {}
    }
    final token = session?.accessToken;
    if (token == null) throw const ClassFailure('Please log in again.');

    try {
      final res = await AppSupabase.instructor.functions
          .invoke(
            function,
            body: body,
            headers: {'x-student-token': token},
          )
          .timeout(_timeout);
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const ClassFailure('Unexpected response from the server.');
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] is String) {
        throw ClassFailure(d['error'] as String);
      }
      throw const ClassFailure('Something went wrong. Please try again.');
    } on ClassFailure {
      rethrow;
    } on TimeoutException {
      throw const ClassFailure('The server took too long. Try again.');
    } catch (_) {
      throw _offline;
    }
  }

  static List<Map<String, dynamic>> _list(dynamic v) => [
        for (final e in (v as List? ?? const []))
          Map<String, dynamic>.from(e as Map),
      ];

  static Future<List<ClassRoom>> classes() async {
    final r = await _call({'action': 'list_classes'});
    return [for (final m in _list(r['classes'])) ClassRoom.fromMap(m)];
  }

  /// The student's notifications (newest first), read through the
  /// `student-notifications` Edge Function of the Instructor project.
  static Future<List<StudentNotification>> notifications() async {
    final r = await _call({'action': 'list'}, function: 'student-notifications');
    return [
      for (final m in _list(r['notifications'])) StudentNotification.fromMap(m),
    ];
  }

  /// Number of unread notifications of the student (from the same backend
  /// list the notifications page shows).
  static Future<int> unreadNotificationCount() async =>
      (await notifications()).where((n) => !n.isRead).length;

  static Future<void> markNotificationsRead(List<String> ids) => _call(
        {'action': 'mark_read', 'ids': ids},
        function: 'student-notifications',
      );

  static Future<List<ReceivedInvitation>> invitations() async {
    final r = await _call({'action': 'list_invitations'});
    return [
      for (final m in _list(r['invitations'])) ReceivedInvitation.fromMap(m),
    ];
  }

  static Future<void> respond(String invitationId, {required bool accept}) =>
      _call({
        'action': 'respond_invitation',
        'invitation_id': invitationId,
        'accept': accept,
      });

  /// Sends a join REQUEST (status pending); the instructor approves it.
  static Future<ClassRoom> joinByCode(String code) async {
    final r = await _call({'action': 'join_by_code', 'code': code});
    final room = Map<String, dynamic>.from(r['class'] as Map);
    room['enrollment_status'] = (r['status'] as String?) ?? 'pending';
    return ClassRoom.fromMap(room);
  }

  static Future<StudentClassView> detail(String classId) async {
    final r = await _call({'action': 'class_detail', 'class_id': classId});
    return StudentClassView(
      room: ClassRoom.fromMap(Map<String, dynamic>.from(r['class'] as Map)),
      tasks: [for (final m in _list(r['assignments'])) ClassTask.fromMap(m)],
    );
  }

  static TaskSubmission? _submission(Map<String, dynamic> r) {
    final v = r['submission'];
    return v is Map ? TaskSubmission.fromMap(Map<String, dynamic>.from(v)) : null;
  }

  /// Adds one file to the student's DRAFT: asks the backend for permission,
  /// uploads the bytes with the one-time token it returns, then lets the
  /// backend record it. The file is NOT submitted and the instructor can not
  /// see it. Returns the updated submission (null when nothing is left).
  static Future<TaskSubmission?> addFile({
    required String assignmentId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final up = await _call({
      'action': 'create_upload',
      'assignment_id': assignmentId,
      'file_name': fileName,
      'size_bytes': bytes.length,
    });
    final path = up['path'] as String;
    try {
      await AppSupabase.instructor.storage
          .from(kClassBucket)
          .uploadBinaryToSignedUrl(
            path,
            up['token'] as String,
            bytes,
            FileOptions(contentType: up['mime_type'] as String?),
          );
    } on StorageException {
      throw const ClassFailure('The upload failed. Please try again.');
    } catch (_) {
      throw _offline;
    }
    return _submission(await _call({
      'action': 'add_file',
      'assignment_id': assignmentId,
      'path': path,
      'file_name': fileName,
    }));
  }

  /// Removes one draft file.
  static Future<TaskSubmission?> removeFile(
          String assignmentId, String fileId) async =>
      _submission(await _call({
        'action': 'remove_file',
        'assignment_id': assignmentId,
        'file_id': fileId,
      }));

  /// "Submit Assignment": the only call that makes the drafts official (and
  /// sets the submission time). Repeating it changes nothing.
  static Future<TaskSubmission> submit(String assignmentId) async {
    final s = _submission(await _call({
      'action': 'submit',
      'assignment_id': assignmentId,
    }));
    if (s == null) {
      throw const ClassFailure('Unexpected response from the server.');
    }
    return s;
  }
}
