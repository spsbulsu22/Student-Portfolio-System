import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/status_dialog.dart';
import 'my_portfolio_screen.dart'
    show
        kPortfolioWideBreakpoint,
        portfolioFmtDate,
        portfolioFmtSize,
        portfolioIconForType,
        showPortfolioMessage;

enum _BkLoad { loading, ready, error }

String _fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// One backup as the page shows it: a row of `file_backups` (a real copy of
/// an uploaded file, made from My Portfolio).
class BackupItem {
  BackupItem(this.backup);
  final StoredBackup backup;

  String get title => backup.name; // e.g. "Project 1.pdf"
  String get dateLabel => // e.g. "Oct 30, 2026 · 10:15 AM"
      '${portfolioFmtDate(backup.createdAt)} · ${_fmtTime(backup.createdAt)}';
  String get typeName => backup.fileType.toUpperCase(); // "PDF", "DOCX"...
  String get sizeLabel => portfolioFmtSize(backup.sizeBytes); // e.g. "2.4 MB"
  IconData get icon => portfolioIconForType(backup.fileType);
}

const _navy = Color(0xFF0A2381);
const _textDark = Color(0xFF273E58);
const _textMuted = Color(0xFF566D83);
const _deleteColor = Color(0xFFD93025);

/// Figma frame: "Backups" (student only).
///
/// Lists the backups made from My Portfolio (read from Supabase). A backup is
/// never opened, previewed or downloaded from here: "Restore" puts a copy of
/// it into My Portfolio as an active file, and that file can be opened there.
/// Backups stay listed after their original file is deleted. A file can have
/// many backups; each one can be restored or deleted on its own.
///
/// Responsive (same breakpoint as My Portfolio): narrower than
/// [kPortfolioWideBreakpoint] shows the original phone layout, wider shows
/// the desktop web layout.
class BackupsScreen extends ConsumerStatefulWidget {
  const BackupsScreen({super.key});

  @override
  ConsumerState<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends ConsumerState<BackupsScreen> {
  _BkLoad _status = _BkLoad.loading;
  List<BackupItem> _items = const [];
  String _error = '';
  int _loadId = 0;
  final _busy = <String>{}; // backups being restored or deleted

  @override
  void initState() {
    super.initState();
    _load(showSpinner: false); // already starts in the loading state
  }

  Future<void> _load({bool showSpinner = true}) async {
    final id = ++_loadId;
    if (showSpinner) setState(() => _status = _BkLoad.loading);
    try {
      final backups = await listMyBackups(ref.read(authProvider));
      if (!mounted || id != _loadId) return;
      setState(() {
        _items = [for (final b in backups) BackupItem(b)];
        _status = _BkLoad.ready;
      });
    } on UploadFailure catch (e) {
      _onLoadError(id, e.message);
    } catch (_) {
      _onLoadError(id, 'Could not load your backups. Try again.');
    }
  }

  void _onLoadError(int id, String message) {
    if (!mounted || id != _loadId) return;
    setState(() {
      _error = message;
      _status = _BkLoad.error;
    });
  }

  /// Restores [item] into My Portfolio as a new active file. The backup
  /// itself stays as it is. My Portfolio reads its list when it opens, so the
  /// restored file is there as soon as the user goes to that page.
  Future<void> _restore(BackupItem item) async {
    final id = item.backup.id;
    if (!_busy.add(id)) return; // ignore double taps
    final auth = ref.read(authProvider);
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: StatusDialog(
          heading: 'Restoring file...',
          message: 'Please wait a moment.',
        ),
      ),
    );
    String? error;
    StoredFile? restored;
    try {
      restored = await restoreMyBackup(auth, item.backup);
    } on UploadFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not restore the backup. Try again.';
    } finally {
      _busy.remove(id);
      if (nav.mounted) nav.pop(); // close the "Restoring file..." dialog
    }
    if (!mounted) return;
    if (restored != null) {
      showPortfolioMessage(
          context, 'Restored "${restored.name}" to My Portfolio.');
    } else {
      showPortfolioMessage(context, error!, error: true);
    }
  }

  /// Permanently deletes ONE backup (Storage object + row) after asking.
  /// Other backups and the original file are not affected.
  Future<void> _delete(BackupItem item) async {
    final id = item.backup.id;
    if (_busy.contains(id)) return;
    final sure = await _confirmDeleteBackup(context, item);
    if (!sure || !mounted || !_busy.add(id)) return;
    final auth = ref.read(authProvider);
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: StatusDialog(
          heading: 'Deleting backup...',
          message: 'Please wait a moment.',
        ),
      ),
    );
    String? error;
    var deleted = false;
    try {
      await deleteMyBackup(auth, item.backup);
      deleted = true;
    } on UploadFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not delete the backup. Try again.';
    } finally {
      _busy.remove(id);
      if (nav.mounted) nav.pop(); // close the "Deleting backup..." dialog
    }
    if (!mounted) return;
    if (deleted) {
      setState(() => _items = [
            for (final i in _items)
              if (i.backup.id != id) i,
          ]);
      showPortfolioMessage(context, 'Backup deleted.');
    } else {
      showPortfolioMessage(context, error!, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kPortfolioWideBreakpoint
          ? _BackupsWeb(
              items: _items,
              status: _status,
              errorMessage: _error,
              onRetry: _load,
              onRestore: _restore,
              onDelete: _delete,
            )
          : _BackupsMobile(
              items: _items,
              status: _status,
              errorMessage: _error,
              onRetry: _load,
              onRestore: _restore,
              onDelete: _delete,
            ),
    );
  }
}

/// Original phone layout (unchanged).
class _BackupsMobile extends StatelessWidget {
  const _BackupsMobile({
    required this.items,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.onRestore,
    required this.onDelete,
  });

  final List<BackupItem> items;
  final _BkLoad status;
  final String errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<BackupItem> onRestore;
  final ValueChanged<BackupItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    final topPad = inset.top + 12; // small margin above the header
    final bottomPad = inset.bottom + 12; // small margin below the Home button
    final count = status == _BkLoad.ready ? items.length : 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _Header(
              topPad: topPad,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            // Fixed (does not scroll): introduction + list summary
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Introduction
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your portfolio, saved',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 24 / 20,
                            color: _textDark,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Restore a saved version to My Portfolio to open '
                          'or download it.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 20 / 14,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // List summary
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Saved portfolios',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 20 / 14,
                            color: _textDark,
                          ),
                        ),
                        Text(
                          '$count ${count == 1 ? 'backup' : 'backups'}'
                          ' · Newest first',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 20 / 13,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Only the backup list scrolls
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (status == _BkLoad.loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                              strokeWidth: 4, color: AppColors.primary),
                        ),
                      ),
                    )
                  else if (status == _BkLoad.error)
                    _EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not load your backups',
                      message: errorMessage,
                      onRetry: onRetry,
                    )
                  else if (items.isEmpty)
                    const _EmptyState()
                  else
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _BackupCard(
                        item: items[i],
                        onRestore: onRestore,
                        onDelete: onDelete,
                      ),
                    ],
                ],
              ),
            ),
            // Home button: 104x48, 32 from the left and bottom
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(32, 8, 0, 32 + bottomPad),
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

/// Same header as My Portfolio / Favorites / Notifications / Profile.
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
            AppColors.instructorGradientEnd, // #004478
          ],
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
            'Backups',
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

class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.item,
    required this.onRestore,
    required this.onDelete,
  });
  final BackupItem item;
  final ValueChanged<BackupItem> onRestore;
  final ValueChanged<BackupItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputFill, // #D3E7FF
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Saved version: icon + title/date
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 24, color: _navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 22 / 18,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.dateLabel,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 18 / 13,
                        color: _textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${item.typeName}  ·  ${item.sizeLabel}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 18 / 13,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 10),
          // Actions: Delete | Restore (backups cannot be opened from here)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DeleteTextButton(onTap: () => onDelete(item)),
              PrimaryActionButton(
                label: 'Restore',
                width: 104,
                onPressed: () => onRestore(item),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown while there are no backups (not part of the Figma frame).
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.icon = Icons.history,
    this.title = 'No backups yet',
    this.message = 'Files you back up from My Portfolio will appear here.',
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry; // error state: "Try again" button

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
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
              label: 'Try again',
              width: 140,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}


// =============================================================================
// DESKTOP WEB LAYOUT (kPortfolioWideBreakpoint and wider)
// =============================================================================
class _BackupsWeb extends StatefulWidget {
  const _BackupsWeb({
    required this.items,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.onRestore,
    required this.onDelete,
  });
  final List<BackupItem> items;
  final _BkLoad status;
  final String errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<BackupItem> onRestore;
  final ValueChanged<BackupItem> onDelete;

  @override
  State<_BackupsWeb> createState() => _BackupsWebState();
}

class _BackupsWebState extends State<_BackupsWeb> {
  final _search = TextEditingController();
  bool _newestFirst = true; // items are given newest first

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<BackupItem> _visible() {
    final q = _search.text.trim().toLowerCase();
    final list = widget.items
        .where((i) =>
            q.isEmpty ||
            i.title.toLowerCase().contains(q) ||
            i.dateLabel.toLowerCase().contains(q))
        .toList();
    return _newestFirst ? list : list.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _visible();
    void back() => Navigator.of(context).maybePop();
    final count = widget.status == _BkLoad.ready ? widget.items.length : 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _BkTopBar(onBack: back),
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
                                  _BkPageHeader(count: count, onHome: back),
                                  const SizedBox(height: 20),
                                  Expanded(
                                    child: _BkListCard(
                                      search: _search,
                                      onSearchChanged: () => setState(() {}),
                                      newestFirst: _newestFirst,
                                      onToggleSort: () => setState(
                                          () => _newestFirst = !_newestFirst),
                                      totalCount: count,
                                      shown: shown,
                                      status: widget.status,
                                      errorMessage: widget.errorMessage,
                                      onRetry: widget.onRetry,
                                      onRestore: widget.onRestore,
                                      onDelete: widget.onDelete,
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

class _BkTopBar extends StatelessWidget {
  const _BkTopBar({required this.onBack});
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
                'Backups',
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

class _BkPageHeader extends StatelessWidget {
  const _BkPageHeader({required this.count, required this.onHome});
  final int count;
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
              'Backups',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Restore a saved version to My Portfolio to open or '
              'download it.',
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
                  const Icon(Icons.history, size: 22, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    '$count ${count == 1 ? 'backup' : 'backups'}',
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

class _BkListCard extends StatelessWidget {
  const _BkListCard({
    required this.search,
    required this.onSearchChanged,
    required this.newestFirst,
    required this.onToggleSort,
    required this.totalCount,
    required this.shown,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.onRestore,
    required this.onDelete,
  });

  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final bool newestFirst;
  final VoidCallback onToggleSort;
  final int totalCount;
  final List<BackupItem> shown;
  final _BkLoad status;
  final String errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<BackupItem> onRestore;
  final ValueChanged<BackupItem> onDelete;

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
                    'Saved portfolios',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
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
                            color: _textDark),
                        decoration: InputDecoration(
                          hintText: 'Search backups',
                          hintStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: _textMuted),
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 20, color: _textMuted),
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
                      message: 'Change order',
                      child: TextButton.icon(
                        onPressed: onToggleSort,
                        icon: Icon(
                            newestFirst
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            size: 18,
                            color: _navy),
                        label: Text(
                          newestFirst ? 'Newest first' : 'Oldest first',
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _navy),
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
            child: status == _BkLoad.loading
                ? const Center(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                          strokeWidth: 4, color: AppColors.primary),
                    ),
                  )
                : status == _BkLoad.error
                    ? _BkEmpty(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not load your backups',
                        message: errorMessage,
                        onRetry: onRetry,
                      )
                    : totalCount == 0
                        ? const _BkEmpty(
                            icon: Icons.history,
                            title: 'No backups yet',
                            message:
                                'Files you back up from My Portfolio will appear here.',
                          )
                        : shown.isEmpty
                            ? const _BkEmpty(
                                icon: Icons.search_off_rounded,
                                title: 'No matching backups',
                                message: 'Try a different search.',
                              )
                            : Scrollbar(
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: shown.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (_, i) => _BkRow(
                                    item: shown[i],
                                    onRestore: onRestore,
                                    onDelete: onDelete,
                                  ),
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}

class _BkRow extends StatefulWidget {
  const _BkRow({
    required this.item,
    required this.onRestore,
    required this.onDelete,
  });
  final BackupItem item;
  final ValueChanged<BackupItem> onRestore;
  final ValueChanged<BackupItem> onDelete;

  @override
  State<_BkRow> createState() => _BkRowState();
}

class _BkRowState extends State<_BkRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BkChip(icon: Icons.insert_drive_file_outlined, text: item.typeName),
        const SizedBox(width: 8),
        _BkChip(icon: Icons.storage_rounded, text: item.sizeLabel),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DeleteTextButton(onTap: () => widget.onDelete(item)),
        const SizedBox(width: 8),
        PrimaryActionButton(
          label: 'Restore',
          width: 104,
          onPressed: () => widget.onRestore(item),
        ),
      ],
    );
    final title = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(item.icon, size: 24, color: _navy),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: _textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hover
              ? AppColors.inputFill
              : AppColors.inputFill.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 820) {
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  meta,
                  const SizedBox(width: 24),
                  actions,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [meta, actions],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BkChip extends StatelessWidget {
  const _BkChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _textMuted),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _BkEmpty extends StatelessWidget {
  const _BkEmpty({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry; // error state: "Try again" button

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
              child: Icon(icon, size: 48, color: AppColors.menuButton),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _textMuted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              PrimaryActionButton(
                label: 'Try again',
                width: 160,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// "Delete" text action of a backup (same look as the former text action).
class _DeleteTextButton extends StatelessWidget {
  const _DeleteTextButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: const SizedBox(
        height: 48,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: _deleteColor),
              SizedBox(width: 6),
              Text(
                'Delete',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _deleteColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks before ONE backup is deleted for good. Returns true on "Delete".
Future<bool> _confirmDeleteBackup(BuildContext context, BackupItem item) async {
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
                'Delete this backup?',
                textAlign: TextAlign.center,
                style:
                    AppTheme.screenHeading.copyWith(color: AppColors.brandText),
              ),
              const SizedBox(height: 8),
              Text(
                'The backup of "${item.title}" from ${item.dateLabel} will be '
                'permanently deleted. Your original file and your other '
                'backups are not affected. This cannot be undone.',
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
