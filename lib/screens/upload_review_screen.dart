import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../utils/slide_route.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/uploading_dialog.dart';
import 'upload_complete_screen.dart';

const _labelNavy = Color(0xB3001B6E); // #001B6E @ 70%
const _editIcon = Color(0xFF001B6E);
const _descFill = Color(0xFFF3F3F3); // (approx) read visually from Figma
const _trackFill = Color(0xFFC8D9F6);
const _thumbFill = Color(0xFF1C4CB5);
const _thumbBorder = Color(0xFF0920A0);
const _publicText = Color(0xFF08085C);
const _errorRed = Color(0xFFD32F2F);

/// Figma frame: "4 - Upload Details (Review)" (student only, opened from the
/// "Next" button of Quick Upload).
///
/// - The pencil button turns the file name into an editable field. Only the
///   part BEFORE the extension can be changed (the extension is shown next to
///   the field, locked), and the name can't be empty.
/// - Visibility is a pill switch with two sides. Tapping the side that is NOT
///   active switches to it. Tapping the side that is already active does
///   nothing. It always starts on Private, every time this screen is opened.
/// - Back returns to Quick Upload. Upload stores the file in Supabase Storage
///   (the project of the logged-in role) and saves its details, showing the
///   "Uploading file..." overlay meanwhile; Cancel stops it and nothing is
///   kept. On success the Upload Complete screen opens, on failure a message
///   is shown and the user can try again.
class UploadReviewScreen extends ConsumerStatefulWidget {
  const UploadReviewScreen({
    super.key,
    required this.file,
    required this.fileName,
    this.fileSize,
    this.folderId,
  });

  /// The picked file (its bytes are what gets uploaded).
  final PlatformFile file;

  /// Full name of the picked file, including the extension (e.g. "Lesson 5.pdf").
  final String fileName;

  /// Size in bytes (null if unknown).
  final int? fileSize;

  /// My Portfolio folder to store the file in (null = root).
  final String? folderId;

  @override
  ConsumerState<UploadReviewScreen> createState() => _UploadReviewScreenState();
}

class _UploadReviewScreenState extends ConsumerState<UploadReviewScreen> {
  late String _baseName; // name without the extension (editable part)
  late final String _ext; // ".pdf" (locked), or '' if the file has none
  late final DateTime _uploadDate;

  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _descCtrl = TextEditingController();

  bool _editing = false;
  String? _nameError;
  bool _isPublic = false; // Private is the default
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final name = widget.fileName;
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      _baseName = name.substring(0, dot);
      _ext = name.substring(dot);
    } else {
      _baseName = name;
      _ext = '';
    }
    _uploadDate = DateTime.now();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ---- file name editing -------------------------------------------------

  void _startEditing() {
    _nameCtrl.text = _baseName;
    _nameCtrl.selection = TextSelection.collapsed(offset: _baseName.length);
    setState(() {
      _editing = true;
      _nameError = null;
    });
  }

  /// Saves the typed name. Returns false (and shows an error) if it is empty.
  bool _commitName() {
    var text = _nameCtrl.text.trim();
    // If the user typed the extension themselves, don't double it.
    if (_ext.isNotEmpty && text.toLowerCase().endsWith(_ext.toLowerCase())) {
      text = text.substring(0, text.length - _ext.length).trim();
    }
    if (text.isEmpty) {
      setState(() => _nameError = 'File name cannot be empty');
      return false;
    }
    setState(() {
      _baseName = text;
      _editing = false;
      _nameError = null;
    });
    FocusScope.of(context).unfocus();
    return true;
  }

  void _onEditTap() {
    if (_editing) {
      _commitName();
    } else {
      _startEditing();
    }
  }

  Future<void> _onUpload() async {
    if (_uploading) return; // ignore double taps
    if (_editing && !_commitName()) return; // fix the name first
    FocusScope.of(context).unfocus();

    _uploading = true;
    // Final name = $_baseName$_ext. Uploads to the Supabase project of the
    // logged-in role, under that user's own folder.
    final auth = ref.read(authProvider);
    final control = UploadControl();
    bool? done;
    try {
      done = await showUploadingDialog(
        context,
        fileName: '$_baseName$_ext',
        totalBytes: widget.fileSize,
        control: control,
        task: () async {
          await uploadPortfolioFile(
            auth: auth,
            file: widget.file,
            displayName: '$_baseName$_ext',
            description: _descCtrl.text,
            isPublic: _isPublic,
            folderId: widget.folderId,
            control: control,
          );
        },
      );
    } on UploadFailure catch (e) {
      if (mounted) _showError(e.message);
    } catch (_) {
      if (mounted) _showError('The upload failed. Please try again.');
    } finally {
      _uploading = false;
    }

    if (!mounted || done != true) return; // cancelled / failed -> stay here
    Navigator.of(context).push(
      SlideFromRightRoute(page: const UploadCompleteScreen()),
    );
  }

  /// Floating message: does not change the screen layout.
  void _showError(String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.error,
          content: Text(message, style: TextStyle(color: scheme.onError)),
        ),
      );
  }

  // ---- formatting helpers ------------------------------------------------

  static String _formatSize(int bytes) {
    // Decimal units (1 KB = 1000 B), same as Quick Upload.
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String get _typeLabel {
    switch (_ext.toLowerCase()) {
      case '.pdf':
        return 'PDF File';
      case '.doc':
      case '.docx':
        return 'Word Document';
      case '.xls':
      case '.xlsx':
        return 'Excel Spreadsheet';
      case '.ppt':
      case '.pptx':
        return 'PowerPoint File';
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
        return 'Image File';
      case '':
        return 'File';
      default:
        return '${_ext.substring(1).toUpperCase()} File';
    }
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    // Immersive mode can report 0 for the top inset, keep the Figma height.
    final topPad = inset.top < 36 ? 36.0 : inset.top;
    final bottomPad = inset.bottom + 12;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _Header(topPad: topPad),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(33, 28, 33, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildNameBlock(),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _InfoBlock(
                                        label: 'Type', value: _typeLabel),
                                    const SizedBox(height: 23),
                                    _InfoBlock(
                                        label: 'Upload Date',
                                        value: _formatDate(_uploadDate)),
                                    const SizedBox(height: 22),
                                    _InfoBlock(
                                      label: 'Size',
                                      value: widget.fileSize == null
                                          ? '-'
                                          : _formatSize(widget.fileSize!),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 3, right: 8),
                                child: RepaintBoundary(child: _DocumentPreview(ext: _ext)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const _Label('Description'),
                          const SizedBox(height: 5),
                          _DescriptionBox(controller: _descCtrl),
                          const SizedBox(height: 9),
                          const _Label('Visibility'),
                          const SizedBox(height: 24),
                          // No setState here: the pill animates by itself and the
                          // rest of the screen is not rebuilt on every tap.
                          _VisibilityToggle(
                            initialIsPublic: _isPublic,
                            onChanged: (v) => _isPublic = v,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom row: Back (left) and Upload (right).
            Padding(
              padding: EdgeInsets.fromLTRB(33, 8, 33, 43 + bottomPad),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PrimaryActionButton(
                    label: 'Back',
                    width: 104,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  PrimaryActionButton(
                    label: 'Upload',
                    width: 104,
                    onPressed: _onUpload,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Name" label, the file name (or the edit field) and the pencil button.
  Widget _buildNameBlock() {
    return Stack(
      children: [
        Padding(
          // keep clear of the 48px pencil button (+27px from the right edge)
          padding: const EdgeInsets.only(right: 75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Name'),
              SizedBox(
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _editing ? _buildNameField() : _buildNameText(),
                    ),
                    // Floats under the field, takes no layout space.
                    if (_nameError != null)
                      Positioned(
                        left: 12,
                        right: 0,
                        bottom: -15,
                        child: Text(
                          _nameError!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            height: 1.0,
                            color: _errorRed,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 27,
          top: 17,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _onEditTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  _editing ? Icons.check_rounded : Icons.edit_square,
                  size: 38,
                  color: _editIcon,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNameText() {
    return Text(
      '$_baseName$_ext',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _valueStyle,
    );
  }

  Widget _buildNameField() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              autofocus: true,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              style: _valueStyle.copyWith(color: Colors.black),
              inputFormatters: [
                // characters that are not allowed in file names
                FilteringTextInputFormatter.deny(RegExp(r'[\\/:*?"<>|]')),
              ],
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onEditingComplete: () {
                if (!_commitName()) _nameFocus.requestFocus();
              },
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'File name',
              ),
            ),
          ),
          // The extension is locked: shown, but not part of the field.
          if (_ext.isNotEmpty)
            Text(
              _ext,
              style: _valueStyle.copyWith(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

TextStyle get _valueStyle => TextStyle(
      fontFamily: 'Inter',
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Colors.black.withValues(alpha: 0.7),
    );

/// Blue gradient header with the left-aligned title (same gradient as the
/// other screens).
class _Header extends StatelessWidget {
  const _Header({required this.topPad});
  final double topPad;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: topPad + 78,
      padding: const EdgeInsets.only(left: 12, bottom: 14),
      alignment: Alignment.bottomLeft,
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
      child: const Text(
        'File Upload Details',
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: _labelNavy,
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        const SizedBox(height: 18),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _valueStyle,
        ),
      ],
    );
  }
}

/// Stacked-page preview (Figma "image 3" + the faded page behind it).
/// A real thumbnail needs a PDF/image renderer, so for now this shows a
/// paper placeholder with an icon for the file type.
class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({required this.ext});
  final String ext;

  IconData get _icon {
    switch (ext.toLowerCase()) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.ppt':
      case '.pptx':
        return Icons.slideshow;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  static const _shadow = [
    BoxShadow(color: Color(0x40000000), offset: Offset(5, 4), blurRadius: 4),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      height: 258,
      child: Stack(
        children: [
          // page behind (50% opacity)
          Positioned(
            left: 26,
            top: 22,
            width: 151,
            height: 234,
            child: Opacity(
              opacity: 0.5,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFEFDFD),
                  boxShadow: _shadow,
                ),
              ),
            ),
          ),
          // front page
          Positioned(
            left: 0,
            top: 0,
            width: 152,
            height: 236,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: _shadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_icon, size: 56, color: AppColors.homeIcon),
                  if (ext.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ext.substring(1).toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _labelNavy,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DescriptionBox extends StatelessWidget {
  const _DescriptionBox({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 123,
      decoration: BoxDecoration(
        color: _descFill,
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        controller: controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(17, 20, 17, 14),
          hintText: 'Enter description...',
          hintStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// Figma "Public/Private" pill (361 x 48).
///
/// Two tap zones, one per side. Tapping the inactive side switches to it;
/// tapping the side that is already active does nothing.
///
/// Smooth: the pill runs its own animation (ease out). Only the pill is
/// repainted while it moves, the rest of the screen is not rebuilt.
class _VisibilityToggle extends StatefulWidget {
  const _VisibilityToggle({
    required this.initialIsPublic,
    required this.onChanged,
  });
  final bool initialIsPublic;
  final ValueChanged<bool> onChanged;

  @override
  State<_VisibilityToggle> createState() => _VisibilityToggleState();
}

class _VisibilityToggleState extends State<_VisibilityToggle>
    with SingleTickerProviderStateMixin {
  // 0.0 = Public (thumb on the left), 1.0 = Private (thumb on the right)
  late final AnimationController _ctrl;
  late bool _isPublic;

  @override
  void initState() {
    super.initState();
    _isPublic = widget.initialIsPublic;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: _isPublic ? 0.0 : 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _select(bool makePublic) {
    if (_isPublic == makePublic) return; // already active -> nothing happens
    _isPublic = makePublic;
    _ctrl.animateTo(
      makePublic ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic, // ease out, in both directions
    );
    widget.onChanged(makePublic);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 48,
        child: Stack(
          children: [
            // track
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _trackFill,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            // sliding thumb (the dark half): moves one thumb-width to the right
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: SlideTransition(
                  position: _ctrl.drive(
                    Tween<Offset>(begin: Offset.zero, end: const Offset(1, 0)),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _thumbFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _thumbBorder, width: 3),
                    ),
                  ),
                ),
              ),
            ),
            // labels (colors fade with the thumb) + tap zones
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = _ctrl.value;
                return Row(
                  children: [
                    Expanded(
                      child: _Side(
                        label: 'Public',
                        color: Color.lerp(Colors.white, _publicText, t)!,
                        onTap: () => _select(true),
                      ),
                    ),
                    Expanded(
                      child: _Side(
                        label: 'Private',
                        color: Color.lerp(_publicText, Colors.white, t)!,
                        onTap: () => _select(false),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
