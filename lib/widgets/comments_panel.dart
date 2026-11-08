part of '../screens/community_screen.dart';

/// Figma frame: "File Viewing" (941:452) - the Comments page (428 x 926).
///
/// Same header as the file page (Menu button + search bar). Below it: back
/// button, file info and the light-blue "Comments" panel (x = 24, y = 273,
/// 377 x 612, radius 20). Each comment is 60 px: a 35 px avatar, the user
/// name (12 px), the text (14 px bold), the date (10 px) and a thumbs-up.
///
/// Extra (not in the Figma frame, needed to make it work): a write box at the
/// bottom of the panel, a count under the thumb, and press-and-hold to delete.
enum _CommentSort { newest, oldest, liked }

class _CommentsPage extends ConsumerStatefulWidget {
  const _CommentsPage({
    super.key,
    required this.file,
    required this.onBack,
    required this.bottom,
  });

  final CommunityFile file;
  final VoidCallback onBack;
  final double bottom;

  @override
  ConsumerState<_CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends ConsumerState<_CommentsPage> {
  static const _navy = Color(0xFF0A2381);
  static const _title = Color(0xFF173650);

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  _Load _state = _Load.loading;
  String _error = '';
  List<FileComment> _comments = const [];
  _CommentSort _sort = _CommentSort.newest;

  bool _sending = false;
  final _liking = <String>{}; // comment ids with a like request in flight

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  Future<void> _load({bool first = false}) async {
    if (!first && _comments.isEmpty) setState(() => _state = _Load.loading);
    try {
      final rows = await loadComments(ref.read(authProvider), widget.file.id);
      if (!mounted) return;
      setState(() {
        _comments = rows;
        _state = _Load.ready;
      });
    } on UploadFailure catch (e) {
      if (!mounted) return;
      // Keep what is already on screen when only a refresh failed.
      if (_comments.isNotEmpty) {
        showPortfolioMessage(context, e.message, error: true);
        return;
      }
      setState(() {
        _error = e.message;
        _state = _Load.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load comments. Try again.';
        _state = _Load.error;
      });
    }
  }

  /// Your own comments are always at the top (in the chosen order), then
  /// everyone else's (in the chosen order).
  List<FileComment> get _sorted {
    int byOrder(FileComment a, FileComment b) {
      switch (_sort) {
        case _CommentSort.newest:
          return b.createdAt.compareTo(a.createdAt);
        case _CommentSort.oldest:
          return a.createdAt.compareTo(b.createdAt);
        case _CommentSort.liked:
          final c = b.likeCount.compareTo(a.likeCount);
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      }
    }

    final list = [..._comments];
    list.sort((a, b) {
      if (a.isMine != b.isMine) return a.isMine ? -1 : 1;
      return byOrder(a, b);
    });
    return list;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final saved =
          await addComment(ref.read(authProvider), widget.file.id, text);
      if (!mounted) return;
      setState(() {
        _comments = [saved, ..._comments.where((c) => c.id != saved.id)];
        _sending = false;
        _input.clear();
        _state = _Load.ready;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on UploadFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showPortfolioMessage(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showPortfolioMessage(context, 'Could not post your comment.',
          error: true);
    }
  }

  /// Instant feedback first, then the server's real answer.
  Future<void> _toggleLike(FileComment c) async {
    if (!_liking.add(c.id)) return; // one request per comment at a time
    void put(FileComment Function(FileComment) f) => setState(() {
          _comments = [for (final x in _comments) x.id == c.id ? f(x) : x];
        });

    put((x) => x.copyWith(
          likedByMe: !c.likedByMe,
          likeCount: math.max(0, c.likeCount + (c.likedByMe ? -1 : 1)),
        ));
    try {
      final r = await toggleCommentLike(ref.read(authProvider), c.id);
      if (!mounted) return;
      put((x) => x.copyWith(likedByMe: r.liked, likeCount: r.count));
    } on UploadFailure catch (e) {
      if (!mounted) return;
      put((x) => x.copyWith(likedByMe: c.likedByMe, likeCount: c.likeCount));
      showPortfolioMessage(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      put((x) => x.copyWith(likedByMe: c.likedByMe, likeCount: c.likeCount));
      showPortfolioMessage(context, 'Could not update your like.', error: true);
    } finally {
      _liking.remove(c.id);
    }
  }

  bool _canDelete(FileComment c) =>
      c.isMine || widget.file.ownerId == ref.read(authProvider).userId;

  Future<void> _confirmDelete(FileComment c) async {
    if (!_canDelete(c)) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete comment?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _title,
          ),
        ),
        content: Text(
          c.isMine
              ? 'Your comment will be removed for everyone.'
              : 'This comment will be removed from your file.',
          style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await deleteComment(ref.read(authProvider), c.id);
      if (!mounted) return;
      setState(() => _comments = _comments.where((x) => x.id != c.id).toList());
      showPortfolioMessage(context, 'Comment deleted.');
    } on UploadFailure catch (e) {
      if (mounted) showPortfolioMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showPortfolioMessage(context, 'Could not delete the comment.',
            error: true);
      }
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14), // header ends y = 137, back button y = 151
        Padding(
          padding: const EdgeInsets.only(left: 19),
          child: _BackCircle(
            onTap: widget.onBack,
            label: 'Back to file',
          ),
        ),
        const SizedBox(height: 16), // info y = 207
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: _FileInfo(file: widget.file),
        ),
        const SizedBox(height: 6), // info ends y = 267, panel y = 273
        Expanded(
          child: Padding(
            // x = 24, 377 wide (right 27); ends y = 885 of 926.
            padding: EdgeInsets.fromLTRB(24, 0, 27, widget.bottom + 24),
            child: Material(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _panelHeader(),
                  Expanded(child: _body()),
                  _composer(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// "Comments" (20 px bold) and the sort button, y = 290 in the frame.
  Widget _panelHeader() {
    const labels = {
      _CommentSort.newest: 'Newest first',
      _CommentSort.oldest: 'Oldest first',
      _CommentSort.liked: 'Most liked',
    };
    return SizedBox(
      height: 53,
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 14,
            child: Text(
              _comments.isEmpty ? 'Comments' : 'Comments (${_comments.length})',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _title,
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 4,
            child: PopupMenuButton<_CommentSort>(
              tooltip: 'Sort comments',
              position: PopupMenuPosition.under,
              color: Colors.white,
              elevation: 6,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                for (final s in _CommentSort.values)
                  PopupMenuItem<_CommentSort>(
                    value: s,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: s == _sort
                              ? const Icon(Icons.check, size: 18, color: _navy)
                              : null,
                        ),
                        Text(
                          labels[s]!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _title,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  // Figma "bi:filter-right": three bars, right aligned.
                  child: _svg(
                    '<rect x="24" y="18" width="12" height="3" rx="1.5"/>'
                    '<rect x="12" y="9" width="24" height="3" rx="1.5"/>'
                    '<rect x="0" y="0" width="36" height="3" rx="1.5"/>',
                    w: 36,
                    h: 21,
                    fill: _navy,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_state) {
      case _Load.loading:
        return const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 40),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.menuButton,
              ),
            ),
          ),
        );
      case _Load.error:
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: _CommunityScreenState._endStyle,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _load,
                  child: const Text(
                    'Try again',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.link,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _Load.ready:
        final list = _sorted;
        return RefreshIndicator(
          color: AppColors.menuButton,
          onRefresh: _load,
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Padding(
                      padding: EdgeInsets.fromLTRB(24, 32, 24, 0),
                      child: Text(
                        'No comments yet.\nBe the first to comment!',
                        textAlign: TextAlign.center,
                        style: _CommunityScreenState._endStyle,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _CommentRow(
                    comment: list[i],
                    onLike: () => _toggleLike(list[i]),
                    onDelete: _canDelete(list[i])
                        ? () => _confirmDelete(list[i])
                        : null,
                  ),
                ),
        );
    }
  }

  /// Write box (white, radius 20, like the search bar) + send button.
  Widget _composer() {
    final hasText = _input.text.trim().isNotEmpty;
    final canSend = hasText && !_sending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                enabled: !_sending,
                onChanged: (_) => setState(() {}),
                minLines: 1,
                maxLines: 4,
                maxLength: kMaxCommentLength,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                cursorColor: AppColors.menuButton,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0x80000000), // black @ 50%
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            enabled: canSend,
            label: 'Post comment',
            child: Material(
              color: canSend ? AppColors.menuButton : const Color(0x330068B8),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: canSend ? _send : null,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 22, color: Colors.white),
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

/// One comment: avatar, name, text, date and the thumbs-up.
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.onLike,
    this.onDelete,
  });

  final FileComment comment;
  final VoidCallback onLike;
  final VoidCallback? onDelete; // null = this person cannot delete it

  static const _navy = Color(0xFF0A2381);

  /// Figma date format: MM-DD-YY (11-04-26).
  static String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)}-${two(d.year % 100)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = comment;
    return InkWell(
      onLongPress: onDelete,
      onSecondaryTap: onDelete, // right-click on the web
      child: Padding(
        padding: const EdgeInsets.fromLTRB(21, 4, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Avatar(),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.isMine ? '${c.authorName} (You)' : c.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: _ResultCard._grey,
                      ),
                    ),
                    Text(
                      c.body,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: Color(0xFF173650),
                      ),
                    ),
                    Text(
                      _date(c.createdAt),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: _ResultCard._grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: c.likedByMe ? 'Remove like' : 'Like comment',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onLike,
                child: SizedBox(
                  width: 44,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      Icon(
                        c.likedByMe
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                        size: 28,
                        color: _navy,
                      ),
                      if (c.likeCount > 0)
                        Text(
                          '${c.likeCount}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _navy,
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

/// Figma "Account avatar": 35 x 35, blue ring with a person inside.
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" width="35" height="35" '
      'viewBox="0 0 35 35"><defs><clipPath id="c">'
      '<circle cx="17.5" cy="17.5" r="15"/></clipPath></defs>'
      '<circle cx="17.5" cy="17.5" r="16" fill="none" stroke="#0068B8" '
      'stroke-width="2.5"/>'
      '<g clip-path="url(#c)" fill="#0068B8">'
      '<circle cx="17.5" cy="13.5" r="5.5"/>'
      '<ellipse cx="17.5" cy="31" rx="12" ry="9.5"/></g></svg>',
      width: 35,
      height: 35,
    );
  }
}
