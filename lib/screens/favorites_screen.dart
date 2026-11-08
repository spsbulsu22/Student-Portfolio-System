import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/primary_action_button.dart';
import 'my_portfolio_screen.dart'; // shared helpers + kPortfolioWideBreakpoint

const _navy = Color(0xFF0A2381);
const _starColor = Color(0xFFF59E0B);

enum _FavLoad { loading, ready, error }

/// One favorite file as the page shows it (a row of `user_files` with
/// `is_favorite = true`).
class _FavEntry {
  _FavEntry(this.file);
  final StoredFile file;

  String get name => file.name;
  String get typeName => file.fileType.toUpperCase(); // "PDF", "DOCX"...
  IconData get icon => portfolioIconForType(file.fileType);
  String get label => '$typeName  •  ${portfolioFmtDate(file.createdAt)}';
  String? get sizeLabel => portfolioFmtSize(file.sizeBytes);
  bool get canPreview => portfolioCanPreview(file.fileType);
}

/// What a favorite row / card can do.
class _FavActions {
  const _FavActions({required this.open, required this.unfavorite});
  final ValueChanged<_FavEntry> open;
  final ValueChanged<_FavEntry> unfavorite; // tap on the star
}

/// Figma frame: "2.2 Favorite" (student only).
///
/// Same look as My Portfolio, with a star on each file and no Upload button.
/// Shows the files starred in My Portfolio (read from Supabase, the same
/// `user_files` rows). Tapping the star removes a file from the favorites.
///
/// Responsive (same breakpoint as My Portfolio):
///  - narrower than [kPortfolioWideBreakpoint]: the original phone layout
///  - wider: the desktop web layout
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  _FavLoad _status = _FavLoad.loading;
  List<_FavEntry> _items = const [];
  String _error = '';
  int _loadId = 0;
  bool _opening = false;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load(showSpinner: false); // already starts in the loading state
  }

  Future<void> _load({bool showSpinner = true}) async {
    final id = ++_loadId;
    if (showSpinner) setState(() => _status = _FavLoad.loading);
    try {
      final files = await listMyFavorites(ref.read(authProvider));
      if (!mounted || id != _loadId) return;
      setState(() {
        _items = [for (final f in files) _FavEntry(f)];
        _status = _FavLoad.ready;
      });
    } on UploadFailure catch (e) {
      _onLoadError(id, e.message);
    } catch (_) {
      _onLoadError(id, 'Could not load your favorites. Try again.');
    }
  }

  void _onLoadError(int id, String message) {
    if (!mounted || id != _loadId) return;
    setState(() {
      _error = message;
      _status = _FavLoad.error;
    });
  }

  Future<void> _open(_FavEntry e) async {
    if (_opening) return; // ignore double taps while the link is made
    _opening = true;
    try {
      final auth = ref.read(authProvider);
      final inline = e.canPreview;
      await openPortfolioUrl(
        context,
        () => fileUrl(auth, e.file, download: !inline),
        inline: inline,
      );
    } finally {
      _opening = false;
    }
  }

  /// Removes the file from the favorites (it stays in My Portfolio).
  Future<void> _unfavorite(_FavEntry e) async {
    final id = e.file.id;
    if (!_busy.add(id)) return;
    final auth = ref.read(authProvider);
    final before = _items;
    setState(() => _items = [
          for (final i in _items)
            if (i.file.id != id) i,
        ]);
    try {
      await setFileFavorite(auth, e.file, false);
      if (mounted) showPortfolioMessage(context, 'Removed from favorites.');
    } on UploadFailure catch (ex) {
      _restore(before, ex.message);
    } catch (_) {
      _restore(before, 'Could not remove the file from your favorites.');
    } finally {
      _busy.remove(id);
    }
  }

  void _restore(List<_FavEntry> before, String message) {
    if (!mounted) return;
    setState(() => _items = before);
    showPortfolioMessage(context, message, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final actions = _FavActions(open: _open, unfavorite: _unfavorite);
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= kPortfolioWideBreakpoint
          ? _FavoritesWeb(
              items: _items,
              status: _status,
              errorMessage: _error,
              onRetry: _load,
              actions: actions,
            )
          : _FavoritesMobile(
              items: _items,
              status: _status,
              errorMessage: _error,
              onRetry: _load,
              actions: actions,
            ),
    );
  }
}

/// Phone layout: same search, filter, name sort and list / grid view as the
/// phone layout of My Portfolio. The search box is always visible; the sort
/// button opens a bottom sheet with the filter, the sort order and the view.
class _FavoritesMobile extends StatefulWidget {
  const _FavoritesMobile({
    required this.items,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.actions,
  });

  final List<_FavEntry> items;
  final _FavLoad status;
  final String errorMessage;
  final VoidCallback onRetry;
  final _FavActions actions;

  @override
  State<_FavoritesMobile> createState() => _FavoritesMobileState();
}

class _FavoritesMobileState extends State<_FavoritesMobile> {
  final _search = TextEditingController();
  _FavFilter _filter = _FavFilter.all;
  bool _ascending = true;
  bool _grid = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  /// Anything other than the default view (used for the dot on the button).
  bool get _customView => _filter != _FavFilter.all || !_ascending || _grid;

  bool get _searchingOrFiltering =>
      _query.isNotEmpty || _filter != _FavFilter.all;

  // Same rules as the desktop layout (_FavoritesWebState._visible).
  List<_FavEntry> _visible() {
    final q = _query;
    final list = widget.items.where((i) {
      final okQuery = q.isEmpty ||
          i.name.toLowerCase().contains(q) ||
          i.label.toLowerCase().contains(q);
      return _favMatchesFilter(_filter, i) && okQuery;
    }).toList();
    list.sort((a, b) => _ascending
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    return list;
  }

  void _clearAll() {
    setState(() {
      _search.clear();
      _filter = _FavFilter.all;
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

          return _FavSortSheet(
            filter: _filter,
            ascending: _ascending,
            grid: _grid,
            onFilter: (f) => apply(() => _filter = f),
            onAscending: (a) => apply(() => _ascending = a),
            onGrid: (g) => apply(() => _grid = g),
            onReset: () => apply(() {
              _filter = _FavFilter.all;
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
    final topPad = inset.top + 12; // small margin above the header
    final bottomPad = inset.bottom + 12; // small margin below the Home button
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final status = widget.status;
    final items = _visible();
    final actions = widget.actions;

    Widget body;
    if (status == _FavLoad.loading) {
      body = const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
              strokeWidth: 4, color: AppColors.primary),
        ),
      );
    } else if (status == _FavLoad.error) {
      body = _EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load your favorites',
        message: widget.errorMessage,
        onRetry: widget.onRetry,
      );
    } else if (widget.items.isEmpty) {
      body = const _EmptyState();
    } else if (items.isEmpty) {
      body = _EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching favorites',
        message: 'Try a different search or filter.',
        onRetry: _searchingOrFiltering ? _clearAll : null,
        actionLabel: 'Clear',
      );
    } else if (_grid) {
      body = LayoutBuilder(
        builder: (_, c) {
          // Auto-adjusts to the width: 2 columns on phones, more when wider.
          final columns = (c.maxWidth ~/ 180).clamp(2, 6).toInt();
          return GridView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 160,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) =>
                _FavMobileGridCard(item: items[i], actions: actions),
          );
        },
      );
    } else {
      body = ListView.separated(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => _FavoriteCard(item: items[i], actions: actions),
      );
    }

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _FavSearchField(
                controller: _search,
                onChanged: () => setState(() {}),
              ),
            ),
            // Filter & sort button (48x48, right side)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 24),
                child: Tooltip(
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
              ),
            ),
            Expanded(child: body),
            // Home button: 104x48, 36 from the left. Hidden while the
            // keyboard is up so the page never overflows.
            if (!keyboardOpen)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(36, 8, 0, 46 + bottomPad),
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

/// Search box of the phone layout (same look as My Portfolio's, plus a
/// clear button while there is text).
class _FavSearchField extends StatelessWidget {
  const _FavSearchField({required this.controller, required this.onChanged});
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
          hintText: 'Search favorites',
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
class _FavSortSheet extends StatelessWidget {
  const _FavSortSheet({
    required this.filter,
    required this.ascending,
    required this.grid,
    required this.onFilter,
    required this.onAscending,
    required this.onGrid,
    required this.onReset,
    required this.onDone,
  });

  final _FavFilter filter;
  final bool ascending;
  final bool grid;
  final ValueChanged<_FavFilter> onFilter;
  final ValueChanged<bool> onAscending;
  final ValueChanged<bool> onGrid;
  final VoidCallback onReset;
  final VoidCallback onDone;

  static const _filters = <(_FavFilter, String)>[
    (_FavFilter.all, 'All'),
    (_FavFilter.images, 'Images'),
    (_FavFilter.pdf, 'PDF'),
    (_FavFilter.docx, 'DOCX'),
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
            const _FavSheetLabel('Show'),
            LayoutBuilder(
              builder: (_, c) {
                const gap = 8.0;
                final w = (c.maxWidth - gap) / 2; // 2 columns x 2 rows
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final f in _filters)
                      _FavSheetChip(
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
            const _FavSheetLabel('Sort by name'),
            LayoutBuilder(
              builder: (_, c) {
                const gap = 8.0;
                final w = (c.maxWidth - gap) / 2;
                return Row(
                  children: [
                    _FavSheetChip(
                      label: 'Ascending',
                      icon: Icons.arrow_upward_rounded,
                      width: w,
                      selected: ascending,
                      onTap: () => onAscending(true),
                    ),
                    const SizedBox(width: gap),
                    _FavSheetChip(
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
            const _FavSheetLabel('View'),
            LayoutBuilder(
              builder: (_, c) {
                const gap = 8.0;
                final w = (c.maxWidth - gap) / 2;
                return Row(
                  children: [
                    _FavSheetChip(
                      label: 'List',
                      icon: Icons.view_list_rounded,
                      width: w,
                      selected: !grid,
                      onTap: () => onGrid(false),
                    ),
                    const SizedBox(width: gap),
                    _FavSheetChip(
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

class _FavSheetLabel extends StatelessWidget {
  const _FavSheetLabel(this.text);
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

/// Pill used inside the sort sheet, sized by the sheet so the columns line up.
class _FavSheetChip extends StatelessWidget {
  const _FavSheetChip({
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

/// Phone grid card of a favorite (used when the grid view is selected).
class _FavMobileGridCard extends StatelessWidget {
  const _FavMobileGridCard({required this.item, required this.actions});
  final _FavEntry item;
  final _FavActions actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => actions.open(item),
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
                    child: Icon(item.icon, size: 22, color: _navy),
                  ),
                  const Spacer(),
                  _FavStar(onTap: () => actions.unfavorite(item), size: 40),
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

/// Same header as My Portfolio / Notifications / Profile.
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
            'Favorites',
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

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.item, required this.actions});
  final _FavEntry item;
  final _FavActions actions;

  IconData get _icon => item.icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputFill, // #D3E7FF
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        borderRadius: BorderRadius.circular(25),
        onTap: () => actions.open(item),
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
                const SizedBox(width: 8),
                _FavStar(onTap: () => actions.unfavorite(item), size: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The filled star of a favorite: tap to remove the file from the favorites.
class _FavStar extends StatelessWidget {
  const _FavStar({required this.onTap, this.size = 48});
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Remove from favorites',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: const Icon(Icons.star_rounded, size: 24, color: _starColor),
        ),
      ),
    );
  }
}

/// Shown while there are no favorites (not part of the Figma frame).
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.icon = Icons.star_border_rounded,
    this.title = 'No favorites yet',
    this.message = 'Files you star will appear here.',
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
// DESKTOP WEB LAYOUT (kPortfolioWideBreakpoint and wider)
// =============================================================================
enum _FavFilter { all, images, pdf, docx }

const _favImageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp'};

/// Filter rule shared by the phone and the desktop layout.
bool _favMatchesFilter(_FavFilter f, _FavEntry i) {
  final ext = i.file.fileType.toLowerCase();
  return switch (f) {
    _FavFilter.all => true,
    _FavFilter.images => _favImageExts.contains(ext),
    _FavFilter.pdf => ext == 'pdf',
    _FavFilter.docx => ext == 'doc' || ext == 'docx',
  };
}

class _FavoritesWeb extends StatefulWidget {
  const _FavoritesWeb({
    required this.items,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.actions,
  });
  final List<_FavEntry> items;
  final _FavLoad status;
  final String errorMessage;
  final VoidCallback onRetry;
  final _FavActions actions;

  @override
  State<_FavoritesWeb> createState() => _FavoritesWebState();
}

class _FavoritesWebState extends State<_FavoritesWeb> {
  final _search = TextEditingController();
  _FavFilter _filter = _FavFilter.all;
  bool _ascending = true;
  bool _grid = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_FavEntry> _visible() {
    final q = _search.text.trim().toLowerCase();
    final list = widget.items.where((i) {
      final okType = _favMatchesFilter(_filter, i);
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

  @override
  Widget build(BuildContext context) {
    final shown = _visible();
    void back() => Navigator.of(context).maybePop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _FavTopBar(onBack: back),
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
                                  _FavPageHeader(
                                      count: widget.items.length,
                                      onHome: back),
                                  const SizedBox(height: 20),
                                  Expanded(
                                    child: _FavFilesCard(
                                      search: _search,
                                      onSearchChanged: () => setState(() {}),
                                      filter: _filter,
                                      onFilter: (f) =>
                                          setState(() => _filter = f),
                                      ascending: _ascending,
                                      onToggleSort: () => setState(
                                          () => _ascending = !_ascending),
                                      grid: _grid,
                                      onGrid: (g) => setState(() => _grid = g),
                                      totalCount: widget.items.length,
                                      shown: shown,
                                      status: widget.status,
                                      errorMessage: widget.errorMessage,
                                      onRetry: widget.onRetry,
                                      actions: widget.actions,
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

class _FavTopBar extends StatelessWidget {
  const _FavTopBar({required this.onBack});
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
                'Favorites',
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

class _FavPageHeader extends StatelessWidget {
  const _FavPageHeader({required this.count, required this.onHome});
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
              'Favorites',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Quick access to the files you starred.',
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
                  const Icon(Icons.star_rounded, size: 22, color: _starColor),
                  const SizedBox(width: 8),
                  Text(
                    '$count ${count == 1 ? 'favorite' : 'favorites'}',
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

class _FavFilesCard extends StatelessWidget {
  const _FavFilesCard({
    required this.search,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilter,
    required this.ascending,
    required this.onToggleSort,
    required this.grid,
    required this.onGrid,
    required this.totalCount,
    required this.shown,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.actions,
  });

  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final _FavFilter filter;
  final ValueChanged<_FavFilter> onFilter;
  final bool ascending;
  final VoidCallback onToggleSort;
  final bool grid;
  final ValueChanged<bool> onGrid;
  final int totalCount;
  final List<_FavEntry> shown;
  final _FavLoad status;
  final String errorMessage;
  final VoidCallback onRetry;
  final _FavActions actions;

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
          _FavToolbar(
            search: search,
            onSearchChanged: onSearchChanged,
            filter: filter,
            onFilter: onFilter,
            ascending: ascending,
            onToggleSort: onToggleSort,
            grid: grid,
            onGrid: onGrid,
          ),
          const Divider(height: 1, color: AppColors.menuDivider),
          Expanded(
            child: status == _FavLoad.loading
                ? const Center(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                          strokeWidth: 4, color: AppColors.primary),
                    ),
                  )
                : status == _FavLoad.error
                    ? _FavEmpty(
                        title: 'Could not load your favorites',
                        message: errorMessage,
                        icon: Icons.error_outline_rounded,
                        onRetry: onRetry,
                      )
                    : totalCount == 0
                        ? const _FavEmpty(
                            title: 'No favorites yet',
                            message: 'Files you star will appear here.',
                          )
                        : shown.isEmpty
                            ? const _FavEmpty(
                                title: 'No matching favorites',
                                message: 'Try a different search or filter.',
                                icon: Icons.search_off_rounded,
                              )
                            : grid
                                ? _FavGrid(items: shown, actions: actions)
                                : _FavTable(items: shown, actions: actions),
          ),
        ],
      ),
    );
  }
}

class _FavToolbar extends StatelessWidget {
  const _FavToolbar({
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
  final _FavFilter filter;
  final ValueChanged<_FavFilter> onFilter;
  final bool ascending;
  final VoidCallback onToggleSort;
  final bool grid;
  final ValueChanged<bool> onGrid;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _FavFilter.all: 'All',
      _FavFilter.images: 'Images',
      _FavFilter.pdf: 'PDF',
      _FavFilter.docx: 'DOCX',
    };
    return Padding(
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
                hintText: 'Search favorites',
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
          for (final f in _FavFilter.values)
            ChoiceChip(
              label: Text(labels[f]!),
              selected: filter == f,
              showCheckmark: false,
              onSelected: (_) => onFilter(f),
              selectedColor: AppColors.menuButton,
              backgroundColor: AppColors.inputFill.withValues(alpha: 0.5),
              side: BorderSide.none,
              labelStyle: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: filter == f ? Colors.white : AppColors.menuText,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: ascending ? 'Sorted A to Z' : 'Sorted Z to A',
                child: TextButton.icon(
                  onPressed: onToggleSort,
                  icon: Icon(
                      ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 18,
                      color: _navy),
                  label: const Text('Name',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _navy)),
                ),
              ),
              const SizedBox(width: 4),
              _FavViewBtn(
                  icon: Icons.view_list_rounded,
                  tooltip: 'List view',
                  selected: !grid,
                  onTap: () => onGrid(false)),
              _FavViewBtn(
                  icon: Icons.grid_view_rounded,
                  tooltip: 'Grid view',
                  selected: grid,
                  onTap: () => onGrid(true)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavViewBtn extends StatelessWidget {
  const _FavViewBtn({
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
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon,
                size: 20,
                color: selected ? AppColors.menuButton : AppColors.menuMuted),
          ),
        ),
      ),
    );
  }
}

class _FavTable extends StatelessWidget {
  const _FavTable({required this.items, required this.actions});
  final List<_FavEntry> items;
  final _FavActions actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final showType = c.maxWidth >= 760;
        const head = TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.menuMuted,
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('NAME', style: head)),
                  if (showType)
                    const SizedBox(width: 110, child: Text('TYPE', style: head)),
                  const SizedBox(
                      width: 90,
                      child: Text('SIZE',
                          textAlign: TextAlign.right, style: head)),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.menuDivider),
            Expanded(
              child: Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _FavRow(
                      item: items[i], showType: showType, actions: actions),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FavRow extends StatefulWidget {
  const _FavRow({
    required this.item,
    required this.showType,
    required this.actions,
  });
  final _FavEntry item;
  final bool showType;
  final _FavActions actions;

  @override
  State<_FavRow> createState() => _FavRowState();
}

class _FavRowState extends State<_FavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: _hover
              ? AppColors.inputFill.withValues(alpha: 0.55)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => widget.actions.open(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _FavIconTile(icon: item.icon),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.menuMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.menuText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.showType)
                    SizedBox(width: 110, child: _FavTypeBadge(label: item.typeName)),
                  SizedBox(
                    width: 90,
                    child: Text(
                      item.sizeLabel ?? '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.menuMuted,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: _FavStar(
                      onTap: () => widget.actions.unfavorite(item),
                    ),
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

class _FavIconTile extends StatelessWidget {
  const _FavIconTile({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 24, color: _navy),
    );
  }
}

class _FavTypeBadge extends StatelessWidget {
  const _FavTypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.inputFill.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.menuButton,
          ),
        ),
      ),
    );
  }
}

class _FavGrid extends StatelessWidget {
  const _FavGrid({required this.items, required this.actions});
  final List<_FavEntry> items;
  final _FavActions actions;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 168,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _FavGridCard(item: items[i], actions: actions),
      ),
    );
  }
}

class _FavGridCard extends StatefulWidget {
  const _FavGridCard({required this.item, required this.actions});
  final _FavEntry item;
  final _FavActions actions;

  @override
  State<_FavGridCard> createState() => _FavGridCardState();
}

class _FavGridCardState extends State<_FavGridCard> {
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
            : AppColors.inputFill.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => widget.actions.open(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    const Spacer(),
                    _FavStar(
                      onTap: () => widget.actions.unfavorite(item),
                      size: 40,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.menuMuted,
                  ),
                ),
                const SizedBox(height: 2),
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
                if (item.sizeLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.sizeLabel!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.menuMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavEmpty extends StatelessWidget {
  const _FavEmpty({
    required this.title,
    required this.message,
    this.icon = Icons.star_border_rounded,
    this.onRetry,
  });
  final String title;
  final String message;
  final IconData icon;
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
                color: AppColors.menuText,
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
                color: AppColors.menuMuted,
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
