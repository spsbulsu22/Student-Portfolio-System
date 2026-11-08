import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../utils/slide_route.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/status_dialog.dart';
import 'quick_upload_screen.dart';

const _navy = Color(0xFF0A2381);
const _starColor = Color(0xFFF59E0B);
const _deleteColor = Color(0xFFD93025);


enum PortfolioItemType { folder, pdf, docx }

/// One row in the portfolio list. Fill the list later from your backend.
class PortfolioItem {
  const PortfolioItem({
    required this.type,
    required this.label, // small line, e.g. "CPE 301L" / "PDF"
    required this.name, // big line, e.g. "Project 1: Digital Logic"
    this.sizeLabel, // e.g. "2.4 MB" (files only)
  });

  final PortfolioItemType type;
  final String label;
  final String name;
  final String? sizeLabel;
}

/// Width from which the desktop web layout is used (same as Home / Login).
const double kPortfolioWideBreakpoint = 600;

enum _Load { loading, ready, error }

/// What kind of file a stored file is (decides the icon, the filters and
/// whether it can be previewed in the browser).
enum _Kind {
  pdf,
  word,
  excel,
  powerpoint,
  text,
  image,
  video,
  audio,
  archive,
  other,
}

_Kind _kindOf(String ext) {
  switch (ext.toLowerCase()) {
    case 'pdf':
      return _Kind.pdf;
    case 'doc':
    case 'docx':
      return _Kind.word;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return _Kind.excel;
    case 'ppt':
    case 'pptx':
      return _Kind.powerpoint;
    case 'txt':
    case 'rtf':
      return _Kind.text;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
      return _Kind.image;
    case 'mp4':
    case 'mov':
    case 'webm':
      return _Kind.video;
    case 'mp3':
    case 'wav':
      return _Kind.audio;
    case 'zip':
      return _Kind.archive;
  }
  return _Kind.other;
}

IconData _iconForKind(_Kind k) {
  switch (k) {
    case _Kind.pdf:
      return Icons.description_outlined;
    case _Kind.word:
      return Icons.article_outlined;
    case _Kind.excel:
      return Icons.table_chart_outlined;
    case _Kind.powerpoint:
      return Icons.slideshow_outlined;
    case _Kind.text:
      return Icons.text_snippet_outlined;
    case _Kind.image:
      return Icons.image_outlined;
    case _Kind.video:
      return Icons.videocam_outlined;
    case _Kind.audio:
      return Icons.audiotrack_outlined;
    case _Kind.archive:
      return Icons.folder_zip_outlined;
    case _Kind.other:
      return Icons.insert_drive_file_outlined;
  }
}

/// Types a browser can show by itself: these open in a new tab, everything
/// else is downloaded.
const _previewable = {
  'pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp', //
  'mp4', 'webm', 'mp3', 'wav', 'txt',
};

String _fmtSize(int bytes) {
  // Decimal units (1 KB = 1000 B), same as Quick Upload / Upload Review.
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
  return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

// -----------------------------------------------------------------------------
// Shared with the Favorites and Backups pages
// -----------------------------------------------------------------------------
IconData portfolioIconForType(String ext) => _iconForKind(_kindOf(ext));
String portfolioFmtSize(int bytes) => _fmtSize(bytes);
String portfolioFmtDate(DateTime d) => _fmtDate(d);
bool portfolioCanPreview(String ext) =>
    _previewable.contains(ext.toLowerCase());

/// Floating message (does not change the page layout). Red for errors.
void showPortfolioMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? scheme.error : AppColors.menuButton,
        content: Text(
          message,
          style: TextStyle(color: error ? scheme.onError : Colors.white),
        ),
      ),
    );
}

/// Opens the link made by [makeUrl]: in a new browser tab when [inline],
/// otherwise as a download. Failures are shown as a message.
Future<void> openPortfolioUrl(
  BuildContext context,
  Future<String> Function() makeUrl, {
  required bool inline,
}) async {
  try {
    final url = await makeUrl();
    final ok = await launchUrl(
      Uri.parse(url),
      webOnlyWindowName: inline ? '_blank' : '_self',
    );
    if (!ok && context.mounted) {
      showPortfolioMessage(context, 'Could not open the file.', error: true);
    }
  } on UploadFailure catch (ex) {
    if (context.mounted) {
      showPortfolioMessage(context, ex.message, error: true);
    }
  } catch (_) {
    if (context.mounted) {
      showPortfolioMessage(context, 'Could not open the file.', error: true);
    }
  }
}

/// "Please wait" overlay (the same dialog as Logging in / out).
void _showBusyDialog(BuildContext context, String heading) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: StatusDialog(heading: heading, message: 'Please wait a moment.'),
    ),
  );
}

/// Asks before a file is deleted for good. Returns true on "Delete".
Future<bool> _confirmDelete(
  BuildContext context,
  String name, {
  required bool hasBackup,
  String? title, // default: "Delete this file?"
  String? message, // default: the single-file text
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 356),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title ?? 'Delete this file?',
                textAlign: TextAlign.center,
                style:
                    AppTheme.screenHeading.copyWith(color: AppColors.brandText),
              ),
              const SizedBox(height: 8),
              Text(
                message ??
                    '"$name" will be permanently deleted. Only the original '
                        'file is deleted'
                        '${hasBackup ? ': its backups are kept on the Backups page' : ''}'
                        '. This cannot be undone.',
                textAlign: TextAlign.center,
                style: AppTheme.body14,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.menuText,
                          side: const BorderSide(color: AppColors.menuDivider),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _deleteColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// One uploaded file as the page shows it (a row of the `user_files` table).
class _Entry {
  _Entry(StoredFile f, {this.backedUp = false})
      : file = f,
        kind = _kindOf(f.fileType);

  final StoredFile file;
  final _Kind kind;
  final bool backedUp; // the file already has a backup
  bool get isFavorite => file.isFavorite;
  bool get isPublic => file.isPublic;

  String get name => file.name;
  String get typeName => file.fileType.toUpperCase(); // "PDF", "DOCX"...
  String get uploadedLabel => 'Uploaded ${_fmtDate(file.createdAt)}';

  /// Small line: type and upload date.
  String get label => '$typeName  •  ${_fmtDate(file.createdAt)}';
  String? get sizeLabel => _fmtSize(file.sizeBytes);
  bool get canPreview => _previewable.contains(file.fileType.toLowerCase());
}

/// Figma frame: "2.1 My Portfolio" (student only).
///
/// Loads the logged-in user's files from Supabase (metadata from the
/// `user_files` table of the user's own project, the file itself from Storage
/// when it is opened) and hands them to the layout:
///  - narrower than 600px (phones, mobile web): the phone layout
///  - 600px or wider (desktop web): the desktop layout
class MyPortfolioScreen extends ConsumerStatefulWidget {
  const MyPortfolioScreen({super.key});

  @override
  ConsumerState<MyPortfolioScreen> createState() => _MyPortfolioScreenState();
}

/// What the file rows / cards can do (wired to the screen state below).
class _Actions {
  const _Actions({
    required this.open,
    required this.download,
    required this.favorite,
    required this.visibility,
    required this.backup,
    required this.delete,
    required this.backupFolder,
    required this.deleteFolder,
    required this.rename,
    required this.renameFolder,
    required this.mover,
  });

  final ValueChanged<_Entry> open;
  final ValueChanged<_Entry> download;
  final ValueChanged<_Entry> favorite; // toggles the star
  final ValueChanged<_Entry> visibility; // toggles Private / Public
  final ValueChanged<_Entry> backup;
  final ValueChanged<_Entry> delete;
  final ValueChanged<StoredFolder> backupFolder; // backs up everything inside
  final ValueChanged<StoredFolder> deleteFolder; // deletes it and its content
  final ValueChanged<_Entry> rename; // new name, extension stays
  final ValueChanged<StoredFolder> renameFolder;
  final _MoveController mover; // drag a file / folder into a folder
}

class _MyPortfolioScreenState extends ConsumerState<MyPortfolioScreen> {
  _Load _status = _Load.loading;
  List<_Entry> _items = const [];
  List<StoredFolder> _folders = const [];
  String _error = '';
  int _loadId = 0;
  bool _opening = false;
  final _busy = <String>{}; // ids of files with an action in progress
  String? _folderId; // folder being shown (null = root of My Portfolio)
  final _mover = _MoveController();

  @override
  void initState() {
    super.initState();
    _mover.onDrop = _moveInto;
    _load(showSpinner: false); // already starts in the loading state
  }

  @override
  void dispose() {
    _mover.dispose();
    super.dispose();
  }

  /// Reads the user's files. With [showSpinner] false (a refresh after
  /// uploading) the current list stays visible, and a failure keeps it.
  Future<void> _load({bool showSpinner = true}) async {
    final id = ++_loadId;
    if (showSpinner) setState(() => _status = _Load.loading);
    try {
      final auth = ref.read(authProvider);
      final filesFuture = listMyFiles(auth);
      final backedUpFuture = listBackedUpFileIds(auth); // never throws
      // Folders must never stop the files from showing: on failure keep
      // what is on screen (creating a folder reports the real problem).
      final foldersFuture =
          listMyFolders(auth).catchError((_) => _folders);
      final files = await filesFuture;
      final backedUp = await backedUpFuture;
      final folders = await foldersFuture;
      if (!mounted || id != _loadId) return;
      setState(() {
        _folders = folders;
        _items = [
          for (final f in files) _Entry(f, backedUp: backedUp.contains(f.id)),
        ];
        _status = _Load.ready;
        // The open folder is gone (e.g. removed elsewhere): back to root.
        if (_folderId != null && !folders.any((f) => f.id == _folderId)) {
          _folderId = null;
        }
      });
    } on UploadFailure catch (e) {
      _onLoadError(id, e.message, showSpinner);
    } catch (_) {
      _onLoadError(id, 'Could not load your files. Try again.', showSpinner);
    }
  }

  void _onLoadError(int id, String message, bool showSpinner) {
    if (!mounted || id != _loadId) return;
    if (!showSpinner && _status == _Load.ready) return; // keep the old list
    setState(() {
      _error = message;
      _status = _Load.error;
    });
  }

  /// Opens [e]: previewable types in a new browser tab, other types (and
  /// [download]) are downloaded.
  Future<void> _open(_Entry e, {required bool download}) async {
    if (_opening) return; // ignore double taps while the link is made
    _opening = true;
    try {
      final inline = !download && e.canPreview;
      final auth = ref.read(authProvider);
      await openPortfolioUrl(
        context,
        () => fileUrl(auth, e.file, download: !inline),
        inline: inline,
      );
    } finally {
      _opening = false;
    }
  }

  /// Floating message: does not change the page layout.
  void _showError(String message) {
    if (!mounted) return;
    showPortfolioMessage(context, message, error: true);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showPortfolioMessage(context, message);
  }

  /// Replaces the entry of file [id] (keeps the list order).
  void _replace(String id, _Entry Function(_Entry) change) {
    if (!mounted) return;
    setState(() {
      _items = [for (final i in _items) i.file.id == id ? change(i) : i];
    });
  }

  // ---------------------------------------------------------------- Favorite
  Future<void> _toggleFavorite(_Entry e) async {
    final id = e.file.id;
    if (!_busy.add(id)) return; // one action per file at a time
    final auth = ref.read(authProvider);
    final want = !e.file.isFavorite;
    // Instant feedback; undone below when saving fails.
    _replace(id, (x) => _Entry(x.file.withFavorite(want), backedUp: x.backedUp));
    try {
      final saved = await setFileFavorite(auth, e.file, want);
      _replace(id, (x) => _Entry(saved, backedUp: x.backedUp));
      _showInfo(want ? 'Added to favorites.' : 'Removed from favorites.');
    } on UploadFailure catch (ex) {
      _replace(
          id, (x) => _Entry(x.file.withFavorite(!want), backedUp: x.backedUp));
      _showError(ex.message);
    } catch (_) {
      _replace(
          id, (x) => _Entry(x.file.withFavorite(!want), backedUp: x.backedUp));
      _showError('Could not update your favorites. Try again.');
    } finally {
      _busy.remove(id);
    }
  }

  // -------------------------------------------------------------- Visibility
  /// Private <-> Public (files only; folders have no visibility).
  Future<void> _toggleVisibility(_Entry e) async {
    final id = e.file.id;
    if (!_busy.add(id)) return; // one action per file at a time
    final auth = ref.read(authProvider);
    final makePublic = !e.file.isPublic;
    final was = e.file.visibility;
    // Instant feedback; undone below when saving fails.
    _replace(
      id,
      (x) => _Entry(
        x.file.withVisibility(makePublic ? 'public' : 'private'),
        backedUp: x.backedUp,
      ),
    );
    try {
      final saved = await setFileVisibility(auth, e.file, makePublic);
      _replace(id, (x) => _Entry(saved, backedUp: x.backedUp));
      _showInfo(
        makePublic
            ? 'Now public. It shows on the Community page.'
            : 'Now private. Only you can see it.',
      );
    } on UploadFailure catch (ex) {
      _replace(
          id, (x) => _Entry(x.file.withVisibility(was), backedUp: x.backedUp));
      _showError(ex.message);
    } catch (_) {
      _replace(
          id, (x) => _Entry(x.file.withVisibility(was), backedUp: x.backedUp));
      _showError('Could not change the visibility. Try again.');
    } finally {
      _busy.remove(id);
    }
  }

  // ------------------------------------------------------------------ Backup
  Future<void> _backup(_Entry e) async {
    final id = e.file.id;
    if (!_busy.add(id)) return; // one action per file at a time
    final auth = ref.read(authProvider);
    final nav = Navigator.of(context, rootNavigator: true);
    _showBusyDialog(context, 'Creating backup...');
    try {
      await backupMyFile(auth, e.file);
      _replace(id, (x) => _Entry(x.file, backedUp: true));
      _showInfo('Backup created. Find it on the Backups page.');
    } on UploadFailure catch (ex) {
      _showError(ex.message);
    } catch (_) {
      _showError('Could not create the backup. Try again.');
    } finally {
      _busy.remove(id);
      if (nav.mounted) nav.pop(); // close the "Creating backup..." dialog
    }
  }

  // ------------------------------------------------------------------ Delete
  Future<void> _delete(_Entry e) async {
    final id = e.file.id;
    if (_busy.contains(id)) return;
    final sure = await _confirmDelete(
      context,
      e.name,
      hasBackup: e.backedUp,
    );
    if (!sure || !mounted || !_busy.add(id)) return;
    final auth = ref.read(authProvider);
    final nav = Navigator.of(context, rootNavigator: true);
    _showBusyDialog(context, 'Deleting file...');
    try {
      await deleteMyFile(auth, e.file);
      if (mounted) {
        setState(() => _items = [
              for (final i in _items)
                if (i.file.id != id) i,
            ]);
      }
      _showInfo('File deleted.');
    } on UploadFailure catch (ex) {
      _showError(ex.message);
    } catch (_) {
      _showError('Could not delete the file. Try again.');
    } finally {
      _busy.remove(id);
      if (nav.mounted) nav.pop(); // close the "Deleting file..." dialog
    }
  }

  // ------------------------------------------------------- Folder: backup
  /// Backs up every file inside [f] (and its subfolders), one backup per file.
  Future<void> _backupFolder(StoredFolder f) async {
    final key = 'folder:${f.id}';
    if (!_busy.add(key)) return;
    final auth = ref.read(authProvider);
    final nav = Navigator.of(context, rootNavigator: true);
    _showBusyDialog(context, 'Creating backup...');
    try {
      final done = await backupMyFolder(auth, f);
      final ids = done.toSet();
      if (mounted) {
        setState(() => _items = [
              for (final i in _items)
                ids.contains(i.file.id) ? _Entry(i.file, backedUp: true) : i,
            ]);
      }
      _showInfo(done.length == 1
          ? '1 file backed up. Find it on the Backups page.'
          : '${done.length} files backed up. Find them on the Backups page.');
    } on UploadFailure catch (ex) {
      _showError(ex.message);
      _load(showSpinner: false); // some files may have been backed up
    } catch (_) {
      _showError('Could not create the backup. Try again.');
      _load(showSpinner: false);
    } finally {
      _busy.remove(key);
      if (nav.mounted) nav.pop(); // close the "Creating backup..." dialog
    }
  }

  // ------------------------------------------------------- Folder: delete
  /// Deletes [f] and everything inside it (files and subfolders).
  Future<void> _deleteFolder(StoredFolder f) async {
    final key = 'folder:${f.id}';
    if (_busy.contains(key)) return;

    // What the user is about to lose (from what is on screen).
    final ids = folderSubtree(_folders, f.id).toSet();
    final inside = [
      for (final i in _items)
        if (i.file.folderId != null && ids.contains(i.file.folderId)) i,
    ];
    final subfolders = ids.length - 1;
    String count(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    final parts = [
      if (inside.isNotEmpty) count(inside.length, 'file'),
      if (subfolders > 0) count(subfolders, 'folder'),
    ];
    final backedUp = inside.any((i) => i.backedUp);
    final message = parts.isEmpty
        ? '"${f.name}" will be permanently deleted. This cannot be undone.'
        : '"${f.name}" and everything inside it (${parts.join(' and ')}) '
            'will be permanently deleted.'
            '${backedUp ? ' Backups of those files are kept on the Backups page.' : ''}'
            ' This cannot be undone.';

    final sure = await _confirmDelete(
      context,
      f.name,
      hasBackup: backedUp,
      title: 'Delete this folder?',
      message: message,
    );
    if (!sure || !mounted || !_busy.add(key)) return;

    final auth = ref.read(authProvider);
    final nav = Navigator.of(context, rootNavigator: true);
    _showBusyDialog(context, 'Deleting folder...');
    try {
      await deleteMyFolder(auth, f);
      if (mounted) {
        setState(() {
          _items = [
            for (final i in _items)
              if (!ids.contains(i.file.folderId)) i,
          ];
          _folders = [
            for (final x in _folders)
              if (!ids.contains(x.id)) x,
          ];
          if (_folderId != null && ids.contains(_folderId)) _folderId = null;
        });
      }
      _showInfo('Folder deleted.');
    } on UploadFailure catch (ex) {
      _showError(ex.message);
      _load(showSpinner: false); // part of it may already be gone
    } catch (_) {
      _showError('Could not delete the folder. Try again.');
      _load(showSpinner: false);
    } finally {
      _busy.remove(key);
      if (nav.mounted) nav.pop(); // close the "Deleting folder..." dialog
    }
  }

  // ----------------------------------------------------------------- Rename
  /// Asks for a new name. The extension is shown next to the box and can not
  /// be edited; an empty name is refused.
  Future<void> _renameFile(_Entry e) async {
    final auth = ref.read(authProvider);
    final parts = splitFileName(e.file);
    final siblings = [
      for (final i in _items)
        if (i.file.id != e.file.id && i.file.folderId == e.file.folderId)
          i.file.name,
    ];
    final saved = await _showRenameDialog<StoredFile>(
      context,
      title: 'Rename file',
      subtitle: parts.ext.isEmpty
          ? 'Enter a new name for this file.'
          : 'The file type (${parts.ext}) stays the same.',
      hint: 'File name',
      initial: parts.base,
      suffix: parts.ext,
      maxLength: kMaxFileNameLength,
      validate: (raw) => validateFileBaseName(
        normalizeFileBaseName(raw, parts.ext),
        existingNames: siblings,
        ext: parts.ext,
      ),
      onSave: (raw) => renameMyFile(auth, e.file, raw),
    );
    if (saved == null || !mounted) return;
    _replace(e.file.id, (x) => _Entry(saved, backedUp: x.backedUp));
    _showInfo('Renamed.');
  }

  Future<void> _renameFolder(StoredFolder f) async {
    final auth = ref.read(authProvider);
    final siblings = [
      for (final x in _folders)
        if (x.id != f.id && x.parentId == f.parentId) x.name,
    ];
    final saved = await _showRenameDialog<StoredFolder>(
      context,
      title: 'Rename folder',
      subtitle: 'Give this folder a new name.',
      hint: 'Folder name',
      initial: f.name,
      maxLength: kMaxFolderNameLength,
      validate: (raw) =>
          validateFolderName(normalizeFolderName(raw), siblings),
      onSave: (raw) => renameMyFolder(auth, f, raw),
    );
    if (saved == null || !mounted) return;
    _replaceFolder(saved);
    _showInfo('Renamed.');
  }

  // ------------------------------------------------------------------- Move
  /// A file or folder was dropped on [target] (>= 50% overlap).
  void _moveInto(Object payload, StoredFolder? target) {
    if (payload is _Entry) {
      _moveFile(payload, target);
    } else if (payload is StoredFolder) {
      _moveFolder(payload, target);
    }
  }

  Future<void> _moveFile(_Entry e, StoredFolder? target) async {
    final id = e.file.id;
    final targetName = target?.name ?? 'My Portfolio';
    if (e.file.folderId == target?.id) return; // already there
    if (!_busy.add(id)) return; // one action per file at a time
    final auth = ref.read(authProvider);
    final before = e.file;
    // Instant feedback (it leaves this folder); undone below on failure.
    _replace(
        id, (x) => _Entry(x.file.withFolder(target?.id), backedUp: x.backedUp));
    try {
      final saved = await moveMyFile(auth, before, target?.id);
      _replace(id, (x) => _Entry(saved, backedUp: x.backedUp));
      _showInfo('Moved to "$targetName".');
    } on UploadFailure catch (ex) {
      _replace(id, (x) => _Entry(before, backedUp: x.backedUp));
      _showError(ex.message);
    } catch (_) {
      _replace(id, (x) => _Entry(before, backedUp: x.backedUp));
      _showError('Could not move the file. Try again.');
    } finally {
      _busy.remove(id);
    }
  }

  void _replaceFolder(StoredFolder f) {
    if (!mounted) return;
    setState(() => _folders = [
          for (final x in _folders) x.id == f.id ? f : x,
        ]);
  }

  Future<void> _moveFolder(StoredFolder f, StoredFolder? target) async {
    final targetId = target?.id; // null = root of My Portfolio
    final targetName = target?.name ?? 'My Portfolio';
    if (f.id == targetId || f.parentId == targetId) return; // already there
    if (targetId != null && folderSubtree(_folders, f.id).contains(targetId)) {
      _showError('A folder can not be moved into itself.');
      return;
    }
    final key = 'folder:${f.id}';
    final clash = _folders.any((x) =>
        x.parentId == targetId &&
        x.id != f.id &&
        x.name.trim().toLowerCase() == f.name.trim().toLowerCase());
    if (clash) {
      _showError('"$targetName" already has a folder named "${f.name}".');
      return;
    }
    if (!_busy.add(key)) return;
    final auth = ref.read(authProvider);
    _replaceFolder(f.withParent(targetId)); // instant; undone on failure
    try {
      final saved = await moveMyFolder(auth, f, targetId);
      _replaceFolder(saved);
      _showInfo('Moved to "$targetName".');
    } on UploadFailure catch (ex) {
      _replaceFolder(f);
      _showError(ex.message);
    } catch (_) {
      _replaceFolder(f);
      _showError('Could not move the folder. Try again.');
    } finally {
      _busy.remove(key);
    }
  }

  // -------------------------------------------------------------- Navigation
  /// Folders from the root down to the open one (empty at the root).
  List<StoredFolder> get _path {
    final byId = {for (final f in _folders) f.id: f};
    final path = <StoredFolder>[];
    final seen = <String>{};
    var id = _folderId;
    while (id != null && seen.add(id)) {
      final f = byId[id];
      if (f == null) break;
      path.insert(0, f);
      id = f.parentId;
    }
    return path;
  }

  /// Opens folder [id]; null shows the root of My Portfolio.
  void _openFolder(String? id) {
    if (id == _folderId) return;
    setState(() => _folderId = id);
  }

  /// One level up (the system back button / Back do this inside a folder).
  void _goUp() {
    final path = _path;
    _openFolder(path.length > 1 ? path[path.length - 2].id : null);
  }

  /// Leaves My Portfolio altogether (from any depth).
  void _leave() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  // ----------------------------------------------------------- Create folder
  Future<void> _createFolder() async {
    final auth = ref.read(authProvider);
    final parentId = _folderId; // new folder goes into the open folder
    final folder = await _showCreateFolderDialog(
      context,
      existingNames: [
        for (final f in _folders)
          if (f.parentId == parentId) f.name,
      ],
      onCreate: (name) => createMyFolder(auth, name, parentId: parentId),
    );
    if (folder == null || !mounted) return;
    setState(() => _folders = [
          folder,
          for (final f in _folders)
            if (f.id != folder.id) f,
        ]);
    _showInfo('Folder created.');
  }

  @override
  Widget build(BuildContext context) {
    final actions = _Actions(
      open: (e) => _open(e, download: false),
      download: (e) => _open(e, download: true),
      favorite: _toggleFavorite,
      visibility: _toggleVisibility,
      backup: _backup,
      delete: _delete,
      backupFolder: _backupFolder,
      deleteFolder: _deleteFolder,
      rename: _renameFile,
      renameFolder: _renameFolder,
      mover: _mover,
    );
    final folderId = _folderId;
    final path = _path;
    final items = [
      for (final i in _items)
        if (i.file.folderId == folderId) i,
    ];
    final folders = [
      for (final f in _folders)
        if (f.parentId == folderId) f,
    ];
    return PopScope(
      canPop: folderId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp(); // inside a folder, back = parent folder
      },
      child: LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kPortfolioWideBreakpoint
          ? _MyPortfolioWeb(
              items: items,
              folders: folders,
              path: path,
              folderId: folderId,
              onOpenFolder: _openFolder,
              onGoUp: _goUp,
              onHome: _leave,
              onCreateFolder: _createFolder,
              status: _status,
              errorMessage: _error,
              onRetry: _load,
              onRefresh: () => _load(showSpinner: false),
              onOpen: (e) => _open(e, download: false),
              onDownload: (e) => _open(e, download: true),
              actions: actions,
            )
          : _MyPortfolioMobile(
              items: items,
              folders: folders,
              path: path,
              folderId: folderId,
              onOpenFolder: _openFolder,
              onGoUp: _goUp,
              onCreateFolder: _createFolder,
              status: _status,
              errorMessage: _error,
              onRetry: _load,
              onRefresh: () => _load(showSpinner: false),
              onOpen: (e) => _open(e, download: false),
              actions: actions,
            ),
      ),
    );
  }
}

// =============================================================================
// DESKTOP WEB LAYOUT (600px and wider)
// =============================================================================
enum _Filter { all, folder, images, pdf, docx, xlsx }

/// Desktop web layout of "2.1 My Portfolio" (used from 600px width).
///
/// Same structure as the Home / Quick Upload web screens: white top bar with
/// breadcrumb, blue gradient dashboard, then a summary row and a white
/// "files" card with a toolbar (search, filters, sort, list/grid) and a table.
class _MyPortfolioWeb extends StatefulWidget {
  const _MyPortfolioWeb({
    required this.items,
    required this.folders,
    required this.path,
    required this.folderId,
    required this.onOpenFolder,
    required this.onGoUp,
    required this.onHome,
    required this.onCreateFolder,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.onRefresh,
    required this.onOpen,
    required this.onDownload,
    required this.actions,
  });

  final List<_Entry> items; // files of the open folder
  final List<StoredFolder> folders; // subfolders of the open folder
  final List<StoredFolder> path; // root -> open folder (empty at the root)
  final String? folderId;
  final ValueChanged<String?> onOpenFolder;
  final VoidCallback onGoUp;
  final VoidCallback onHome;
  final VoidCallback onCreateFolder;
  final _Load status;
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;
  final ValueChanged<_Entry> onOpen;
  final ValueChanged<_Entry> onDownload;
  final _Actions actions;

  @override
  State<_MyPortfolioWeb> createState() => _MyPortfolioWebState();
}

class _MyPortfolioWebState extends State<_MyPortfolioWeb> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  bool _ascending = true;
  bool _grid = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    await Navigator.of(context).push(
      SlideFromRightRoute(page: QuickUploadScreen(folderId: widget.folderId)),
    );
    if (mounted) widget.onRefresh(); // pick up anything uploaded meanwhile
  }

  List<_Entry> _visible() {
    final q = _search.text.trim().toLowerCase();
    final list = widget.items.where((i) {
      final ext = i.file.fileType.toLowerCase();
      final okType = switch (_filter) {
        _Filter.all => true,
        _Filter.folder => false, // uploads are files, not folders
        _Filter.images => i.kind == _Kind.image,
        _Filter.pdf => i.kind == _Kind.pdf,
        _Filter.docx => i.kind == _Kind.word,
        _Filter.xlsx => ext == 'xls' || ext == 'xlsx',
      };
      final okQuery = q.isEmpty ||
          i.name.toLowerCase().contains(q) ||
          i.label.toLowerCase().contains(q);
      return okType && okQuery;
    }).toList();
    list.sort((a, b) => _ascending
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    return list;
  }

  /// Folders are shown under "All" and "Folders" only; the search matches
  /// their name. Same name sort as the files.
  List<StoredFolder> _visibleFolders() {
    if (_filter != _Filter.all && _filter != _Filter.folder) return const [];
    final q = _search.text.trim().toLowerCase();
    final list = widget.folders
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) => _ascending
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    return list;
  }

  int _count(_Kind k) => widget.items.where((i) => i.kind == k).length;

  @override
  Widget build(BuildContext context) {
    final shown = _visible();
    final shownFolders = _visibleFolders();
    final totalItems = widget.items.length + widget.folders.length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _WebTopBar(
              onBack: () => Navigator.of(context).maybePop(),
              onHome: widget.onHome,
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
                                  _PageHeader(
                                      onUpload: _upload,
                                      onCreateFolder: widget.onCreateFolder),
                                  const SizedBox(height: 20),
                                  // The page itself never scrolls: the
                                  // summary cards sit on the LEFT and only
                                  // the files list (right) scrolls.
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: c.maxWidth >= 900 ? 260 : 210,
                                          child: _StatsRow(
                                            total: totalItems,
                                            folders: widget.folders.length,
                                            pdfs: _count(_Kind.pdf),
                                            docs: _count(_Kind.word),
                                          ),
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: _FilesCard(
                                            search: _search,
                                            onSearchChanged: () =>
                                                setState(() {}),
                                            filter: _filter,
                                            onFilter: (f) =>
                                                setState(() => _filter = f),
                                            ascending: _ascending,
                                            onToggleSort: () => setState(
                                                () => _ascending = !_ascending),
                                            grid: _grid,
                                            onGrid: (g) =>
                                                setState(() => _grid = g),
                                            onUpload: _upload,
                                            totalCount: totalItems,
                                            path: widget.path,
                                            onOpenFolder: widget.onOpenFolder,
                                            onGoUp: widget.onGoUp,
                                            shown: shown,
                                            shownFolders: shownFolders,
                                            status: widget.status,
                                            errorMessage: widget.errorMessage,
                                            onRetry: widget.onRetry,
                                            onOpen: widget.onOpen,
                                            onDownload: widget.onDownload,
                                            actions: widget.actions,
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

// =============================================================================
// TOP BAR (same bar as the other web screens, with a breadcrumb)
// =============================================================================
class _WebTopBar extends StatelessWidget {
  const _WebTopBar({required this.onBack, required this.onHome});
  final VoidCallback onBack; // inside a folder this goes up one level
  final VoidCallback onHome;

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
                onTap: onHome,
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
                'My Portfolio',
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

// =============================================================================
// PAGE HEADER: title + Upload button
// =============================================================================
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onUpload, required this.onCreateFolder});
  final VoidCallback onUpload;
  final VoidCallback onCreateFolder;

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
              'My Portfolio',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your folders and files, all in one place.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CreateFolderButton(onTap: onCreateFolder),
            _UploadButton(onTap: onUpload),
          ],
        ),
      ],
    );
  }
}

class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: AppColors.inputFill,
        onTap: onTap,
        child: const SizedBox(
          height: 48,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.upload_rounded,
                    size: 22, color: AppColors.menuButton),
                SizedBox(width: 10),
                Text(
                  'Upload',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.menuButton,
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

/// Outlined twin of the Upload button (same size / shape).
class _CreateFolderButton extends StatelessWidget {
  const _CreateFolderButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withValues(alpha: 0.12),
        onTap: onTap,
        child: const SizedBox(
          height: 48,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.create_new_folder_outlined,
                    size: 22, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Create Folder',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

// =============================================================================
// SUMMARY CARDS
// =============================================================================
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.total,
    required this.folders,
    required this.pdfs,
    required this.docs,
  });

  final int total, folders, pdfs, docs;

  @override
  Widget build(BuildContext context) {
    // Stacked vertically (left column of the page).
    final cards = [
      _StatCard(
          icon: Icons.inventory_2_outlined, label: 'Total items', value: total),
      _StatCard(icon: Icons.folder_outlined, label: 'Folders', value: folders),
      _StatCard(
          icon: Icons.description_outlined, label: 'PDF files', value: pdfs),
      _StatCard(
          icon: Icons.article_outlined, label: 'Word documents', value: docs),
    ];
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          cards[i],
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 26, color: AppColors.homeIcon),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FILES CARD: toolbar + table / grid + footer
// =============================================================================
class _FilesCard extends StatelessWidget {
  const _FilesCard({
    required this.search,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilter,
    required this.ascending,
    required this.onToggleSort,
    required this.grid,
    required this.onGrid,
    required this.onUpload,
    required this.totalCount,
    required this.path,
    required this.onOpenFolder,
    required this.onGoUp,
    required this.shown,
    required this.shownFolders,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.onOpen,
    required this.onDownload,
    required this.actions,
  });

  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final bool ascending;
  final VoidCallback onToggleSort;
  final bool grid;
  final ValueChanged<bool> onGrid;
  final VoidCallback onUpload;
  final int totalCount;
  final List<StoredFolder> path;
  final ValueChanged<String?> onOpenFolder;
  final VoidCallback onGoUp;
  final List<_Entry> shown;
  final List<StoredFolder> shownFolders;
  final _Load status;
  final String errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<_Entry> onOpen;
  final ValueChanged<_Entry> onDownload;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
              child: _FolderCrumbs(
                path: path,
                onOpen: onOpenFolder,
                onUp: onGoUp,
                mover: actions.mover,
              ),
            ),
            const Divider(height: 1, color: AppColors.menuDivider),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: _Toolbar(
              search: search,
              onSearchChanged: onSearchChanged,
              filter: filter,
              onFilter: onFilter,
              ascending: ascending,
              onToggleSort: onToggleSort,
              grid: grid,
              onGrid: onGrid,
            ),
          ),
          const Divider(height: 1, color: AppColors.menuDivider),
          Expanded(
            child: status == _Load.loading
                ? const _LoadingState()
                : status == _Load.error
                    ? _EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not load your files',
                        message: errorMessage,
                        onRetry: onRetry,
                      )
                    : totalCount == 0
                        ? _EmptyState(
                            icon: Icons.folder_open_rounded,
                            title: path.isEmpty
                                ? 'Your portfolio is empty'
                                : 'This folder is empty',
                            message: path.isEmpty
                                ? 'Upload your first file to get started.'
                                : 'Upload a file or create a folder here.',
                            onUpload: onUpload,
                          )
                        : (shown.isEmpty && shownFolders.isEmpty)
                            ? const _EmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'No matching items',
                                message: 'Try a different search or filter.',
                              )
                            : _ScrollableItems(
                                shown: shown,
                                folders: shownFolders,
                                grid: grid,
                                totalCount: totalCount,
                                onOpenFolder: onOpenFolder,
                                onOpen: onOpen,
                                onDownload: onDownload,
                                actions: actions,
                              ),
          ),
        ],
      ),
    );
  }
}

/// The files area. Table header and footer stay fixed; only the rows scroll.
class _ScrollableItems extends StatefulWidget {
  const _ScrollableItems({
    required this.shown,
    required this.folders,
    required this.grid,
    required this.totalCount,
    required this.onOpenFolder,
    required this.onOpen,
    required this.onDownload,
    required this.actions,
  });

  final List<_Entry> shown;
  final List<StoredFolder> folders;
  final bool grid;
  final int totalCount;
  final ValueChanged<String?> onOpenFolder;
  final ValueChanged<_Entry> onOpen;
  final ValueChanged<_Entry> onDownload;
  final _Actions actions;

  @override
  State<_ScrollableItems> createState() => _ScrollableItemsState();
}

class _ScrollableItemsState extends State<_ScrollableItems> {
  final _scroll = ScrollController();
  final _viewKey = GlobalKey(); // the scrolling area (drag auto-scroll)

  @override
  void initState() {
    super.initState();
    widget.actions.mover.attachScroll(_viewKey, () => _scroll);
  }

  @override
  void dispose() {
    widget.actions.mover.detachScroll(_viewKey);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.shown;
    final folders = widget.folders;
    return LayoutBuilder(
      builder: (context, c) {
        final showType = c.maxWidth >= 760;
        return Column(
          children: [
            if (!widget.grid) _TableHeader(showType: showType),
            Expanded(
              child: KeyedSubtree(
                key: _viewKey,
                child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: widget.grid
                    ? SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(24),
                        child: SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final f in folders)
                                _FolderMovable(
                                  folder: f,
                                  actions: widget.actions,
                                  radius: 18,
                                  child: _FolderGridCard(
                                    folder: f,
                                    actions: widget.actions,
                                    onTap: () => widget.onOpenFolder(f.id),
                                  ),
                                ),
                              for (final i in shown)
                                _FileMovable(
                                  item: i,
                                  actions: widget.actions,
                                  child: _GridCard(
                                    item: i,
                                    onOpen: widget.onOpen,
                                    actions: widget.actions,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: folders.length + shown.length,
                        itemBuilder: (_, k) => k < folders.length
                            ? _FolderMovable(
                                folder: folders[k],
                                actions: widget.actions,
                                radius: 0,
                                child: _FolderRow(
                                  folder: folders[k],
                                  actions: widget.actions,
                                  showType: showType,
                                  onTap: () =>
                                      widget.onOpenFolder(folders[k].id),
                                ),
                              )
                            : _FileMovable(
                                item: shown[k - folders.length],
                                actions: widget.actions,
                                child: _FileRow(
                                  item: shown[k - folders.length],
                                  showType: showType,
                                  onOpen: widget.onOpen,
                                  onDownload: widget.onDownload,
                                  actions: widget.actions,
                                ),
                              ),
                      ),
              ),
              ),
            ),
            const Divider(height: 1, color: AppColors.menuDivider),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Showing ${shown.length + folders.length} of ${widget.totalCount} items',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.menuMuted,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilter,
    required this.ascending,
    required this.onToggleSort,
    required this.grid,
    required this.onGrid,
  });

  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final bool ascending;
  final VoidCallback onToggleSort;
  final bool grid;
  final ValueChanged<bool> onGrid;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
              color: Colors.black,
            ),
            decoration: InputDecoration(
              hintText: 'Search files',
              hintStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0x80000000),
              ),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 20, color: AppColors.menuMuted),
              filled: true,
              fillColor: AppColors.inputFill,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(50),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // Filters: 3 columns x 2 rows.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FilterChip(
                    label: 'All',
                    selected: filter == _Filter.all,
                    onTap: () => onFilter(_Filter.all)),
                const SizedBox(width: _filterGap),
                _FilterChip(
                    label: 'Folders',
                    selected: filter == _Filter.folder,
                    onTap: () => onFilter(_Filter.folder)),
                const SizedBox(width: _filterGap),
                _FilterChip(
                    label: 'Images',
                    selected: filter == _Filter.images,
                    onTap: () => onFilter(_Filter.images)),
              ],
            ),
            const SizedBox(height: _filterGap),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FilterChip(
                    label: 'PDF',
                    selected: filter == _Filter.pdf,
                    onTap: () => onFilter(_Filter.pdf)),
                const SizedBox(width: _filterGap),
                _FilterChip(
                    label: 'DOCX',
                    selected: filter == _Filter.docx,
                    onTap: () => onFilter(_Filter.docx)),
                const SizedBox(width: _filterGap),
                _FilterChip(
                    label: 'XLSX',
                    selected: filter == _Filter.xlsx,
                    onTap: () => onFilter(_Filter.xlsx)),
              ],
            ),
          ],
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: onToggleSort,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.menuText,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
              side: const BorderSide(color: AppColors.menuDivider),
            ),
          ),
          icon: Icon(
            ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 18,
          ),
          label: const Text(
            'Name',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.menuDivider),
            borderRadius: BorderRadius.circular(50),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ViewToggle(
                icon: Icons.view_list_rounded,
                tooltip: 'List view',
                selected: !grid,
                onTap: () => onGrid(false),
              ),
              _ViewToggle(
                icon: Icons.grid_view_rounded,
                tooltip: 'Grid view',
                selected: grid,
                onTap: () => onGrid(true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Same width for every filter chip, so the 3 columns line up.
const double _filterChipW = 96;
const double _filterGap = 8;

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.menuButton : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.menuButton : AppColors.menuDivider,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        hoverColor: selected ? Colors.transparent : AppColors.inputFill,
        onTap: onTap,
        child: Container(
          height: 44,
          width: _filterChipW,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.menuText,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? AppColors.inputFill : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon,
                size: 20,
                color: selected ? _navy : AppColors.menuMuted),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Table (list view)
// -----------------------------------------------------------------------------
const double _typeColW = 110;
const double _sizeColW = 90;
const double _starColW = 40;
const double _actionColW = 40;

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.showType});
  final bool showType;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: AppColors.menuMuted,
    );
    return Container(
      color: const Color(0xFFF6FAFF),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 54), // icon tile + gap
          const Expanded(child: Text('NAME', style: style)),
          if (showType)
            const SizedBox(width: _typeColW, child: Text('TYPE', style: style)),
          const SizedBox(width: _sizeColW, child: Text('SIZE', style: style)),
          const SizedBox(width: _starColW),
          const SizedBox(width: _actionColW),
        ],
      ),
    );
  }
}

enum _RowAction { open, download, rename, favorite, visibility, backup, delete }

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.item,
    required this.showType,
    required this.onOpen,
    required this.onDownload,
    required this.actions,
  });
  final _Entry item;
  final bool showType;
  final ValueChanged<_Entry> onOpen;
  final ValueChanged<_Entry> onDownload;
  final _Actions actions;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // Same hover / press feedback as a folder row: a Material + InkWell
    // (hover tint, ripple and pressed highlight), not a hand-made tint.
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => widget.onOpen(item),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.menuDivider)),
          ),
          child: Row(
            children: [
              _IconTile(kind: item.kind),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.menuText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.uploadedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.menuMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showType)
                SizedBox(
                  width: _typeColW,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _TypeBadge(label: item.typeName),
                  ),
                ),
              SizedBox(
                width: _sizeColW,
                child: Text(
                  item.sizeLabel ?? '—',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.menuText,
                  ),
                ),
              ),
              SizedBox(
                width: _starColW,
                child: _StarButton(
                  item: item,
                  onTap: () => widget.actions.favorite(item),
                ),
              ),
              SizedBox(
                width: _actionColW,
                child: _ItemMenu(item: item, actions: widget.actions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DRAG & MOVE inside My Portfolio (files and folders into folders)
// =============================================================================
/// How long a file / folder has to be held before it reacts (short on purpose;
/// the system default is 500 ms).
const Duration kFolderHold = Duration(milliseconds: 400);

/// The floating card that follows the finger / pointer while dragging.
const Size _kDragChipSize = Size(230, 60);

/// The card floats a little above the finger so the finger never hides it.
const Offset _kDragLift = Offset(0, -40);

/// Id of the drop zone of the root crumb ("My Portfolio").
const String _kRootZone = '__root__';

/// Drop rule: the dragged card must cover at least this share of the smaller
/// of (dragged card, folder) to count as "inside" that folder.
const double _kDropOverlap = 0.5;

/// Runs one drag at a time: tracks what is dragged, which folder it is over
/// (>= 50% overlap), draws the floating card, scrolls the list near its edges
/// and reports the drop. Lives in the screen state; the cards only register
/// themselves as drop zones / drag sources.
class _MoveController extends ChangeNotifier {
  /// Drop zones by id. [folder] is null for the root of My Portfolio (the
  /// first breadcrumb). [clip] limits the zone to what is really visible
  /// (breadcrumbs scrolled out of their row must not catch drops).
  final _zones =
      <String, ({GlobalKey key, StoredFolder? folder, GlobalKey? clip})>{};

  /// Called when something is released over a folder. [target] is null when
  /// it is released over the root crumb ("My Portfolio").
  void Function(Object payload, StoredFolder? target)? onDrop;

  String? dragId; // 'file:<id>' / 'folder:<id>' of the dragged card
  Object? payload; // the _Entry or StoredFolder being dragged
  String? hoverId; // id of the folder the card is over (>= 50%), if any

  bool get isDragging => payload != null;
  StoredFolder? get hoverFolder =>
      hoverId == null ? null : _zones[hoverId]?.folder;

  /// Name shown on the floating card ("My Portfolio" for the root crumb).
  String? get hoverName => hoverId == null
      ? null
      : (hoverId == _kRootZone ? 'My Portfolio' : hoverFolder?.name);

  Offset _pointer = Offset.zero;
  final _chipPos = ValueNotifier<Offset>(Offset.zero);
  OverlayEntry? _chip;
  Timer? _timer;

  GlobalKey? _viewportKey;
  ScrollController? Function()? _scrollOf;

  // --- drop zones (folder cards) ---------------------------------------------
  /// [f] null registers the root of My Portfolio.
  void registerZone(StoredFolder? f, GlobalKey key, {GlobalKey? clip}) =>
      _zones[f?.id ?? _kRootZone] = (key: key, folder: f, clip: clip);

  void unregisterZone(String id, GlobalKey key) {
    if (identical(_zones[id]?.key, key)) _zones.remove(id);
  }

  // --- auto scroll near the top / bottom edge of the list --------------------
  void attachScroll(GlobalKey viewport, ScrollController? Function() scrollOf) {
    _viewportKey = viewport;
    _scrollOf = scrollOf;
  }

  void detachScroll(GlobalKey viewport) {
    if (identical(_viewportKey, viewport)) {
      _viewportKey = null;
      _scrollOf = null;
    }
  }

  void _autoScroll() {
    final vk = _viewportKey;
    final sc = _scrollOf?.call();
    if (vk == null || sc == null || !sc.hasClients) return;
    final box = vk.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final r = box.localToGlobal(Offset.zero) & box.size;
    const zone = 72.0, fastest = 14.0;
    final dy = _pointer.dy;
    double v = 0;
    if (dy < r.top + zone) {
      v = -fastest * ((r.top + zone - dy) / zone).clamp(0.0, 1.0);
    } else if (dy > r.bottom - zone) {
      v = fastest * ((dy - (r.bottom - zone)) / zone).clamp(0.0, 1.0);
    }
    if (v == 0) return;
    final pos = sc.position;
    final next =
        (pos.pixels + v).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (next != pos.pixels) {
      sc.jumpTo(next.toDouble());
      _recompute(); // the folders moved under a still finger
    }
  }

  // --- the drag itself -------------------------------------------------------
  void begin(
    BuildContext context, {
    required String id,
    required Object data,
    required String title,
    required IconData icon,
    required Offset at,
  }) {
    if (isDragging) return;
    dragId = id;
    payload = data;
    hoverId = null;
    _pointer = at;
    _chipPos.value = at + _kDragLift;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    _chip = OverlayEntry(
      builder: (_) => ValueListenableBuilder<Offset>(
        valueListenable: _chipPos,
        builder: (_, p, __) {
          final local = overlayBox.globalToLocal(p);
          return Positioned(
            left: local.dx - _kDragChipSize.width / 2,
            top: local.dy - _kDragChipSize.height / 2,
            width: _kDragChipSize.width,
            height: _kDragChipSize.height,
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: this,
                builder: (_, __) => _DragChip(
                  title: title,
                  icon: icon,
                  target: hoverName,
                ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_chip!);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _autoScroll();
    });
    _recompute();
    notifyListeners();
  }

  void update(Offset at) {
    if (!isDragging) return;
    _pointer = at;
    _chipPos.value = at + _kDragLift;
    _recompute();
  }

  /// The folder with the biggest overlap (>= 50%), nearest centre on ties.
  void _recompute() {
    final center = _pointer + _kDragLift;
    final drag = Rect.fromCenter(
      center: center,
      width: _kDragChipSize.width,
      height: _kDragChipSize.height,
    );
    final dragArea = drag.width * drag.height;
    String? best;
    var bestDist = double.infinity;
    _zones.forEach((id, z) {
      if (dragId == 'folder:$id') return; // never into itself
      final box = z.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      var r = box.localToGlobal(Offset.zero) & box.size;
      final clipBox = z.clip?.currentContext?.findRenderObject();
      if (clipBox is RenderBox && clipBox.attached && clipBox.hasSize) {
        r = r.intersect(clipBox.localToGlobal(Offset.zero) & clipBox.size);
        if (r.width <= 0 || r.height <= 0) return; // scrolled out of view
      }
      final inter = r.intersect(drag);
      if (inter.width <= 0 || inter.height <= 0) return;
      final ratio = (inter.width * inter.height) /
          math.min(dragArea, r.width * r.height);
      if (ratio < _kDropOverlap) return;
      final dist = (r.center - center).distance;
      if (dist < bestDist) {
        best = id;
        bestDist = dist;
      }
    });
    if (best != hoverId) {
      hoverId = best;
      notifyListeners();
    }
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    _chip?.remove();
    _chip?.dispose();
    _chip = null;
    dragId = null;
    payload = null;
    hoverId = null;
    notifyListeners();
  }

  /// Finger / pointer released: drop onto the folder it is over, if any.
  void finish() {
    final data = payload;
    final over = hoverId;
    final hasZone = over != null && _zones.containsKey(over);
    final target = hasZone ? _zones[over]?.folder : null; // null = root
    _end();
    if (data != null && hasZone) onDrop?.call(data, target);
  }

  void cancel() {
    if (isDragging) _end();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chip?.remove();
    _chip?.dispose();
    _chip = null;
    _chipPos.dispose();
    super.dispose();
  }
}

/// The floating card shown while dragging.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.title, required this.icon, this.target});
  final String title;
  final IconData icon;
  final String? target; // name of the folder it would be moved into

  @override
  Widget build(BuildContext context) {
    final over = target != null;
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: const Color(0x66000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: over ? AppColors.primary : AppColors.menuDivider,
          width: over ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: _navy),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.menuText,
                    ),
                  ),
                  if (over)
                    Text(
                      'Move into "$target"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Makes a card draggable: hold for [kFolderHold], then drag.
///
///  - Folder ([onMenu] given): the hold opens the folder menu; as soon as the
///    finger moves, the menu disappears and the folder is dragged.
///  - File: same as a folder (its own menu); a card without [onMenu] is
///    picked up at once.
class _MoveGesture extends StatefulWidget {
  const _MoveGesture({
    super.key,
    required this.mover,
    required this.dragId,
    required this.payload,
    required this.title,
    required this.icon,
    required this.child,
    this.onMenu,
  });

  final _MoveController mover;
  final String dragId;
  final Object payload;
  final String title;
  final IconData icon;
  final Widget child;

  /// Opens the menu at the given point and returns a function that closes it.
  final VoidCallback Function(Offset at)? onMenu;

  @override
  State<_MoveGesture> createState() => _MoveGestureState();
}

class _MoveGestureState extends State<_MoveGesture> {
  static const double _moveSlop = 12; // px of movement that starts the drag

  VoidCallback? _closeMenu;
  Offset? _origin;
  bool _dragging = false;

  void _beginDrag(Offset at) {
    _dragging = true;
    widget.mover.begin(
      context,
      id: widget.dragId,
      data: widget.payload,
      title: widget.title,
      icon: widget.icon,
      at: at,
    );
  }

  void _onStart(LongPressStartDetails d) {
    if (widget.mover.isDragging) return;
    _origin = d.globalPosition;
    HapticFeedback.mediumImpact();
    final menu = widget.onMenu;
    if (menu != null) {
      _closeMenu = menu(d.globalPosition);
    } else {
      _beginDrag(d.globalPosition);
    }
  }

  void _onMove(LongPressMoveUpdateDetails d) {
    final origin = _origin;
    if (origin == null) return;
    if (!_dragging) {
      if ((d.globalPosition - origin).distance < _moveSlop) return;
      _closeMenu?.call(); // the menu disappears, the folder follows the finger
      _closeMenu = null;
      _beginDrag(d.globalPosition);
    }
    widget.mover.update(d.globalPosition);
  }

  void _onEnd(LongPressEndDetails d) {
    _origin = null;
    if (_dragging) {
      _dragging = false;
      widget.mover.finish();
    }
  }

  void _onCancel() {
    _origin = null;
    _closeMenu?.call();
    _closeMenu = null;
    if (_dragging) {
      _dragging = false;
      widget.mover.cancel();
    }
  }

  @override
  void dispose() {
    _closeMenu?.call();
    if (_dragging) {
      final mover = widget.mover;
      // Not while the tree is being torn down: notify after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => mover.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: kFolderHold),
          (r) => r
            ..onLongPressStart = _onStart
            ..onLongPressMoveUpdate = _onMove
            ..onLongPressEnd = _onEnd
            ..onLongPressCancel = _onCancel,
        ),
      },
      child: ListenableBuilder(
        listenable: widget.mover,
        // The card being dragged stays behind, faded.
        builder: (_, child) => Opacity(
          opacity: widget.mover.dragId == widget.dragId ? 0.35 : 1,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Makes a folder card a drop target and lights it up while the dragged card
/// covers at least half of it.
class _FolderZone extends StatefulWidget {
  const _FolderZone({
    required this.mover,
    required this.folder,
    required this.radius,
    required this.child,
    this.clip,
  });
  final _MoveController mover;
  final StoredFolder? folder; // null = root of My Portfolio (first crumb)
  final double radius;
  final Widget child;
  final GlobalKey? clip; // visible area of the zone (breadcrumb row)

  @override
  State<_FolderZone> createState() => _FolderZoneState();
}

class _FolderZoneState extends State<_FolderZone> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.mover.registerZone(widget.folder, _key, clip: widget.clip);
  }

  String get _zoneId => widget.folder?.id ?? _kRootZone;

  @override
  void didUpdateWidget(_FolderZone old) {
    super.didUpdateWidget(old);
    final oldId = old.folder?.id ?? _kRootZone;
    if (oldId != _zoneId) old.mover.unregisterZone(oldId, _key);
    widget.mover.registerZone(widget.folder, _key, clip: widget.clip);
  }

  @override
  void dispose() {
    widget.mover.unregisterZone(_zoneId, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: ListenableBuilder(
        listenable: widget.mover,
        builder: (_, child) {
          final on = widget.mover.hoverId == _zoneId;
          return DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              border: on ? Border.all(color: AppColors.primary, width: 3) : null,
              color: on ? AppColors.primary.withOpacity(0.14) : null,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A file card that can be held and dragged into a folder.
class _FileMovable extends StatelessWidget {
  const _FileMovable({
    required this.item,
    required this.actions,
    required this.child,
    this.showOpenItems = true, // Preview / Download (desktop only)
  });
  final _Entry item;
  final _Actions actions;
  final Widget child;
  final bool showOpenItems;

  @override
  Widget build(BuildContext context) {
    final id = 'file:${item.file.id}';
    return _MoveGesture(
      key: ValueKey(id),
      mover: actions.mover,
      dragId: id,
      payload: item,
      title: item.name,
      icon: _iconForKind(item.kind),
      onMenu: (at) => _openFileMenu(context, at, item, actions,
          showOpenItems: showOpenItems),
      child: child,
    );
  }
}

/// A folder card: tap opens it, hold opens its menu (Create Backup / Delete),
/// hold and drag moves it into another folder, and it accepts drops.
class _FolderMovable extends StatelessWidget {
  const _FolderMovable({
    required this.folder,
    required this.actions,
    required this.radius,
    required this.child,
  });
  final StoredFolder folder;
  final _Actions actions;
  final double radius; // corner radius of the card (for the highlight)
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = 'folder:${folder.id}';
    return _FolderZone(
      mover: actions.mover,
      folder: folder,
      radius: radius,
      child: _MoveGesture(
        key: ValueKey(id),
        mover: actions.mover,
        dragId: id,
        payload: folder,
        title: folder.name,
        icon: Icons.folder_rounded,
        onMenu: (at) => _openFolderMenu(context, at, folder, actions),
        child: child,
      ),
    );
  }
}

/// Opens the folder menu (Create Backup / Delete) at [at] and returns the
/// function that closes it again (used when the folder starts being dragged).
/// Folders cannot be favorited, so there is no star entry.
VoidCallback _openFolderMenu(
  BuildContext context,
  Offset at,
  StoredFolder folder,
  _Actions actions,
) =>
    _openHoldMenu(context, at, [
      _HoldItem('Rename', () => actions.renameFolder(folder)),
      _HoldItem('Create Backup', () => actions.backupFolder(folder)),
      _HoldItem('Delete', () => actions.deleteFolder(folder),
          color: _deleteColor),
    ]);

/// The hold menu of a file (same look and behaviour as the folder's): Preview
/// / Download (desktop only), Rename, Favorite, Make Public / Private, Backup
/// and Delete. Moving the finger
/// closes it and drags the file.
VoidCallback _openFileMenu(
  BuildContext context,
  Offset at,
  _Entry item,
  _Actions actions, {
  bool showOpenItems = true,
}) =>
    _openHoldMenu(context, at, [
      if (showOpenItems && item.canPreview)
        _HoldItem('Preview', () => actions.open(item)),
      if (showOpenItems) _HoldItem('Download', () => actions.download(item)),
      _HoldItem('Rename', () => actions.rename(item)),
      _HoldItem(
        item.isFavorite ? 'Remove from favorites' : 'Add to favorites',
        () => actions.favorite(item),
      ),
      _HoldItem(
        item.isPublic ? 'Make Private' : 'Make Public',
        () => actions.visibility(item),
      ),
      _HoldItem('Create Backup', () => actions.backup(item)),
      _HoldItem('Delete', () => actions.delete(item), color: _deleteColor),
    ]);

class _HoldItem {
  const _HoldItem(this.label, this.run, {this.color});
  final String label;
  final VoidCallback run;
  final Color? color;
}

/// Opens a small menu at [at] and returns the function that closes it again.
VoidCallback _openHoldMenu(
  BuildContext context,
  Offset at,
  List<_HoldItem> entries,
) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  var closed = false;

  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
    entry.dispose();
  }

  Widget tile(String label, VoidCallback run, {Color? color}) => InkWell(
        onTap: () {
          close();
          run();
        },
        child: Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _MenuLabel(label, color: color ?? AppColors.menuText),
        ),
      );

  entry = OverlayEntry(builder: (ctx) {
    const w = 200.0;
    final h = 48.0 * entries.length;
    final screen = MediaQuery.sizeOf(ctx);
    final left = at.dx.clamp(8.0, math.max(8.0, screen.width - w - 8)).toDouble();
    final top = at.dy.clamp(8.0, math.max(8.0, screen.height - h - 8)).toDouble();
    return Stack(
      children: [
        // Tapping anywhere else closes the menu.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
            onSecondaryTap: close,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: w,
          child: Material(
            color: Colors.white,
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in entries) tile(e.label, e.run, color: e.color),
              ],
            ),
          ),
        ),
      ],
    );
  });
  overlay.insert(entry);
  return close;
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text, {this.color = AppColors.menuText});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

/// Star that shows and toggles the favorite state of a file.
class _StarButton extends StatelessWidget {
  const _StarButton({required this.item, required this.onTap, this.size = 40});
  final _Entry item;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fav = item.isFavorite;
    return Tooltip(
      message: fav ? 'Remove from favorites' : 'Add to favorites',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            fav ? Icons.star_rounded : Icons.star_border_rounded,
            size: 22,
            color: fav ? _starColor : AppColors.menuMuted,
          ),
        ),
      ),
    );
  }
}

/// The "more" menu of a file: Preview / Download (desktop only), Rename,
/// Favorite, Make Public / Private, Backup and Delete.
class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.item,
    required this.actions,
    this.showOpenItems = true,
    this.size = 40,
  });
  final _Entry item;
  final _Actions actions;
  final bool showOpenItems;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: PopupMenuButton<_RowAction>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        color: Colors.white,
        icon: const Icon(Icons.more_vert_rounded,
            size: 22, color: AppColors.menuMuted),
        onSelected: (a) {
          switch (a) {
            case _RowAction.open:
              actions.open(item);
            case _RowAction.download:
              actions.download(item);
            case _RowAction.rename:
              actions.rename(item);
            case _RowAction.favorite:
              actions.favorite(item);
            case _RowAction.visibility:
              actions.visibility(item);
            case _RowAction.backup:
              actions.backup(item);
            case _RowAction.delete:
              actions.delete(item);
          }
        },
        itemBuilder: (_) => [
          if (showOpenItems && item.canPreview)
            const PopupMenuItem(
              value: _RowAction.open,
              child: _MenuLabel('Preview'),
            ),
          if (showOpenItems)
            const PopupMenuItem(
              value: _RowAction.download,
              child: _MenuLabel('Download'),
            ),
          const PopupMenuItem(
            value: _RowAction.rename,
            child: _MenuLabel('Rename'),
          ),
          PopupMenuItem(
            value: _RowAction.favorite,
            child: _MenuLabel(
              item.isFavorite ? 'Remove from favorites' : 'Add to favorites',
            ),
          ),
          PopupMenuItem(
            value: _RowAction.visibility,
            child: _MenuLabel(item.isPublic ? 'Make Private' : 'Make Public'),
          ),
          PopupMenuItem(
            value: _RowAction.backup,
            child: const _MenuLabel('Create Backup'),
          ),
          const PopupMenuItem(
            value: _RowAction.delete,
            child: _MenuLabel('Delete', color: _deleteColor),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.kind});
  final _Kind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_iconForKind(kind), size: 22, color: _navy),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.brandText,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Grid card (grid view)
// -----------------------------------------------------------------------------
class _GridCard extends StatefulWidget {
  const _GridCard({
    required this.item,
    required this.onOpen,
    required this.actions,
  });
  final _Entry item;
  final ValueChanged<_Entry> onOpen;
  final _Actions actions;

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // Same hover / press feedback as a folder card (Material + InkWell).
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.menuDivider),
        ),
        child: InkWell(
          onTap: () => widget.onOpen(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconTile(kind: item.kind),
                  const Spacer(),
                  _TypeBadge(label: item.typeName),
                  const SizedBox(width: 2),
                  _StarButton(
                    item: item,
                    size: 32,
                    onTap: () => widget.actions.favorite(item),
                  ),
                  _ItemMenu(item: item, actions: widget.actions, size: 32),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.menuText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.sizeLabel == null
                    ? item.label
                    : '${item.label}  •  ${item.sizeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.menuMuted,
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

// -----------------------------------------------------------------------------
// Empty states
// -----------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.onUpload,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onUpload;
  final VoidCallback? onRetry; // error state: "Try again" instead of Upload

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppColors.inputFill,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: AppColors.menuButton),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.menuText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.menuMuted,
              ),
            ),
            if (onUpload != null || onRetry != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 160,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onUpload ?? onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(
                    onUpload != null
                        ? Icons.upload_rounded
                        : Icons.refresh_rounded,
                    size: 20,
                  ),
                  label: Text(
                    onUpload != null ? 'Upload' : 'Try again',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown while the files are being loaded (same spinner as the dialogs).
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                  strokeWidth: 4, color: AppColors.primary),
            ),
            SizedBox(height: 20),
            Text(
              'Loading your files…',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.menuMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PHONE LAYOUT (narrower than 600px)
// =============================================================================
/// Phone layout of "2.1 My Portfolio" (used below 600px width).
///
/// Same look as Favorites (gradient header, light-blue cards), without the
/// star, plus an Upload button next to Home.
///
/// Search, type filter, name sort and list/grid view work exactly like the
/// desktop toolbar ([_MyPortfolioWebState]). The search field is always
/// visible; the sort button opens a bottom sheet with the filter, the sort
/// order and the view mode. The list and the grid both adapt to the choice.
class _MyPortfolioMobile extends StatefulWidget {
  const _MyPortfolioMobile({
    required this.items,
    required this.folders,
    required this.path,
    required this.folderId,
    required this.onOpenFolder,
    required this.onGoUp,
    required this.onCreateFolder,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.onRefresh,
    required this.onOpen,
    required this.actions,
  });

  final List<_Entry> items; // files of the open folder
  final List<StoredFolder> folders; // subfolders of the open folder
  final List<StoredFolder> path; // root -> open folder (empty at the root)
  final String? folderId;
  final ValueChanged<String?> onOpenFolder;
  final VoidCallback onGoUp;
  final VoidCallback onCreateFolder;
  final _Load status;
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;
  final ValueChanged<_Entry> onOpen;
  final _Actions actions;

  @override
  State<_MyPortfolioMobile> createState() => _MyPortfolioMobileState();
}

class _MyPortfolioMobileState extends State<_MyPortfolioMobile> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  bool _ascending = true;
  bool _grid = false;
  final _listScroll = ScrollController();
  final _gridScroll = ScrollController();
  final _viewKey = GlobalKey(); // the scrolling area (drag auto-scroll)

  @override
  void initState() {
    super.initState();
    widget.actions.mover
        .attachScroll(_viewKey, () => _grid ? _gridScroll : _listScroll);
  }

  @override
  void dispose() {
    widget.actions.mover.detachScroll(_viewKey);
    _listScroll.dispose();
    _gridScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  /// Anything other than the default view (used for the dot on the button).
  bool get _customView => _filter != _Filter.all || !_ascending || _grid;

  bool get _searchingOrFiltering => _query.isNotEmpty || _filter != _Filter.all;

  // Same rules as the desktop layout (_MyPortfolioWebState._visible).
  List<_Entry> _visibleFiles() {
    final q = _query;
    final list = widget.items.where((i) {
      final ext = i.file.fileType.toLowerCase();
      final okType = switch (_filter) {
        _Filter.all => true,
        _Filter.folder => false, // uploads are files, not folders
        _Filter.images => i.kind == _Kind.image,
        _Filter.pdf => i.kind == _Kind.pdf,
        _Filter.docx => i.kind == _Kind.word,
        _Filter.xlsx => ext == 'xls' || ext == 'xlsx',
      };
      final okQuery = q.isEmpty ||
          i.name.toLowerCase().contains(q) ||
          i.label.toLowerCase().contains(q);
      return okType && okQuery;
    }).toList();
    list.sort((a, b) => _ascending
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    return list;
  }

  /// Folders show under "All" and "Folders" only; the search matches their
  /// name. Same name sort as the files.
  List<StoredFolder> _visibleFolders() {
    if (_filter != _Filter.all && _filter != _Filter.folder) return const [];
    final q = _query;
    final list = widget.folders
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) => _ascending
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    return list;
  }

  void _clearAll() {
    setState(() {
      _search.clear();
      _filter = _Filter.all;
    });
  }

  Future<void> _openSortSheet() {
    FocusScope.of(context).unfocus();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheet) {
          // Changes apply to the page at once (and redraw the sheet).
          void apply(VoidCallback change) {
            setState(change);
            setSheet(() {});
          }

          return _SortSheet(
            filter: _filter,
            ascending: _ascending,
            grid: _grid,
            onFilter: (f) => apply(() => _filter = f),
            onAscending: (a) => apply(() => _ascending = a),
            onGrid: (g) => apply(() => _grid = g),
            onReset: () => apply(() {
              _filter = _Filter.all;
              _ascending = true;
              _grid = false;
            }),
            onDone: () => Navigator.of(sheetContext).pop(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    final topPad = inset.top + 12;
    final bottomPad = inset.bottom + 12;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final path = widget.path;
    final status = widget.status;
    final files = _visibleFiles();
    final folders = _visibleFolders();
    final hasAnything = widget.items.isNotEmpty || widget.folders.isNotEmpty;

    Widget body;
    if (status == _Load.loading) {
      body = const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
              strokeWidth: 4, color: AppColors.primary),
        ),
      );
    } else if (status == _Load.error) {
      body = _MobileEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load your files',
        message: widget.errorMessage,
        onRetry: widget.onRetry,
      );
    } else if (!hasAnything) {
      body = path.isEmpty
          ? const _MobileEmptyState()
          : const _MobileEmptyState(
              title: 'This folder is empty',
              message: 'Tap Upload or Create Folder to add something here.',
            );
    } else if (files.isEmpty && folders.isEmpty) {
      body = _MobileEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching items',
        message: _filter == _Filter.folder && _query.isEmpty
            ? 'There are no folders here yet.'
            : 'Try a different search or filter.',
        onRetry: _searchingOrFiltering ? _clearAll : null,
        actionLabel: 'Clear',
      );
    } else if (_grid) {
      body = LayoutBuilder(
        builder: (_, c) {
          // Auto-adjusts to the width: 2 columns on phones, more when wider.
          final columns = (c.maxWidth ~/ 180).clamp(2, 6).toInt();
          return GridView.builder(
            controller: _gridScroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 160,
            ),
            itemCount: folders.length + files.length,
            itemBuilder: (_, i) => i < folders.length
                ? _FolderMovable(
                    folder: folders[i],
                    actions: widget.actions,
                    radius: 22,
                    child: _MobileFolderGridCard(
                      folder: folders[i],
                      actions: widget.actions,
                      onTap: () => widget.onOpenFolder(folders[i].id),
                    ),
                  )
                : _FileMovable(
                    showOpenItems: false,
                    item: files[i - folders.length],
                    actions: widget.actions,
                    child: _MobileItemGridCard(
                      item: files[i - folders.length],
                      onTap: () => widget.onOpen(files[i - folders.length]),
                      actions: widget.actions,
                    ),
                  ),
          );
        },
      );
    } else {
      body = ListView.separated(
        controller: _listScroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        itemCount: folders.length + files.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => i < folders.length
            ? _FolderMovable(
                folder: folders[i],
                actions: widget.actions,
                radius: 25,
                child: _MobileFolderCard(
                  folder: folders[i],
                  actions: widget.actions,
                  onTap: () => widget.onOpenFolder(folders[i].id),
                ),
              )
            : _FileMovable(
                showOpenItems: false,
                item: files[i - folders.length],
                actions: widget.actions,
                child: _MobileItemCard(
                  item: files[i - folders.length],
                  onTap: () => widget.onOpen(files[i - folders.length]),
                  actions: widget.actions,
                ),
              ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _MobileHeader(
              topPad: topPad,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            if (path.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
                child: _FolderCrumbs(
                  path: path,
                  onOpen: widget.onOpenFolder,
                  onUp: widget.onGoUp,
                  mover: widget.actions.mover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _MobileSearchField(
                controller: _search,
                onChanged: () => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 16, right: 24),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.onCreateFolder,
                    style: TextButton.styleFrom(
                      foregroundColor: _navy,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.create_new_folder_outlined,
                        size: 24),
                    label: const Text(
                      'Create Folder',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: 'Filter and sort',
                    child: IconButton(
                      onPressed: _openSortSheet,
                      iconSize: 32,
                      constraints:
                          const BoxConstraints.tightFor(width: 48, height: 48),
                      padding: EdgeInsets.zero,
                      icon: Badge(
                        isLabelVisible: _customView,
                        smallSize: 10,
                        backgroundColor: AppColors.primary,
                        child: Transform.flip(
                          flipX: true,
                          child: const Icon(Icons.sort, color: _navy),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: KeyedSubtree(key: _viewKey, child: body)),
            // Hidden while the keyboard is up so the page never overflows.
            if (!keyboardOpen)
              Padding(
                padding: EdgeInsets.fromLTRB(36, 8, 36, 46 + bottomPad),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    PrimaryActionButton(
                      label: path.isEmpty ? 'Home' : 'Back',
                      width: 104,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    PrimaryActionButton(
                      label: 'Upload',
                      width: 120,
                      onPressed: () async {
                        await Navigator.of(context).push(
                          SlideFromRightRoute(
                              page: QuickUploadScreen(
                                  folderId: widget.folderId)),
                        );
                        widget.onRefresh(); // pick up anything uploaded
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Search box of the phone layout (same look as the desktop one, plus a
/// clear button while there is text).
class _MobileSearchField extends StatelessWidget {
  const _MobileSearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          hintText: 'Search files',
          hintStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0x80000000),
          ),
          prefixIcon: const Icon(Icons.search_rounded,
              size: 20, color: AppColors.menuMuted),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.menuMuted),
                  onPressed: () {
                    controller.clear();
                    onChanged();
                  },
                ),
          filled: true,
          fillColor: AppColors.inputFill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet behind the phone's sort button: what to show, the name order
/// and list / grid. Every tap applies at once; "Done" just closes it.
class _SortSheet extends StatelessWidget {
  const _SortSheet({
    required this.filter,
    required this.ascending,
    required this.grid,
    required this.onFilter,
    required this.onAscending,
    required this.onGrid,
    required this.onReset,
    required this.onDone,
  });

  final _Filter filter;
  final bool ascending;
  final bool grid;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<bool> onAscending;
  final ValueChanged<bool> onGrid;
  final VoidCallback onReset;
  final VoidCallback onDone;

  static const _filters = <(_Filter, String)>[
    (_Filter.all, 'All'),
    (_Filter.folder, 'Folders'),
    (_Filter.images, 'Images'),
    (_Filter.pdf, 'PDF'),
    (_Filter.docx, 'DOCX'),
    (_Filter.xlsx, 'XLSX'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + (bottom > 0 ? 0 : 8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filter & Sort',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.menuText,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onReset,
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.link,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _SheetLabel('Show'),
            LayoutBuilder(
              builder: (_, c) {
                const gap = 8.0;
                final w = (c.maxWidth - gap * 2) / 3; // 3 columns x 2 rows
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final f in _filters)
                      _SheetChip(
                        label: f.$2,
                        width: w,
                        selected: filter == f.$1,
                        onTap: () => onFilter(f.$1),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const _SheetLabel('Sort by name'),
            LayoutBuilder(
              builder: (_, c) {
                const gap = 8.0;
                final w = (c.maxWidth - gap) / 2;
                return Row(
                  children: [
                    _SheetChip(
                      label: 'Ascending',
                      icon: Icons.arrow_upward_rounded,
                      width: w,
                      selected: ascending,
                      onTap: () => onAscending(true),
                    ),
                    const SizedBox(width: gap),
                    _SheetChip(
                      label: 'Descending',
                      icon: Icons.arrow_downward_rounded,
                      width: w,
                      selected: !ascending,
                      onTap: () => onAscending(false),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const _SheetLabel('View'),
            LayoutBuilder(
              builder: (_, c) {
                const gap = 8.0;
                final w = (c.maxWidth - gap) / 2;
                return Row(
                  children: [
                    _SheetChip(
                      label: 'List',
                      icon: Icons.view_list_rounded,
                      width: w,
                      selected: !grid,
                      onTap: () => onGrid(false),
                    ),
                    const SizedBox(width: gap),
                    _SheetChip(
                      label: 'Grid',
                      icon: Icons.grid_view_rounded,
                      width: w,
                      selected: grid,
                      onTap: () => onGrid(true),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Center(
              child: PrimaryActionButton(
                label: 'Done',
                width: 160,
                onPressed: onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.menuMuted,
          ),
        ),
      );
}

/// Pill used inside the sort sheet (same look as the desktop filter chips,
/// but sized by the sheet so 3 / 2 columns always line up).
class _SheetChip extends StatelessWidget {
  const _SheetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.width,
    this.icon,
  });
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.menuText;
    return Material(
      color: selected ? AppColors.menuButton : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.menuButton : AppColors.menuDivider,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 44,
          width: width,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
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

/// Phone grid card of a file (used when the grid view is selected).
class _MobileItemGridCard extends StatelessWidget {
  const _MobileItemGridCard({
    required this.item,
    required this.onTap,
    required this.actions,
  });
  final _Entry item;
  final VoidCallback onTap;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_iconForKind(item.kind),
                        size: 22, color: _navy),
                  ),
                  const Spacer(),
                  _StarButton(
                    item: item,
                    size: 32,
                    onTap: () => actions.favorite(item),
                  ),
                  _ItemMenu(
                    item: item,
                    actions: actions,
                    showOpenItems: false,
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xBF000000),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  item.sizeLabel == null
                      ? item.label
                      : '${item.label}  •  ${item.sizeLabel}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.menuMuted,
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

/// Phone grid card of a folder (used when the grid view is selected).
class _MobileFolderGridCard extends StatelessWidget {
  const _MobileFolderGridCard({
    required this.folder,
    required this.onTap,
    required this.actions,
  });
  final StoredFolder folder;
  final VoidCallback onTap;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.folder_rounded,
                        size: 22, color: _navy),
                  ),
                  const Spacer(),
                  _FolderMenu(folder: folder, actions: actions, size: 32),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xBF000000),
                  ),
                ),
              ),
              Text(
                'FOLDER  •  ${_fmtDate(folder.createdAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.menuMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.topPad, required this.onBack});
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
            AppColors.instructorGradientStart,
            AppColors.instructorGradientEnd,
          ],
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
              onTap: onBack,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.chevron_left, size: 20, color: Colors.white),
              ),
            ),
          ),
          const Text(
            'My Portfolio',
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

class _MobileItemCard extends StatelessWidget {
  const _MobileItemCard({
    required this.item,
    required this.onTap,
    required this.actions,
  });
  final _Entry item;
  final VoidCallback onTap;
  final _Actions actions;

  IconData get _icon => _iconForKind(item.kind);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        borderRadius: BorderRadius.circular(25),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 86),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon, size: 24, color: _navy),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Opacity(
                    opacity: 0.7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 24 / 15,
                            color: Color(0xBF000000),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 24 / 20,
                            color: Color(0xBF000000),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (item.sizeLabel != null) ...[
                  const SizedBox(width: 16),
                  Opacity(
                    opacity: 0.5,
                    child: Text(
                      item.sizeLabel!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _navy,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                _StarButton(
                  item: item,
                  size: 36,
                  onTap: () => actions.favorite(item),
                ),
                _ItemMenu(
                  item: item,
                  actions: actions,
                  showOpenItems: false,
                  size: 36,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileEmptyState extends StatelessWidget {
  const _MobileEmptyState({
    this.icon = Icons.folder_open_rounded,
    this.title = 'Your portfolio is empty',
    this.message = 'Tap Upload to add your first file.',
    this.onRetry,
    this.actionLabel = 'Try again',
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry; // error state: "Try again" button
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.menuButton),
            const SizedBox(height: 16),
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
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              PrimaryActionButton(
                label: actionLabel,
                width: 140,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// FOLDERS (create dialog + how a folder is drawn on desktop / phone)
// =============================================================================
String _folderCreatedLabel(StoredFolder f) => 'Created ${_fmtDate(f.createdAt)}';

/// Asks for a folder name and creates it through [onCreate]. The dialog stays
/// open while saving and shows any problem under the field. Returns the new
/// folder, or null when cancelled.
Future<StoredFolder?> _showCreateFolderDialog(
  BuildContext context, {
  required List<String> existingNames,
  required Future<StoredFolder> Function(String name) onCreate,
}) =>
    showDialog<StoredFolder>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateFolderDialog(
        existingNames: existingNames,
        onCreate: onCreate,
      ),
    );

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog({
    required this.existingNames,
    required this.onCreate,
  });

  final List<String> existingNames;
  final Future<StoredFolder> Function(String name) onCreate;

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = normalizeFolderName(_controller.text);
    final problem = validateFolderName(name, widget.existingNames);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final folder = await widget.onCreate(name);
      if (mounted) Navigator.of(context).pop(folder);
    } on UploadFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not create the folder. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    const noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
      borderSide: BorderSide.none,
    );
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 356),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create folder',
                  textAlign: TextAlign.center,
                  style: AppTheme.screenHeading
                      .copyWith(color: AppColors.brandText),
                ),
                const SizedBox(height: 8),
                Text(
                  'Give your new folder a name.',
                  textAlign: TextAlign.center,
                  style: AppTheme.body14,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: kMaxFolderNameLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  style: AppTheme.fieldText,
                  decoration: InputDecoration(
                    hintText: 'Folder name',
                    hintStyle: AppTheme.fieldHint,
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    border: noBorder,
                    enabledBorder: noBorder,
                    disabledBorder: noBorder,
                    focusedBorder: noBorder,
                    errorText: _error,
                    errorMaxLines: 3,
                    errorStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: errorColor,
                    ),
                    errorBorder: noBorder,
                    focusedErrorBorder: noBorder,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.menuText,
                            side:
                                const BorderSide(color: AppColors.menuDivider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 3, color: Colors.white),
                                )
                              : const Text(
                                  'Create',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
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

enum _FolderAction { rename, backup, delete }

/// The "more" menu of a folder: Rename, Create Backup and Delete (the same
/// entries as its hold menu).
class _FolderMenu extends StatelessWidget {
  const _FolderMenu({
    required this.folder,
    required this.actions,
    this.size = 40,
  });
  final StoredFolder folder;
  final _Actions actions;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: PopupMenuButton<_FolderAction>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        color: Colors.white,
        icon: const Icon(Icons.more_vert_rounded,
            size: 22, color: AppColors.menuMuted),
        onSelected: (a) {
          switch (a) {
            case _FolderAction.rename:
              actions.renameFolder(folder);
            case _FolderAction.backup:
              actions.backupFolder(folder);
            case _FolderAction.delete:
              actions.deleteFolder(folder);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _FolderAction.rename,
            child: _MenuLabel('Rename'),
          ),
          PopupMenuItem(
            value: _FolderAction.backup,
            child: _MenuLabel('Create Backup'),
          ),
          PopupMenuItem(
            value: _FolderAction.delete,
            child: _MenuLabel('Delete', color: _deleteColor),
          ),
        ],
      ),
    );
  }
}

/// Asks for a new name (files and folders). [suffix] (a file's extension) is
/// shown after the box and can not be edited. The Rename button stays off
/// while the box is empty, and [validate] is checked again on submit.
Future<T?> _showRenameDialog<T>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String hint,
  required String initial,
  required int maxLength,
  required String? Function(String raw) validate,
  required Future<T> Function(String raw) onSave,
  String suffix = '',
}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RenameDialog<T>(
        title: title,
        subtitle: subtitle,
        hint: hint,
        initial: initial,
        maxLength: maxLength,
        suffix: suffix,
        validate: validate,
        onSave: onSave,
      ),
    );

class _RenameDialog<T> extends StatefulWidget {
  const _RenameDialog({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.initial,
    required this.maxLength,
    required this.suffix,
    required this.validate,
    required this.onSave,
  });

  final String title;
  final String subtitle;
  final String hint;
  final String initial;
  final int maxLength;
  final String suffix;
  final String? Function(String raw) validate;
  final Future<T> Function(String raw) onSave;

  @override
  State<_RenameDialog<T>> createState() => _RenameDialogState<T>();
}

class _RenameDialogState<T> extends State<_RenameDialog<T>> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  bool get _blank => _controller.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    // The whole name is selected, so typing replaces it.
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final problem = widget.validate(_controller.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.onSave(_controller.text);
      if (mounted) Navigator.of(context).pop(result);
    } on UploadFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not rename it. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    const noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
      borderSide: BorderSide.none,
    );
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 356),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppTheme.screenHeading
                      .copyWith(color: AppColors.brandText),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: AppTheme.body14,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: widget.maxLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => setState(() => _error = null),
                  style: AppTheme.fieldText,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: AppTheme.fieldHint,
                    counterText: '',
                    suffixText: widget.suffix.isEmpty ? null : widget.suffix,
                    suffixStyle: AppTheme.fieldText
                        .copyWith(color: AppColors.menuMuted),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    border: noBorder,
                    enabledBorder: noBorder,
                    disabledBorder: noBorder,
                    focusedBorder: noBorder,
                    errorText: _error,
                    errorMaxLines: 3,
                    errorStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: errorColor,
                    ),
                    errorBorder: noBorder,
                    focusedErrorBorder: noBorder,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.menuText,
                            side:
                                const BorderSide(color: AppColors.menuDivider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (_saving || _blank) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.inputFill,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 3, color: Colors.white),
                                )
                              : const Text(
                                  'Rename',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
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

/// Desktop list row of a folder (same columns as a file row).
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.showType,
    required this.onTap,
    required this.actions,
  });
  final StoredFolder folder;
  final bool showType;
  final VoidCallback onTap;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.menuDivider)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.folder_rounded, size: 22, color: _navy),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.menuText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _folderCreatedLabel(folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.menuMuted,
                  ),
                ),
              ],
            ),
          ),
          if (showType)
            const SizedBox(
              width: _typeColW,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _TypeBadge(label: 'FOLDER'),
              ),
            ),
          const SizedBox(
            width: _sizeColW,
            child: Text(
              '—',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.menuText,
              ),
            ),
          ),
          const SizedBox(width: _starColW),
          SizedBox(
            width: _actionColW,
            child: _FolderMenu(folder: folder, actions: actions),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

/// Desktop grid card of a folder.
class _FolderGridCard extends StatelessWidget {
  const _FolderGridCard({
    required this.folder,
    required this.onTap,
    required this.actions,
  });
  final StoredFolder folder;
  final VoidCallback onTap;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.menuDivider),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.folder_rounded, size: 22, color: _navy),
              ),
              const Spacer(),
              const _TypeBadge(label: 'FOLDER'),
              const SizedBox(width: 2),
              _FolderMenu(folder: folder, actions: actions, size: 32),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            folder.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.menuText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _folderCreatedLabel(folder),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.menuMuted,
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

/// Phone card of a folder (same look as a file card).
class _MobileFolderCard extends StatelessWidget {
  const _MobileFolderCard({
    required this.folder,
    required this.onTap,
    required this.actions,
  });
  final StoredFolder folder;
  final VoidCallback onTap;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        onTap: onTap,
        child: Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.folder_rounded, size: 24, color: _navy),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Opacity(
              opacity: 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FOLDER  •  ${_fmtDate(folder.createdAt)}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 24 / 15,
                      color: Color(0xBF000000),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    folder.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 24 / 20,
                      color: Color(0xBF000000),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _FolderMenu(folder: folder, actions: actions, size: 36),
        ],
      ),
        ),
      ),
    );
  }
}


// =============================================================================
// FOLDER BREADCRUMBS (shown only inside a folder; root view is unchanged)
// =============================================================================
/// Back button + "My Portfolio > Folder > Subfolder". Every crumb but the last
/// jumps to that level; the row scrolls sideways when the path is long and
/// always keeps the current folder in view. Touch targets are at least 48px.
class _FolderCrumbs extends StatefulWidget {
  const _FolderCrumbs({
    required this.path,
    required this.onOpen,
    required this.onUp,
    required this.mover,
  });

  final List<StoredFolder> path;
  final ValueChanged<String?> onOpen; // null = root
  final VoidCallback onUp;

  /// Every crumb except the current folder is a drop target: drop a file or
  /// folder on a crumb to move it out of the open folder, up to that level.
  final _MoveController mover;

  @override
  State<_FolderCrumbs> createState() => _FolderCrumbsState();
}

class _FolderCrumbsState extends State<_FolderCrumbs> {
  final _scroll = ScrollController();
  final _rowKey = GlobalKey(); // visible area of the crumbs (clips the zones)

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void didUpdateWidget(_FolderCrumbs old) {
    super.didUpdateWidget(old);
    _toEnd();
  }

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  /// [folder] null = the root crumb. The open folder (onTap null) is not a
  /// drop target: items are already inside it.
  Widget _crumb(String label, {VoidCallback? onTap, StoredFolder? folder}) {
    final current = onTap == null;
    final crumb = _crumbBody(label, onTap, current);
    if (current) return crumb;
    return _FolderZone(
      mover: widget.mover,
      folder: folder,
      radius: 10,
      clip: _rowKey,
      child: crumb,
    );
  }

  Widget _crumbBody(String label, VoidCallback? onTap, bool current) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, maxWidth: 260),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                color: current ? AppColors.menuText : _navy,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: widget.onUp,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.arrow_back_rounded, color: _navy),
        ),
        Expanded(
          child: KeyedSubtree(
            key: _rowKey,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _crumb(
                    'My Portfolio',
                    onTap: () => widget.onOpen(null),
                  ),
                  for (var i = 0; i < path.length; i++) ...[
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: AppColors.menuMuted),
                    _crumb(
                      path[i].name,
                      folder: path[i],
                      onTap: i == path.length - 1
                          ? null
                          : () => widget.onOpen(path[i].id),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
