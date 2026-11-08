import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../providers/auth_provider.dart';

/// Storage bucket (private) and metadata table. Created by
/// supabase/file_upload.sql, which must be run in BOTH Supabase projects.
const kFilesBucket = 'user-files';
const _table = 'user_files';
const _backupsTable = 'file_backups';
const _foldersTable = 'portfolio_folders';

/// 50MB, counted like the file manager does (1 MB = 1,000,000 bytes).
/// Keep in sync with `file_size_limit` in supabase/file_upload.sql.
const int kMaxUploadBytes = 50 * 1000 * 1000;

/// Allowed file types: extension -> MIME type.
/// Keep in sync with `allowed_mime_types` in supabase/file_upload.sql.
const Map<String, String> kAllowedFileTypes = {
  // documents
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx':
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'rtf': 'application/rtf',
  // images
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  // video
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  // audio
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  // archives
  'zip': 'application/zip',
};

/// Message that is safe to show to the user as it is.
class UploadFailure implements Exception {
  const UploadFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Lets the UI report progress and cancel a running upload.
class UploadControl {
  /// 0..1, only moves forward. Listen to it to draw a progress bar.
  final progress = _MonotonicProgress();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class _MonotonicProgress {
  double _value = 0;
  final _listeners = <void Function(double)>[];

  double get value => _value;

  void report(double v) {
    final next = v.clamp(0.0, 1.0).toDouble();
    if (next <= _value) return;
    _value = next;
    for (final l in List.of(_listeners)) {
      l(next);
    }
  }

  void addListener(void Function(double) l) => _listeners.add(l);
  void removeListener(void Function(double) l) => _listeners.remove(l);
}

/// One row of the metadata table.
class StoredFile {
  const StoredFile({
    required this.id,
    required this.ownerId,
    required this.role,
    required this.name,
    required this.originalName,
    required this.fileType,
    required this.mimeType,
    required this.sizeBytes,
    required this.storagePath,
    required this.visibility,
    required this.createdAt,
    this.description,
    this.isFavorite = false,
    this.folderId,
  });

  final String id;
  final String ownerId;
  final String role; // 'student' | 'instructor'
  final String name; // name shown in the app (can be edited before upload)
  final String originalName; // name of the picked file
  final String fileType; // extension without dot, lowercase
  final String mimeType;
  final int sizeBytes;
  final String storagePath;
  final String visibility; // 'private' | 'public' (as chosen in the UI)
  final DateTime createdAt;
  final String? description;
  final bool isFavorite; // starred (shown on the Favorite page)
  final String? folderId; // portfolio_folders.id; null = root of My Portfolio

  StoredFile withFavorite(bool value) => StoredFile(
        id: id,
        ownerId: ownerId,
        role: role,
        name: name,
        originalName: originalName,
        fileType: fileType,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        storagePath: storagePath,
        visibility: visibility,
        createdAt: createdAt,
        description: description,
        isFavorite: value,
        folderId: folderId,
      );

  bool get isPublic => visibility == 'public';

  /// Same file, public or private.
  StoredFile withVisibility(String value) => StoredFile(
        id: id,
        ownerId: ownerId,
        role: role,
        name: name,
        originalName: originalName,
        fileType: fileType,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        storagePath: storagePath,
        visibility: value,
        createdAt: createdAt,
        description: description,
        isFavorite: isFavorite,
        folderId: folderId,
      );

  /// Same file inside another folder (null = root of My Portfolio).
  StoredFile withFolder(String? value) => StoredFile(
        id: id,
        ownerId: ownerId,
        role: role,
        name: name,
        originalName: originalName,
        fileType: fileType,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        storagePath: storagePath,
        visibility: visibility,
        createdAt: createdAt,
        description: description,
        isFavorite: isFavorite,
        folderId: value,
      );

  factory StoredFile.fromMap(Map<String, dynamic> m) => StoredFile(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        role: m['role'] as String,
        name: m['name'] as String,
        originalName: m['original_name'] as String,
        fileType: m['file_type'] as String,
        mimeType: m['mime_type'] as String,
        sizeBytes: (m['size_bytes'] as num).toInt(),
        storagePath: m['storage_path'] as String,
        visibility: (m['visibility'] as String?) ?? 'private',
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        description: m['description'] as String?,
        isFavorite: (m['is_favorite'] as bool?) ?? false,
        folderId: m['folder_id'] as String?,
      );
}

/// One row of the `file_backups` table: a real copy of an uploaded file
/// (its own Storage object). It starts out linked to the original file, and
/// stays (with `fileId` null) after that file is deleted.
class StoredBackup {
  const StoredBackup({
    required this.id,
    required this.fileId,
    required this.name,
    required this.originalName,
    required this.fileType,
    required this.mimeType,
    required this.sizeBytes,
    required this.storagePath,
    required this.createdAt,
  });

  final String id;
  final String? fileId; // the original file (user_files.id); null once deleted
  final String name;
  final String originalName;
  final String fileType;
  final String mimeType;
  final int sizeBytes;
  final String storagePath;
  final DateTime createdAt;

  factory StoredBackup.fromMap(Map<String, dynamic> m) => StoredBackup(
        id: m['id'] as String,
        fileId: m['file_id'] as String?,
        name: m['name'] as String,
        originalName: m['original_name'] as String,
        fileType: m['file_type'] as String,
        mimeType: m['mime_type'] as String,
        sizeBytes: (m['size_bytes'] as num).toInt(),
        storagePath: m['storage_path'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

/// Returns an error message when the file can't be uploaded, or null when it
/// is fine. [sizeBytes] may be null when unknown (then only the type is
/// checked).
String? validateUploadFile(String fileName, int? sizeBytes) {
  final ext = _extensionOf(fileName);
  if (!kAllowedFileTypes.containsKey(ext)) {
    return ext.isEmpty
        ? 'That file has no extension, so its type is not supported.'
        : 'Files of type .$ext are not supported. Allowed: PDF, Word, Excel, '
            'PowerPoint, text, images, video, audio and ZIP.';
  }
  if (sizeBytes != null) {
    if (sizeBytes <= 0) return 'That file is empty.';
    if (sizeBytes > kMaxUploadBytes) {
      return 'That file is too large. The maximum size is 50MB.';
    }
  }
  return null;
}

/// Storage keys only allow a safe subset of characters.
String _safeKeyPart(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[._]+'), '');
  final trimmed = cleaned.length > 80
      ? cleaned.substring(cleaned.length - 80) // keep the extension
      : cleaned;
  return trimmed.isEmpty ? 'file' : trimmed;
}

String _uniqueId() {
  final r = math.Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$r';
}

/// The client (= Supabase project) of the logged-in user, plus their id.
({SupabaseClient client, String userId, UserRole role}) _session(
  AuthState auth,
) {
  final role = auth.role;
  final uid = auth.userId;
  if (role == null || uid == null) {
    throw const UploadFailure('Please log in again to upload files.');
  }
  final client = clientForRole(role);
  // Use the live session as the source of truth (it can have expired).
  final live = client.auth.currentUser;
  if (live == null || live.id != uid) {
    throw const UploadFailure('Your session has expired. Please log in again.');
  }
  return (client: client, userId: uid, role: role);
}

/// Uploads [file] to Supabase Storage and saves its metadata.
///
/// Storage path: `<role>/<user id>/<unique>_<safe name>` in the private
/// [kFilesBucket] bucket of the project that belongs to the user's role.
/// The row in `user_files` is only written after the file is stored; if the
/// row can't be written, or the upload was cancelled, the stored file is
/// removed again, so no orphan is left behind.
///
/// [displayName] is the name chosen on the review screen (with extension).
/// Throws [UploadFailure] with a message ready to show.
Future<StoredFile?> uploadPortfolioFile({
  required AuthState auth,
  required PlatformFile file,
  required String displayName,
  String? description,
  bool isPublic = false,
  String? folderId, // portfolio folder to store it in (null = root)
  UploadControl? control,
}) async {
  final s = _session(auth);
  final ctl = control ?? UploadControl();

  final ext = _extensionOf(file.name);
  final error = validateUploadFile(file.name, null); // type; size below
  if (error != null) throw UploadFailure(error);

  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    throw const UploadFailure('Could not read the selected file. Pick it again.');
  }
  if (bytes.length > kMaxUploadBytes) {
    throw const UploadFailure('That file is too large. The maximum size is 50MB.');
  }
  if (bytes.isEmpty) throw const UploadFailure('That file is empty.');

  final mime = kAllowedFileTypes[ext]!;
  final path =
      '${s.role.name}/${s.userId}/${_uniqueId()}_${_safeKeyPart(file.name)}';

  ctl.progress.report(0.05);
  try {
    await s.client.storage.from(kFilesBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
  } on StorageException catch (e) {
    throw UploadFailure(_storageMessage(e));
  } catch (_) {
    throw const UploadFailure(
      'Could not reach the server. Check your connection and try again.',
    );
  }
  ctl.progress.report(0.9);

  Future<void> removeStored() async {
    try {
      await s.client.storage.from(kFilesBucket).remove([path]);
    } catch (_) {}
  }

  if (ctl.isCancelled) {
    await removeStored();
    return null;
  }

  try {
    final row = await s.client
        .from(_table)
        .insert({
          'owner_id': s.userId,
          'role': s.role.name,
          'name': displayName,
          'original_name': file.name,
          'file_type': ext,
          'mime_type': mime,
          'size_bytes': bytes.length,
          'storage_path': path,
          'description':
              (description?.trim().isEmpty ?? true) ? null : description!.trim(),
          'visibility': isPublic ? 'public' : 'private',
          if (folderId != null) 'folder_id': folderId,
        })
        .select()
        .single();
    ctl.progress.report(0.98);
    if (ctl.isCancelled) {
      // Cancelled while saving: undo both parts.
      await s.client.from(_table).delete().eq('id', row['id'] as String);
      await removeStored();
      return null;
    }
    return StoredFile.fromMap(row);
  } on PostgrestException catch (e) {
    await removeStored();
    if (folderId != null && _folderSetupMissing(e)) {
      throw const UploadFailure(_folderSetupMessage);
    }
    if (folderId != null && (e.code == '23503' || e.code == '23514')) {
      throw const UploadFailure('That folder no longer exists. Go back and '
          'open it again.');
    }
    throw const UploadFailure(
      'The file was uploaded but could not be saved. Please try again.',
    );
  } catch (_) {
    await removeStored();
    throw const UploadFailure(
      'Could not reach the server. Check your connection and try again.',
    );
  }
}

String _storageMessage(StorageException e) {
  final code = e.statusCode;
  final msg = e.message.toLowerCase();
  if (code == '413' || msg.contains('exceeded') || msg.contains('too large')) {
    return 'That file is too large. The maximum size is 50MB.';
  }
  if (code == '415' || msg.contains('mime')) {
    return 'That file type is not supported.';
  }
  if (code == '401' || code == '403' || msg.contains('row-level security')) {
    return 'You do not have permission to upload. Please log in again.';
  }
  if (code == '404' || msg.contains('bucket not found')) {
    return 'File storage is not set up yet. Please contact support.';
  }
  return 'The upload failed. Please try again.';
}

/// The logged-in user's files, newest first. Survives logout/login because
/// it is read from the database, filtered by RLS to the user's own rows.
Future<List<StoredFile>> listMyFiles(AuthState auth) async {
  final s = _session(auth);
  try {
    final rows = await s.client
        .from(_table)
        .select()
        .eq('owner_id', s.userId)
        .order('created_at', ascending: false);
    return [for (final r in rows) StoredFile.fromMap(r)];
  } on PostgrestException {
    throw const UploadFailure('Could not load your files. Try again.');
  } catch (_) {
    throw const UploadFailure(
      'Could not reach the server. Check your connection and try again.',
    );
  }
}

/// Temporary (1 hour) link to open or download a stored file. With
/// [download] the link makes the browser save the file under its name instead
/// of showing it.
Future<String> fileUrl(
  AuthState auth,
  StoredFile file, {
  bool download = false,
}) =>
    _signedUrl(auth, file.storagePath, file.name, download);

Future<String> _signedUrl(
  AuthState auth,
  String path,
  String downloadName,
  bool download,
) async {
  final s = _session(auth);
  try {
    final url =
        await s.client.storage.from(kFilesBucket).createSignedUrl(path, 3600);
    if (!download) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}download=${Uri.encodeComponent(downloadName)}';
  } on StorageException {
    throw const UploadFailure('Could not open the file. Try again.');
  } catch (_) {
    throw const UploadFailure(
      'Could not reach the server. Check your connection and try again.',
    );
  }
}

const _networkMessage =
    'Could not reach the server. Check your connection and try again.';

/// The user's favorite files, newest first (same rows as My Portfolio).
Future<List<StoredFile>> listMyFavorites(AuthState auth) async {
  final s = _session(auth);
  try {
    final rows = await s.client
        .from(_table)
        .select()
        .eq('owner_id', s.userId)
        .eq('is_favorite', true)
        .order('created_at', ascending: false);
    return [for (final r in rows) StoredFile.fromMap(r)];
  } on PostgrestException {
    throw const UploadFailure('Could not load your favorites. Try again.');
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Message for a failed favorite update. The Postgres error code tells the
/// real cause apart (and it is printed to the debug console), instead of one
/// vague message for everything.
String _favoriteMessage(PostgrestException e, bool adding) {
  debugPrint('Favorite update failed: code=${e.code} message=${e.message}');
  final code = e.code ?? '';
  final msg = e.message.toLowerCase();
  if (code == 'PGRST204' ||
      code == '42703' ||
      (msg.contains('is_favorite') && msg.contains('column'))) {
    return 'Favorites are not set up in the database yet. Run '
        'supabase/favorites_fix.sql in this Supabase project.';
  }
  if (code == '42501' || msg.contains('permission denied')) {
    return 'The database refused to save the favorite (permission). Run '
        'supabase/favorites_fix.sql in this Supabase project.';
  }
  return adding
      ? 'Could not add the file to your favorites. Try again.'
      : 'Could not remove the file from your favorites. Try again.';
}

/// Adds / removes [file] from the favorites. Returns the saved row.
Future<StoredFile> setFileFavorite(
  AuthState auth,
  StoredFile file,
  bool value,
) async {
  final s = _session(auth);
  try {
    final row = await s.client
        .from(_table)
        .update({'is_favorite': value})
        .eq('id', file.id)
        .eq('owner_id', s.userId)
        .select()
        .maybeSingle();
    if (row != null) return StoredFile.fromMap(row);

    // No row came back: either the file is gone, or the database silently
    // refused the update (no UPDATE policy). Tell the two apart.
    final still = await s.client
        .from(_table)
        .select('id')
        .eq('id', file.id)
        .maybeSingle();
    if (still == null) throw const UploadFailure('That file no longer exists.');
    debugPrint('Favorite update changed 0 rows: missing UPDATE policy?');
    throw const UploadFailure(
      'The database did not allow the change. Run '
      'supabase/favorites_fix.sql in this Supabase project.',
    );
  } on UploadFailure {
    rethrow;
  } on PostgrestException catch (e) {
    throw UploadFailure(_favoriteMessage(e, value));
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Makes [file] public (shown on the Community page) or private (only its
/// owner sees it). Returns the saved row.
Future<StoredFile> setFileVisibility(
  AuthState auth,
  StoredFile file,
  bool makePublic,
) async {
  final s = _session(auth);
  try {
    final row = await s.client
        .from(_table)
        .update({'visibility': makePublic ? 'public' : 'private'})
        .eq('id', file.id)
        .eq('owner_id', s.userId)
        .select()
        .maybeSingle();
    if (row != null) return StoredFile.fromMap(row);

    final still = await s.client
        .from(_table)
        .select('id')
        .eq('id', file.id)
        .maybeSingle();
    if (still == null) throw const UploadFailure('That file no longer exists.');
    debugPrint('Visibility update changed 0 rows: missing UPDATE policy/grant?');
    throw const UploadFailure(
      'The database did not allow the change. Run '
      'supabase/visibility_fix.sql in this Supabase project.',
    );
  } on UploadFailure {
    rethrow;
  } on PostgrestException catch (e) {
    debugPrint('Visibility update failed: ${e.code} ${e.message}');
    if (e.code == '42501' ||
        e.code == '403' ||
        e.message.contains('Only the name') ||
        e.message.contains('42501')) {
      throw const UploadFailure(
        'The database did not allow the change. Run '
        'supabase/visibility_fix.sql in this Supabase project.',
      );
    }
    if (e.code == '23514') {
      throw const UploadFailure(
        'The database only accepts certain visibility values. '
        'Run supabase/visibility_fix.sql in this Supabase project.',
      );
    }
    // Unknown problem: show the database's own words so it can be fixed.
    final code = (e.code ?? '').isEmpty ? '' : '[${e.code}] ';
    throw UploadFailure(
      '${makePublic ? 'Could not make the file public' : 'Could not make the file private'}: '
      '$code${e.message}',
    );
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Ids of the files that already have a backup. Empty when it can't be read
/// (the backup action itself reports the problem when the user tries it).
Future<Set<String>> listBackedUpFileIds(AuthState auth) async {
  try {
    final s = _session(auth);
    final rows = await s.client
        .from(_backupsTable)
        .select('file_id')
        .eq('owner_id', s.userId);
    return {
      for (final r in rows)
        if (r['file_id'] != null) r['file_id'] as String,
    };
  } catch (_) {
    return <String>{};
  }
}

/// The user's backups, newest first.
Future<List<StoredBackup>> listMyBackups(AuthState auth) async {
  final s = _session(auth);
  try {
    final rows = await s.client
        .from(_backupsTable)
        .select()
        .eq('owner_id', s.userId)
        .order('created_at', ascending: false);
    return [for (final r in rows) StoredBackup.fromMap(r)];
  } on PostgrestException {
    throw const UploadFailure('Could not load your backups. Try again.');
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Name of the Edge Function (supabase/functions/manage-backups) that creates
/// and restores backups. Backup objects can only be touched with the
/// service role, so the app never reads, signs or copies them itself.
const _backupFunction = 'manage-backups';

/// Short text of what went wrong, safe to show: the failing step and the
/// Supabase message/code reported by the function (never a key).
String _clip(String v, [int max = 280]) =>
    v.length > max ? '${v.substring(0, max)}...' : v;

String _withDetail(String base, {String? step, String? detail, Object? code}) {
  final parts = <String>[
    if (step != null && step.isNotEmpty) step,
    if (detail != null && detail.isNotEmpty) detail,
    if (code != null && '$code'.isNotEmpty) 'code $code',
  ];
  return parts.isEmpty ? base : _clip('$base (${parts.join(' - ')})');
}

/// Calls the backup function and returns its JSON answer. Failures become
/// an [UploadFailure] whose message names the step
/// that failed and the underlying error, and is also printed to the console.
Future<Map<String, dynamic>> _callBackupFunction(
  SupabaseClient client,
  Map<String, dynamic> body, {
  required String fallback,
}) async {
  final action = body['action'];
  try {
    // Send the live session token explicitly, so the function always knows
    // which user (and therefore which project's data) the call is for.
    final token = client.auth.currentSession?.accessToken;
    if (token == null) {
      throw const UploadFailure('Your session has expired. Please log in again.');
    }
    final res = await client.functions.invoke(
      _backupFunction,
      body: body,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    debugPrint('manage-backups $action: unexpected answer: $data');
    throw UploadFailure(_withDetail(
      fallback,
      step: 'unexpected answer from manage-backups',
      detail: '${data.runtimeType}',
    ));
  } on FunctionException catch (e) {
    final d = e.details;
    final map = d is Map ? d : const <dynamic, dynamic>{};
    final code = map['error'] as String?;
    final step = map['step'] as String?;
    final detail = (map['detail'] ?? (d is String ? d : map['message']))
        ?.toString();
    final dbCode = map['code'];
    // Visible in the browser console / flutter run output.
    debugPrint('manage-backups $action failed: status=${e.status} '
        'error=$code step=$step detail=$detail code=$dbCode raw=$d');
    switch (code) {
      case 'backup_not_found':
        throw const UploadFailure('That backup no longer exists.');
    }
    if (e.status == 404 && code == null) {
      throw UploadFailure(_withDetail(
        'The manage-backups function was not found in this Supabase '
        'project. Deploy it there',
        detail: _clip('${detail ?? ''}', 120),
      ));
    }
    if (e.status == 401) {
      throw UploadFailure(_withDetail(
        'The server rejected your login',
        step: step,
        detail: detail,
      ));
    }
    final base = switch (code) {
      'file_not_found' => 'The original file could not be found',
      'storage_missing' => 'The stored copy of this backup could not be found',
      _ => fallback.replaceFirst(RegExp(r'\.?\s*Try again\.?$'), ''),
    };
    throw UploadFailure(_withDetail(base, step: step, detail: detail, code: dbCode));
  } on UploadFailure {
    rethrow;
  } catch (e) {
    // Not an answer of the function: the request itself failed (network,
    // CORS, function missing/unreachable) or the app could not read it.
    debugPrint('manage-backups $action request failed: ${e.runtimeType}: $e');
    throw UploadFailure(_withDetail(
      _networkMessage.replaceFirst(RegExp(r' Check your connection.*$'), ''),
      step: 'calling manage-backups',
      detail: '${e.runtimeType}: $e',
    ));
  }
}

/// Makes a real copy of [file] in Storage (`<role>/<user id>/backups/...`,
/// the original stays untouched) and saves its metadata linked to the file.
/// A file can have any number of backups: every call makes a new, separate
/// one (own id, timestamp and Storage object); older ones are never touched.
/// Done by the server (it also removes the copy again if the row can't be
/// saved), because clients have no access to the backup folder.
Future<StoredBackup?> backupMyFile(AuthState auth, StoredFile file) async {
  final s = _session(auth);
  final data = await _callBackupFunction(
    s.client,
    {'action': 'backup', 'file_id': file.id},
    fallback: 'Could not create the backup. Try again.',
  );
  final row = data['backup'];
  if (row is! Map) {
    throw UploadFailure(_withDetail(
      'Could not create the backup',
      step: 'unexpected answer from manage-backups',
      detail: 'no backup row in the answer',
    ));
  }
  try {
    return StoredBackup.fromMap(Map<String, dynamic>.from(row));
  } catch (e) {
    // The backup exists (the server saved it); only reading its row here
    // failed. Do not report a failure for that: the Backups page loads it.
    debugPrint('Backup created, but its row could not be read: $e');
    return null;
  }
}

/// Permanently deletes ONE backup: its Storage object and its row, both done
/// by the server after checking that the backup belongs to the logged-in user.
/// Other backups and the original file are not affected.
Future<void> deleteMyBackup(AuthState auth, StoredBackup backup) async {
  final s = _session(auth);
  final data = await _callBackupFunction(
    s.client,
    {'action': 'delete', 'backup_id': backup.id},
    fallback: 'Could not delete the backup. Try again.',
  );
  if (data['deleted'] != true) {
    throw UploadFailure(_withDetail(
      'Could not delete the backup',
      step: 'unexpected answer from manage-backups',
      detail: 'deletion was not confirmed',
    ));
  }
}

/// Restores [backup] into My Portfolio as a new active file: the server
/// copies the stored object to the normal file location and registers it in
/// `user_files` for the logged-in user, with the backup's name, type, size
/// and description. A name that is already taken gets " (restored)" added.
/// The backup itself is not changed. Returns the new file.
Future<StoredFile> restoreMyBackup(AuthState auth, StoredBackup backup) async {
  final s = _session(auth);
  final data = await _callBackupFunction(
    s.client,
    {'action': 'restore', 'backup_id': backup.id},
    fallback: 'Could not restore the backup. Try again.',
  );
  final row = data['file'];
  if (row is! Map) {
    throw const UploadFailure('Could not restore the backup. Try again.');
  }
  return StoredFile.fromMap(Map<String, dynamic>.from(row));
}

/// True while an object can still be read (used to confirm a removal).
Future<bool> _objectExists(SupabaseClient client, String path) async {
  try {
    await client.storage.from(kFilesBucket).createSignedUrl(path, 10);
    return true;
  } on StorageException {
    return false;
  }
}

/// Permanently deletes [file]: its Storage object, then its metadata row.
/// Its backups are NOT touched: their Storage copies and rows stay (the
/// database sets their `file_id` to null), so they remain on the Backups
/// page.
///
/// Storage goes first on purpose: if the row can't be deleted afterwards the
/// file still shows up and "Delete" can simply be tried again (removing an
/// object that is already gone is fine). The row is never deleted while its
/// Storage object might still exist, so no orphan is left either way.
Future<void> deleteMyFile(AuthState auth, StoredFile file) async {
  final s = _session(auth);
  final storage = s.client.storage.from(kFilesBucket);
  try {
    final path = file.storagePath;
    final removed = await storage.remove([path]);
    final removedNames = {for (final o in removed) o.name};
    if (!removedNames.contains(path) && await _objectExists(s.client, path)) {
      throw const UploadFailure('Could not delete the file. Try again.');
    }

    // Also verifies that a row really went away (RLS hides foreign rows).
    final deleted = await s.client
        .from(_table)
        .delete()
        .eq('id', file.id)
        .eq('owner_id', s.userId)
        .select('id');
    if (deleted.isEmpty) {
      final still = await s.client
          .from(_table)
          .select('id')
          .eq('id', file.id)
          .maybeSingle();
      if (still != null) {
        throw const UploadFailure('Could not delete the file. Try again.');
      }
    }
  } on UploadFailure {
    rethrow;
  } on StorageException {
    throw const UploadFailure('Could not delete the file. Try again.');
  } on PostgrestException {
    throw const UploadFailure('Could not delete the file. Try again.');
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

// -----------------------------------------------------------------------------
// Portfolio folders (table `portfolio_folders`, supabase/portfolio_folders.sql)
// -----------------------------------------------------------------------------

/// Longest folder name accepted (keep in sync with the SQL check).
const int kMaxFolderNameLength = 60;

/// One row of the `portfolio_folders` table.
class StoredFolder {
  const StoredFolder({
    required this.id,
    required this.ownerId,
    required this.role,
    required this.name,
    required this.createdAt,
    this.parentId,
  });

  final String id;
  final String ownerId;
  final String role; // 'student' | 'instructor'
  final String name;
  final DateTime createdAt;
  final String? parentId; // enclosing folder; null = root of My Portfolio

  /// Same folder inside another folder (null = top level).
  StoredFolder withParent(String? value) => StoredFolder(
        id: id,
        ownerId: ownerId,
        role: role,
        name: name,
        createdAt: createdAt,
        parentId: value,
      );

  factory StoredFolder.fromMap(Map<String, dynamic> m) => StoredFolder(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        role: m['role'] as String,
        name: m['name'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        parentId: m['parent_id'] as String?,
      );
}

/// Trims the name and collapses runs of whitespace into one space.
String normalizeFolderName(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Error message when [name] (already normalized) can't be used, else null.
/// Duplicates are compared case-insensitively against [existing].
String? validateFolderName(String name, Iterable<String> existing) {
  if (name.isEmpty) return 'Please enter a folder name.';
  if (name.length > kMaxFolderNameLength) {
    return 'Folder names can be at most $kMaxFolderNameLength characters.';
  }
  final key = name.toLowerCase();
  if (existing.any((e) => e.trim().toLowerCase() == key)) {
    return 'A folder with this name already exists.';
  }
  return null;
}

const _folderSetupMessage = 'Nested folders are not set up in the database '
    'yet. Run supabase/folder_navigation.sql in this Supabase project.';

/// True when the folder columns (`parent_id` / `folder_id`) are missing.
bool _folderSetupMissing(PostgrestException e) {
  final code = e.code ?? '';
  final msg = e.message.toLowerCase();
  return (code == 'PGRST204' || code == '42703') &&
      (msg.contains('parent_id') || msg.contains('folder_id'));
}

String _folderMessage(PostgrestException e) {
  debugPrint('Folder request failed: code=${e.code} message=${e.message}');
  final code = e.code ?? '';
  final msg = e.message.toLowerCase();
  if (_folderSetupMissing(e)) return _folderSetupMessage;
  if (code == '23505') return 'A folder with this name already exists.';
  if (code == '23503') {
    return 'The folder you are in no longer exists. Go back and try again.';
  }
  if (code == '23514') return 'That folder name is not allowed.';
  if (code == '42P01' ||
      code == 'PGRST205' ||
      (msg.contains('portfolio_folders') &&
          (msg.contains('does not exist') || msg.contains('schema cache')))) {
    return 'Folders are not set up in the database yet. Run '
        'supabase/portfolio_folders.sql in this Supabase project.';
  }
  if (code == '42501' || msg.contains('row-level security')) {
    return 'The database refused to save the folder (permission). Run '
        'supabase/portfolio_folders.sql in this Supabase project.';
  }
  return 'Could not create the folder. Try again.';
}

/// The logged-in user's folders, newest first (RLS limits it to their own).
Future<List<StoredFolder>> listMyFolders(AuthState auth) async {
  final s = _session(auth);
  try {
    final rows = await s.client
        .from(_foldersTable)
        .select()
        .eq('owner_id', s.userId)
        .order('created_at', ascending: false);
    return [for (final r in rows) StoredFolder.fromMap(r)];
  } on PostgrestException catch (e) {
    debugPrint('Could not load folders: code=${e.code} message=${e.message}');
    throw const UploadFailure('Could not load your folders. Try again.');
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Creates a folder owned by the logged-in user, inside [parentId] (null =
/// top level). The name is validated again here; the database also enforces
/// it (unique per user within the same parent, ignoring case). Throws
/// [UploadFailure] with a message ready to show.
Future<StoredFolder> createMyFolder(
  AuthState auth,
  String rawName, {
  String? parentId,
}) async {
  final s = _session(auth);
  final name = normalizeFolderName(rawName);
  final problem = validateFolderName(name, const []);
  if (problem != null) throw UploadFailure(problem);
  try {
    final row = await s.client
        .from(_foldersTable)
        .insert({
          'owner_id': s.userId,
          'role': s.role.name,
          'name': name,
          if (parentId != null) 'parent_id': parentId,
        })
        .select()
        .single();
    return StoredFolder.fromMap(row);
  } on PostgrestException catch (e) {
    throw UploadFailure(_folderMessage(e));
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

// -----------------------------------------------------------------------------
// Folder actions: backup and delete (whole subtree)
// -----------------------------------------------------------------------------

/// [rootId] and every folder inside it, at any depth, in breadth-first order
/// (a folder always comes before the folders inside it).
List<String> folderSubtree(List<StoredFolder> all, String rootId) {
  final children = <String, List<String>>{};
  for (final f in all) {
    final p = f.parentId;
    if (p != null) (children[p] ??= <String>[]).add(f.id);
  }
  final order = <String>[rootId];
  final seen = <String>{rootId};
  for (var i = 0; i < order.length; i++) {
    for (final c in children[order[i]] ?? const <String>[]) {
      if (seen.add(c)) order.add(c); // `seen` also guards against cycles
    }
  }
  return order;
}

/// Every file inside [folder], including its subfolders (read fresh, so
/// files added from elsewhere are not missed).
Future<({List<String> folderIds, List<StoredFile> files})> _folderContents(
  AuthState auth,
  StoredFolder folder,
) async {
  final folders = await listMyFolders(auth);
  final ids = folderSubtree(folders, folder.id);
  final set = ids.toSet();
  final files = [
    for (final f in await listMyFiles(auth))
      if (f.folderId != null && set.contains(f.folderId)) f,
  ];
  return (folderIds: ids, files: files);
}

/// Backs up EVERY file inside [folder] (and its subfolders): each one gets its
/// own backup exactly like "Create Backup" on a single file. The backup
/// system stores files, not folders, so restoring puts the files back into
/// My Portfolio one by one. Returns the ids of the files that were backed up.
/// Throws [UploadFailure] (naming how far it got) if one of them fails.
Future<List<String>> backupMyFolder(AuthState auth, StoredFolder folder) async {
  final contents = await _folderContents(auth, folder);
  if (contents.files.isEmpty) {
    throw const UploadFailure('This folder has no files to back up.');
  }
  final done = <String>[];
  for (final file in contents.files) {
    try {
      await backupMyFile(auth, file);
      done.add(file.id);
    } on UploadFailure catch (e) {
      throw UploadFailure(
        '${done.length} of ${contents.files.length} files were backed up. '
        '${e.message}',
      );
    }
  }
  return done;
}

/// Permanently deletes [folder] and EVERYTHING inside it: all files (Storage
/// object + row, like [deleteMyFile]) and all subfolders at any depth.
/// The backups of the deleted files are NOT touched (they stay on the Backups
/// page).
///
/// Order matters and does not depend on how the database foreign keys are
/// set: first the files, then the folders from the deepest up to [folder], so
/// nothing is ever deleted while something still points at it. If it stops
/// half way, what is left is a normal, consistent folder, and "Delete" can
/// simply be tried again.
Future<({int files, int folders})> deleteMyFolder(
  AuthState auth,
  StoredFolder folder,
) async {
  final s = _session(auth);
  final contents = await _folderContents(auth, folder);

  for (final file in contents.files) {
    await deleteMyFile(auth, file);
  }

  try {
    for (final id in contents.folderIds.reversed) {
      final deleted = await s.client
          .from(_foldersTable)
          .delete()
          .eq('id', id)
          .eq('owner_id', s.userId)
          .select('id');
      if (deleted.isEmpty) {
        // Already gone, or the database silently refused (no DELETE policy).
        final still = await s.client
            .from(_foldersTable)
            .select('id')
            .eq('id', id)
            .maybeSingle();
        if (still != null) {
          debugPrint('Folder delete changed 0 rows: missing DELETE policy?');
          throw const UploadFailure(
            'The database did not allow deleting the folder. Run '
            'supabase/folder_delete.sql in this Supabase project.',
          );
        }
      }
    }
  } on UploadFailure {
    rethrow;
  } on PostgrestException catch (e) {
    debugPrint('Folder delete failed: code=${e.code} message=${e.message}');
    throw const UploadFailure('Could not delete the folder. Try again.');
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
  return (files: contents.files.length, folders: contents.folderIds.length - 1);
}

// -----------------------------------------------------------------------------
// Moving files and folders into folders (drag and drop inside My Portfolio)
// -----------------------------------------------------------------------------
const _moveSetupMessage = 'The database did not allow moving it. Run '
    'supabase/folder_move.sql in this Supabase project.';

String _moveMessage(PostgrestException e, {required bool folder}) {
  debugPrint('Move failed: code=${e.code} message=${e.message}');
  final code = e.code ?? '';
  final msg = e.message.toLowerCase();
  if (_folderSetupMissing(e)) return _folderSetupMessage;
  if (code == '23505') {
    return folder
        ? 'A folder with this name already exists in that folder.'
        : 'A file with this name already exists in that folder.';
  }
  if (code == '23503') {
    return 'That folder no longer exists. Go back and try again.';
  }
  if (code == '42501' ||
      msg.contains('permission denied') ||
      msg.contains('row-level security')) {
    return _moveSetupMessage;
  }
  return folder
      ? 'Could not move the folder. Try again.'
      : 'Could not move the file. Try again.';
}

/// Moves [file] into the folder [folderId] (null = root). Only the folder the
/// file belongs to changes: the stored object, name and backups stay as they
/// are. Returns the saved row.
Future<StoredFile> moveMyFile(
  AuthState auth,
  StoredFile file,
  String? folderId,
) async {
  final s = _session(auth);
  try {
    final row = await s.client
        .from(_table)
        .update({'folder_id': folderId})
        .eq('id', file.id)
        .eq('owner_id', s.userId)
        .select()
        .maybeSingle();
    if (row != null) return StoredFile.fromMap(row);

    // No row came back: the file is gone, or the database silently refused
    // the update (no UPDATE policy). Tell the two apart.
    final still = await s.client
        .from(_table)
        .select('id')
        .eq('id', file.id)
        .maybeSingle();
    if (still == null) throw const UploadFailure('That file no longer exists.');
    throw const UploadFailure(_moveSetupMessage);
  } on UploadFailure {
    rethrow;
  } on PostgrestException catch (e) {
    throw UploadFailure(_moveMessage(e, folder: false));
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Moves [folder] (with everything in it) into the folder [parentId]
/// (null = top level). A folder can never go into itself or into one of its
/// own subfolders. Returns the saved row.
Future<StoredFolder> moveMyFolder(
  AuthState auth,
  StoredFolder folder,
  String? parentId,
) async {
  final s = _session(auth);
  try {
    if (parentId != null) {
      final all = await listMyFolders(auth);
      if (folderSubtree(all, folder.id).contains(parentId)) {
        throw const UploadFailure('A folder can not be moved into itself.');
      }
    }
    final row = await s.client
        .from(_foldersTable)
        .update({'parent_id': parentId})
        .eq('id', folder.id)
        .eq('owner_id', s.userId)
        .select()
        .maybeSingle();
    if (row != null) return StoredFolder.fromMap(row);

    final still = await s.client
        .from(_foldersTable)
        .select('id')
        .eq('id', folder.id)
        .maybeSingle();
    if (still == null) {
      throw const UploadFailure('That folder no longer exists.');
    }
    throw const UploadFailure(_moveSetupMessage);
  } on UploadFailure {
    rethrow;
  } on PostgrestException catch (e) {
    throw UploadFailure(_moveMessage(e, folder: true));
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

// -----------------------------------------------------------------------------
// Renaming files and folders (More menu / hold menu in My Portfolio)
// -----------------------------------------------------------------------------

/// Longest file name WITHOUT its extension.
const int kMaxFileNameLength = 100;

/// Splits the name shown in the app into the part the user may edit and the
/// extension (with the dot, exactly as it is written, e.g. `.pdf`) that is
/// locked. A name without the file's extension has nothing locked.
({String base, String ext}) splitFileName(StoredFile file) {
  final suffix = '.${file.fileType}';
  final n = file.name;
  if (file.fileType.isNotEmpty &&
      n.length > suffix.length &&
      n.toLowerCase().endsWith(suffix.toLowerCase())) {
    final cut = n.length - suffix.length;
    return (base: n.substring(0, cut), ext: n.substring(cut));
  }
  return (base: n, ext: '');
}

/// Trims, collapses spaces, and drops an extension the user typed again by
/// hand (so `report.pdf` typed on a PDF does not become `report.pdf.pdf`).
String normalizeFileBaseName(String raw, [String ext = '']) {
  var text = normalizeFolderName(raw);
  if (ext.isNotEmpty && text.toLowerCase().endsWith(ext.toLowerCase())) {
    text = text.substring(0, text.length - ext.length).trim();
  }
  return text;
}

/// Error message when [base] (already normalized) can't be a file name, else
/// null. [existingNames] are full names (with extension) of the other files
/// in the same folder; they are compared ignoring case.
String? validateFileBaseName(
  String base, {
  Iterable<String> existingNames = const [],
  String ext = '',
}) {
  if (base.isEmpty) return 'File name cannot be empty.';
  if (RegExp(r'^\.+$').hasMatch(base)) return 'Please enter a real file name.';
  if (base.length > kMaxFileNameLength) {
    return 'File names can be at most $kMaxFileNameLength characters.';
  }
  if (RegExp(r'[\\/\u0000-\u001f]').hasMatch(base)) {
    return 'File names can not contain / or \\.';
  }
  final key = '$base$ext'.toLowerCase();
  if (existingNames.any((e) => e.trim().toLowerCase() == key)) {
    return 'A file with this name already exists in this folder.';
  }
  return null;
}

String _renameMessage(PostgrestException e, {required bool folder}) {
  debugPrint('Rename failed: code=${e.code} message=${e.message}');
  final code = e.code ?? '';
  final msg = e.message.toLowerCase();
  if (code == '23505') {
    return folder
        ? 'A folder with this name already exists.'
        : 'A file with this name already exists in this folder.';
  }
  if (code == '23514') {
    return folder
        ? 'That folder name is not allowed.'
        : 'That file name is not allowed.';
  }
  if (code == '42501' ||
      msg.contains('permission denied') ||
      msg.contains('row-level security')) {
    return _withDetail(
      folder ? _renameFolderSetupMessage : _renameFileSetupMessage,
      detail: e.message,
      code: e.code,
    );
  }
  // Any other database error: show what it was, so it can be fixed.
  return _withDetail(
    folder
        ? 'Could not rename the folder.'
        : 'Could not rename the file.',
    detail: e.message,
    code: e.code,
  );
}

const _renameFileSetupMessage = 'The database did not allow renaming the '
    'file. Run supabase/file_rename.sql in this Supabase project.';
const _renameFolderSetupMessage = 'The database did not allow renaming the '
    'folder (permission).';

/// Renames [file]. [rawBase] is the name WITHOUT the extension: the extension
/// of the current name is always kept, and an empty name is refused. Only the
/// name shown in the app changes (the stored object and its path stay).
/// Returns the saved row.
Future<StoredFile> renameMyFile(
  AuthState auth,
  StoredFile file,
  String rawBase,
) async {
  final s = _session(auth);
  final ext = splitFileName(file).ext;
  final base = normalizeFileBaseName(rawBase, ext);
  final problem = validateFileBaseName(base, ext: ext);
  if (problem != null) throw UploadFailure(problem);
  final newName = '$base$ext';
  if (newName == file.name) return file; // nothing to save

  try {
    final row = await s.client
        .from(_table)
        .update({'name': newName})
        .eq('id', file.id)
        .eq('owner_id', s.userId)
        .select()
        .maybeSingle();
    if (row != null) return StoredFile.fromMap(row);

    final still = await s.client
        .from(_table)
        .select('id')
        .eq('id', file.id)
        .maybeSingle();
    if (still == null) throw const UploadFailure('That file no longer exists.');
    throw const UploadFailure(_renameFileSetupMessage);
  } on UploadFailure {
    rethrow;
  } on PostgrestException catch (e) {
    throw UploadFailure(_renameMessage(e, folder: false));
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Renames [folder]. The name is validated again here (not empty, at most
/// [kMaxFolderNameLength] characters); the database also keeps names unique
/// inside the same parent folder. Returns the saved row.
Future<StoredFolder> renameMyFolder(
  AuthState auth,
  StoredFolder folder,
  String rawName,
) async {
  final s = _session(auth);
  final name = normalizeFolderName(rawName);
  final problem = validateFolderName(name, const []);
  if (problem != null) throw UploadFailure(problem);
  if (name == folder.name) return folder; // nothing to save

  try {
    final row = await s.client
        .from(_foldersTable)
        .update({'name': name})
        .eq('id', folder.id)
        .eq('owner_id', s.userId)
        .select()
        .maybeSingle();
    if (row != null) return StoredFolder.fromMap(row);

    final still = await s.client
        .from(_foldersTable)
        .select('id')
        .eq('id', folder.id)
        .maybeSingle();
    if (still == null) {
      throw const UploadFailure('That folder no longer exists.');
    }
    throw const UploadFailure(_renameFolderSetupMessage);
  } on UploadFailure {
    rethrow;
  } on PostgrestException catch (e) {
    throw UploadFailure(_renameMessage(e, folder: true));
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}
