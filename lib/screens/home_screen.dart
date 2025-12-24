import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mongol/mongol.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../services/storage_service.dart';
import '../utils/rich_text_controller.dart';
import 'settings_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'recycle_bin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  List<Note> _notes = [];
  Note? _selectedNote;
  
  final TextEditingController _titleController = TextEditingController();
  late MongolRichTextController _contentController;
  final GlobalKey _exportKey = GlobalKey();
  late TextEditingController _searchController;
  late FocusNode _titleFocusNode;
  late FocusNode _contentFocusNode;
  String _searchQuery = '';
  bool _isSearchVisible = false;
  final ValueNotifier<int> _wordCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isContentFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isTitleFocused = ValueNotifier<bool>(false);
  int _wordCount = 0; // Keeping for compatibility or removing usage below
  final ImagePicker _picker = ImagePicker();
  TextSelection? _lastValidSelection; // Track last valid selection for formatting
  
  // Visual Settings
  String _currentFont = 'Xinhei';
  String _currentTheme = 'Paper';

  Map<String, dynamic> get _themeData {
    switch (_currentTheme) {
      case 'Night':
        return {
          'paper': const Color(0xFF2D2D2D),
          'sidebar': const Color(0xFF1A1A1A),
          'text': Colors.white,
          'divider': Colors.grey[800],
        };
      case 'Nostalgic':
        return {
          'paper': const Color(0xFFF4ECD8),
          'sidebar': const Color(0xFF5D4037),
          'text': const Color(0xFF3E2723),
          'divider': Colors.brown[300],
        };
      case 'Paper':
      default:
        return {
          'paper': const Color(0xFFFFFDF9),
          'sidebar': Colors.brown[700],
          'text': Colors.black,
          'divider': Colors.brown,
        };
    }
  }

  TextStyle _getTextStyle(double fontSize, {bool isBold = false}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontFamily: _currentFont,
      color: _themeData['text'],
    );
  }

  List<Note> get _filteredNotes {
    Iterable<Note> filtered = _notes;
    if (_searchQuery.isNotEmpty) {
      filtered = _notes.where((note) {
        return note.title.contains(_searchQuery) ||
               note.content.contains(_searchQuery) ||
               note.tags.any((tag) => tag.contains(_searchQuery));
      });
    }
    
    final list = filtered.where((n) => !n.isDeleted).toList(); // Filter deleted
    list.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  void _showAddTagDialog() {
    if (_selectedNote == null) return;
    final tagController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 300,
          height: 400,
          decoration: BoxDecoration(
            color: _themeData['paper'],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _themeData['divider']!, width: 2),
          ),
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              // Vertical Title and Input
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MongolText(
                      'ᠱᠢᠪᠢᠰ ᠨᠡᠮᠡᠬᠦ', // Add Tag
                      style: _getTextStyle(20, isBold: true),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: MongolTextField(
                        controller: tagController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'ᠱᠢᠪᠢᠰ...',
                          hintStyle: TextStyle(color: (_themeData['text'] as Color).withAlpha(100)),
                          border: MongolOutlineInputBorder(),
                        ),
                        style: _getTextStyle(18),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 32),
              // Vertical Action Buttons
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MongolIconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
                    onPressed: () {
                      final tag = tagController.text.trim();
                      if (tag.isNotEmpty) {
                        setState(() {
                          if (!_selectedNote!.tags.contains(tag)) {
                            _selectedNote!.tags.add(tag);
                          }
                        });
                        _saveCurrentNote();
                      }
                      Navigator.pop(context);
                    },
                    tooltip: 'Add / ᠨᠡᠮᠡᠬᠦ',
                  ),
                  const SizedBox(height: 24),
                  MongolIconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 40),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Cancel / ᠪᠤᠴᠠᠬᠤ',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Notification Animation
  late AnimationController _notificationController;
  late Animation<Offset> _notificationOffset;
  String _notificationMessage = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _titleFocusNode = FocusNode();
    _contentFocusNode = FocusNode();
    
    // Initialize rich text controller
    _contentController = MongolRichTextController(
      defaultStyle: const TextStyle(fontSize: 18),
    );
    
    _contentController.addListener(_updateStats);
    _contentController.addListener(() {
      if (_contentController.text.isNotEmpty && 
          !_contentController.selection.isCollapsed && 
          _contentController.selection.start >= 0) {
        _lastValidSelection = _contentController.selection;
      }
    });
    _contentFocusNode.addListener(() {
      _isContentFocused.value = _contentFocusNode.hasFocus;
    });
    _titleFocusNode.addListener(() {
      _isTitleFocused.value = _titleFocusNode.hasFocus;
    });
    
    _loadSettings();
    _initializeAppData();

    _notificationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _notificationOffset = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _notificationController,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _searchController.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    _notificationController.dispose();
    _wordCountNotifier.dispose();
    _isContentFocused.dispose();
    _isTitleFocused.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final font = await _storageService.loadFont();
    final theme = await _storageService.loadTheme();
    setState(() {
      if (font != null) {
        // Sanitize font from storage (handle old typos)
        if (font.trim() == 'Utasuuat' || font.trim() == 'Utasuaat') {
          _currentFont = 'Utasuaat';
        } else {
          _currentFont = 'Xinhei';
        }
      }
      if (theme != null) _currentTheme = theme;
    });

    // Check first launch for keyboard prompt
    final isFirst = await _storageService.isFirstLaunch();
    if (isFirst) {
      _showFirstLaunchKeyboardDialog();
    }
  }

  Future<void> _launchKeyboardDownload() async {
    _titleFocusNode.unfocus();
    _contentFocusNode.unfocus();
    final url = Uri.parse('https://www.nmgoyun.com/#/download');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showFirstLaunchKeyboardDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _themeData['paper'],
        title: MongolText('ᠲᠠ ᠰᠠᠶ᠋ᠢᠨ!', style: TextStyle(color: _themeData['text'], fontWeight: FontWeight.bold)), // Prompt / Attention
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MongolText(
              'ᠬᠡᠷᠪᠡ ᠲᠠ ᠮᠣᠩᠭᠣᠯ ᠦᠰᠦᠭ ᠪᠢᠴᠢᠭᠯᠡᠬᠦ ᠠᠷᠭ᠎ᠠ ᠦᠭᠡᠢ ᠪᠣᠯ ᠡᠨᠳᠡ ᠡᠴᠡ ᠲᠠᠲᠠᠵᠤ ᠠᠪᠤᠭᠠᠷᠠᠢ ᠃', // If you don't have Oyun Mongol keyboard, please download here.
              style: TextStyle(color: _themeData['text']),
            )
            
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _storageService.setFirstLaunchComplete();
            },
            child: MongolText('ᠮᠡᠳᠡᠪᠡ', style: TextStyle(color: _themeData['text'])), // Understood/OK
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _storageService.setFirstLaunchComplete();
              _launchKeyboardDownload();
            },
            child: const MongolText('ᠲᠠᠲᠠᠬᠤ', style: TextStyle(color: Colors.blue)), // Download
          ),
        ],
      ),
    );
  }

  Future<void> _initializeAppData() async {
    await _loadNotes();
    FlutterNativeSplash.remove();
  }

  Future<void> _loadNotes() async {
    final notes = await _storageService.loadNotes();
    setState(() {
      _notes = notes;
      // Filter out deleted notes before auto-selecting
      final nonDeleted = _notes.where((n) => !n.isDeleted).toList();
      if (nonDeleted.isNotEmpty && _selectedNote == null) {
        _selectNote(nonDeleted.first);
      } else if (nonDeleted.isEmpty) {
        _selectedNote = null;
        _titleController.clear();
        _contentController.setContent('', []);
      }
    });
  }

  void _selectNote(Note note) {
    setState(() {
      _selectedNote = note;
      _titleController.text = note.title;
      _contentController.setContent(note.content, note.attributes);
      _updateStats();
    });
  }

  void _updateStats() {
    final text = _contentController.text;
    if (text.isEmpty) {
      _wordCountNotifier.value = 0;
      _wordCount = 0;
      return;
    }
    // Simple word count: split by whitespace and filter empties
    final words = text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final count = words.length;
    _wordCountNotifier.value = count;
    _wordCount = count;
  }

  // Format toolbar helper methods
  Widget _buildLabelButton({
    required String label,
    required String tooltip,
    required VoidCallback? onTap,
    bool isEnabled = true,
  }) {
    final bool active = isEnabled && onTap != null;
    return MongolTooltip(
      message: tooltip,
      child: InkWell(
        onTap: active ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36, // Slightly smaller than icon buttons to fit 3 in row
          height: 36,
          decoration: BoxDecoration(
            color: (_themeData['text'] as Color).withAlpha(10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (_themeData['divider'] as Color).withAlpha(50),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: active ? _themeData['text'] : (_themeData['text'] as Color).withAlpha(60),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormatButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool isEnabled = true,
  }) {
    final bool active = isEnabled && onTap != null;
    return MongolTooltip(
      message: tooltip,
      child: InkWell(
        onTap: active ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (_themeData['text'] as Color).withAlpha(10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (_themeData['divider'] as Color).withAlpha(50),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? _themeData['text'] : (_themeData['text'] as Color).withAlpha(60),
          ),
        ),
      ),
    );
  }

  void _applyFormat(String type) {
    if (type == 'B') {
      _contentController.toggleBold();
    } else if (type == 'U') {
      _contentController.toggleUnderline();
    } else if (type == 'CLEAR') {
      _contentController.clearStyles();
    }
    _saveCurrentNote();
  }

  void _applyColor(Color? color) {
    _contentController.applyColor(color);
    _saveCurrentNote();
  }

  void _showFontPicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _themeData['paper'],
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MongolText(
                'ᠦᠰᠦᠭ ᠰᠣᠩᠭᠣᠬᠤ',
                style: _getTextStyle(20, isBold: true),
              ),
              const SizedBox(height: 20),
               ...['Utasuaat', 'Xinhei'].map((font) => ListTile(
                title: Text(
                  font,
                  style: TextStyle(
                    fontFamily: font,
                    color: _themeData['text'],
                  ),
                ),
                leading: Radio<String>(
                  value: font,
                  groupValue: _currentFont,
                  onChanged: (value) async {
                    Navigator.pop(context);
                    if (value != null) {
                      setState(() => _currentFont = value);
                      await _storageService.saveFont(value);
                    }
                  },
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemePicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _themeData['paper'],
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MongolText(
                'ᠦᠩᠭᠡ ᠰᠣᠩᠭᠣᠬᠤ',
                style: _getTextStyle(20, isBold: true),
              ),
              const SizedBox(height: 20),
              ...['Paper', 'Night', 'Nostalgic'].map((theme) => ListTile(
                title: Text(
                  theme,
                  style: TextStyle(color: _themeData['text']),
                ),
                leading: Radio<String>(
                  value: theme,
                  groupValue: _currentTheme,
                  onChanged: (value) async {
                    Navigator.pop(context);
                    if (value != null) {
                      setState(() => _currentTheme = value);
                      await _storageService.saveTheme(value);
                    }
                  },
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _createNewNote() {
    setState(() {
      _selectedNote = null;
      _titleController.clear();
      _contentController.setContent('', []);
    });
    _titleFocusNode.requestFocus();
  }

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    if (_selectedNote == null) {
      if (_notes.isNotEmpty) {
        _selectNote(_notes.first);
      } else {
        setState(() {
          _titleController.clear();
          _contentController.setContent('', []);
        });
      }
    } else {
      // Revert to original content by re-selecting the current note
      _selectNote(_selectedNote!);
    }
  }

  void _deleteCurrentNote() async {
    if (_selectedNote == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _themeData['paper'],
        title: MongolText('ᠠᠷᠠᠰᠢᠯᠠᠬᠤ / Delete?', style: _getTextStyle(20, isBold: true)),
        content: MongolText('ᠡᠨᠡ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ ᠢ ᠠᠷᠠᠰᠢᠯᠠᠬᠤ ᠤᠤ︖ / Delete this note?', style: _getTextStyle(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: MongolText('ᠪᠣᠯᠢᠬᠤ / Cancel', style: TextStyle(color: _themeData['text'])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const MongolText('ᠠᠷᠠᠰᠢᠯᠠᠬᠤ / Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final List<Note> notes = await _storageService.loadNotes();
      // Soft Delete
      final index = notes.indexWhere((n) => n.id == _selectedNote!.id);
      if (index != -1) {
        notes[index].isDeleted = true; // Mark as deleted
        notes[index].updatedAt = DateTime.now(); // Update timestamp for Recycle Bin sort
        await _storageService.saveNotes(notes);
      }
      
      _showNotification('ᠪᠤᠯᠠᠩ ᠳᠤ ᠬᠢᠪᠡ'); // "Moved to Bin" (Approx)
      
      setState(() {
        _notes = notes;
        final nonDeleted = _notes.where((n) => !n.isDeleted).toList();
        if (nonDeleted.isNotEmpty) {
          _selectNote(nonDeleted.first);
        } else {
          _selectedNote = null;
          _titleController.clear();
          _contentController.setContent('', []);
        }
      });

      // Aggressively clear focus after the state transition rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).unfocus();
          // Also explicitly unfocus the nodes just in case
          _titleFocusNode.unfocus();
          _contentFocusNode.unfocus();
        }
      });
    }
  }

  void _showNotification(String message) {
    setState(() {
      _notificationMessage = message;
    });
    _notificationController.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _notificationController.reverse();
    });
  }

  void _saveCurrentNote({bool dismissKeyboard = false}) async {
    final title = _titleController.text;
    final content = _contentController.text;

    if (title.isEmpty && content.isEmpty) return;

    if (dismissKeyboard) {
      FocusScope.of(context).unfocus();
    }

    List<Note> notes = await _storageService.loadNotes();
    
    if (_selectedNote == null) {
      final newNote = Note(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        content: content,
        attributes: List.from(_contentController.attributes),
        updatedAt: DateTime.now(),
      );
      notes.insert(0, newNote);
      _selectedNote = newNote;
    } else {
      final index = notes.indexWhere((n) => n.id == _selectedNote!.id);
      if (index != -1) {
        notes[index].title = title;
        notes[index].content = content;
        notes[index].attributes = List.from(_contentController.attributes);
        notes[index].isPinned = _selectedNote!.isPinned;
        notes[index].tags = List.from(_selectedNote!.tags);
        notes[index].updatedAt = DateTime.now();
        _selectedNote = notes[index];
      }
    }

    await _storageService.saveNotes(notes);
    await _loadNotes();
    _showNotification('ᠬᠠᠳᠠᠭᠠᠯᠠᠪᠠ'); // "Saved" in Mongol
  }

  void _exportToImage() async {
    if (_selectedNote == null) return;
    _titleFocusNode.unfocus();
    _contentFocusNode.unfocus();

    _showNotification('ᠪᠡᠯᠡᠳᠭᠡᠵᠦ ᠪᠠᠢᠨ᠎ᠠ...');

    try {
      final screenHeight = MediaQuery.of(context).size.height;
      
      // Build the export widget in an overlay to render it
      final overlay = OverlayEntry(
        builder: (context) => Positioned(
          left: -10000, // Off-screen
          top: 0,
          child: RepaintBoundary(
            key: _exportKey,
            child: _buildExportWidgetIntrinsic(screenHeight),
          ),
        ),
      );

      Overlay.of(context).insert(overlay);

      // Wait for the widget to fully render
      await Future.delayed(const Duration(milliseconds: 800));

      // Capture the rendered widget
      final RenderRepaintBoundary boundary = _exportKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Remove the overlay
      overlay.remove();

      // Auto-crop: Find the rightmost non-background pixel
      final originalImage = img.decodeImage(pngBytes);
      if (originalImage == null) throw 'Failed to decode image';

      final isNight = _currentTheme == 'Night';
      final br = isNight ? 45 : 255;
      final bg = isNight ? 45 : 253;
      final bb = isNight ? 45 : 249;
      
      // Scan from LEFT to RIGHT to find the maximum X with content
      int maxContentX = 0;
      for (int x = 0; x < originalImage.width; x += 5) {
        for (int y = 0; y < originalImage.height; y += 10) {
          final p = originalImage.getPixel(x, y);
          
          // Check if this pixel is NOT background (with tolerance)
          final rDiff = (p[0] - br).abs();
          final gDiff = (p[1] - bg).abs();
          final bDiff = (p[2] - bb).abs();
          
          if (rDiff > 8 || gDiff > 8 || bDiff > 8) {
            if (x > maxContentX) maxContentX = x;
            break; // Found content in this column, move to next column
          }
        }
      }

      // Add padding and ensure minimum width
      final cropWidth = (maxContentX + 100).clamp(200, originalImage.width);
      
      final croppedImage = img.copyCrop(
        originalImage, 
        x: 0, 
        y: 0, 
        width: cropWidth, 
        height: originalImage.height
      );
      final croppedBytes = Uint8List.fromList(img.encodePng(croppedImage));

      // Save result
      final result = await ImageGallerySaver.saveImage(
        croppedBytes,
        quality: 100,
        name: "MongolNote_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (result['isSuccess']) {
        _showNotification('ᠵᠢᠷᠤᠭ ᠬᠠᠳᠠᠭᠠᠯᠠᠪᠠ');
        
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/note_export.png').create();
        await file.writeAsBytes(croppedBytes);
        await Share.shareXFiles([XFile(file.path)], text: 'ᠮᠣᠩᠭᠣᠯ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ');
      } else {
        _showNotification('ᠠᠯᠳᠠᠭ᠎ᠠ ᠭᠠᠷᠪᠠ');
      }
    } catch (e) {
      _showNotification('ᠠᠯᠳᠠᠭ᠎ᠠ: $e');
    }
  }

  // Helper method to build TextSpan from attribute ranges
  TextSpan _buildFormattedTextSpan(String text, List<AttributeRange> attributeRanges, double fontSize) {
    if (text.isEmpty) return TextSpan(text: '', style: _getTextStyle(fontSize));
    
    final List<TextSpan> children = [];
    final List<AttributeRange> sortedAttrs = List.from(attributeRanges)
      ..sort((a, b) => a.start.compareTo(b.start));

    int currentPos = 0;
    for (final attr in sortedAttrs) {
      final int plainStart = currentPos;
      final int plainEnd = attr.start.clamp(0, text.length);

      if (plainEnd > plainStart) {
        children.add(TextSpan(
          text: text.substring(plainStart, plainEnd),
          style: _getTextStyle(fontSize),
        ));
      }

      final int actualEnd = attr.end.clamp(0, text.length);
      final int actualStart = attr.start.clamp(0, actualEnd);
      
      if (actualEnd > actualStart) {
        children.add(TextSpan(
          text: text.substring(actualStart, actualEnd),
          style: TextStyle(
            fontSize: attr.attribute.fontSize ?? fontSize,
            fontFamily: _currentFont,
            fontWeight: attr.attribute.isBold ? FontWeight.bold : FontWeight.normal,
            decoration: attr.attribute.isUnderline ? TextDecoration.overline : TextDecoration.none,
            color: attr.attribute.color ?? _themeData['text'],
          ),
        ));
      }
      currentPos = actualEnd;
    }

    if (currentPos < text.length) {
      children.add(TextSpan(
        text: text.substring(currentPos),
        style: _getTextStyle(fontSize),
      ));
    }

    return TextSpan(children: children);
  }

  Widget _buildExportWidgetIntrinsic(double height) {
    final isNight = _currentTheme == 'Night';
    final bgColor = isNight ? const Color(0xFF2D2D2D) : const Color(0xFFFFFDF9);

    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Material(
        color: bgColor,
        child: Container(
          height: height,
          padding: const EdgeInsets.all(40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              MongolText(
                _selectedNote!.title.isNotEmpty ? _selectedNote!.title : 'ᠭᠠᠷᠴᠠᠭ ᠦᠭᠡᠢ',
                style: _getTextStyle(24, isBold: true),
              ),
              const SizedBox(width: 40),
              Container(width: 1, color: Colors.grey.withAlpha(100)),
              const SizedBox(width: 40),
              // Tags if any
              if (_selectedNote!.tags.isNotEmpty) ...[
                Wrap(
                  direction: Axis.vertical,
                  spacing: 8,
                  children: _selectedNote!.tags.map((tag) => Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withAlpha(100)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: MongolText(tag, style: _getTextStyle(12)),
                  )).toList(),
                ),
                const SizedBox(width: 20),
              ],
              // Content with formatting
              MongolText.rich(
                _buildFormattedTextSpan(_selectedNote!.content, _selectedNote!.attributes, 18),
              ),
              const SizedBox(width: 40),
              Container(width: 1, color: Colors.grey.withAlpha(100)),
              const SizedBox(width: 40),
              // Date and Footer
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MongolText('ᠮᠣᠩᠭᠣᠯ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ', style: _getTextStyle(12, isBold: false).copyWith(color: Colors.grey)),
                  const SizedBox(height: 10),
                  Text(
                    DateFormat('yyyy-MM-dd').format(_selectedNote!.updatedAt),
                    style: _getTextStyle(10).copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _applyFontSize(double? size) {
    // Verify selection validity
    if (_contentController.selection.isCollapsed || _contentController.selection.start < 0) {
      if (_lastValidSelection != null) {
        _contentController.selection = _lastValidSelection!;
      } else {
      }
    }
    _contentController.applyFontSize(size);
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final File localImage = await File(image.path).copy('${appDir.path}/$fileName');
        _contentController.insertImage(localImage.path);
      }
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    
    return Scaffold(
      backgroundColor: _themeData['paper'],
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
              Column(
              children: [
                  // Top Section: Editor
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      color: _themeData['paper'],
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            IntrinsicWidth(
                              child: MongolTextField(
                                controller: _titleController,
                                focusNode: _titleFocusNode,
                                maxLines: null,
                                decoration: InputDecoration(
                                  hintText: 'ᠭᠠᠷᠴᠠᠭ',
                                  hintStyle: TextStyle(color: (_themeData['text'] as Color).withAlpha(100)),
                                  border: InputBorder.none,
                                ),
                                style: _getTextStyle(22, isBold: true),
                              ),
                            ),
                            VerticalDivider(width: 20, thickness: 1, color: _themeData['divider']),
                            // Tags Display (Between Title and Content)
                            if (_selectedNote != null && _selectedNote!.tags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 16.0),
                                child: Wrap(
                                  direction: Axis.vertical,
                                  spacing: 12.0, 
                                  runSpacing: 12.0,
                                  children: _selectedNote!.tags.map((tag) => Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: (_themeData['divider'] as Color).withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: _themeData['divider']!.withAlpha(100)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        MongolText(tag, style: _getTextStyle(12)),
                                        const SizedBox(height: 4),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedNote!.tags.remove(tag);
                                            });
                                            _saveCurrentNote();
                                          },
                                          child: Icon(Icons.close, size: 14, color: _themeData['divider']),
                                        ),
                                      ],
                                    ),
                                  )).toList(),
                                ),
                              ),
                            IntrinsicWidth(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: MediaQuery.of(context).size.width - 150,
                                ),
                                child: MongolTextField(
                                  controller: _contentController,
                                  focusNode: _contentFocusNode,
                                  maxLines: null,
                                  decoration: InputDecoration(
                                    hintText: 'ᠪᠢᠴᠢᠭ᠌ ᠪᠢᠴᠢᠬᠦ...',
                                    hintStyle: TextStyle(color: (_themeData['text'] as Color).withAlpha(100)),
                                    border: InputBorder.none,
                                  ),
                                  style: _getTextStyle(18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!isKeyboardOpen || _isSearchVisible) ...[
                    Divider(height: 1, thickness: 2, color: _themeData['divider']),
                    SizedBox(
                      height: screenHeight * 0.38,
                      child: Row(
                        children: [
                          // Vertical Sidebar
                          Container(
                            width: 70,
                            color: _themeData['sidebar'],
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  const MongolText(
                                    'ᠮᠣᠩᠭᠣᠯ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  // Search Toggle
                                  MongolIconButton(
                                    icon: Icon(
                                      _isSearchVisible ? Icons.search_off : Icons.search,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isSearchVisible = !_isSearchVisible;
                                        if (!_isSearchVisible) {
                                          _searchQuery = '';
                                          _searchController.clear();
                                        }
                                      });
                                    },
                                    tooltip: 'Search / ᠬᠠᠢᠬᠤ',
                                  ),
                                  const SizedBox(height: 12),
                                  // Stats Display
                                  ValueListenableBuilder<int>(
                                    valueListenable: _wordCountNotifier,
                                    builder: (context, count, _) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Column(
                                          children: [
                                             const MongolText('ᠦᠭᠡ', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                            Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  // Pin Toggle
                                  MongolIconButton(
                                    icon: Icon(
                                      _selectedNote?.isPinned == true ? Icons.push_pin : Icons.push_pin_outlined,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      if (_selectedNote != null) {
                                        setState(() {
                                          _selectedNote!.isPinned = !_selectedNote!.isPinned;
                                        });
                                        _saveCurrentNote();
                                      }
                                    },
                                    tooltip: 'Pin / ᠬᠠᠳᠠᠬᠤ',
                                  ),
                                  const SizedBox(height: 12),
                                  // Export Button
                                  MongolIconButton(
                                    icon: const Icon(Icons.share, color: Colors.white),
                                    onPressed: _exportToImage,
                                    tooltip: 'Export / ᠭᠠᠷᠭᠠᠬᠤ',
                                  ),
                                  const SizedBox(height: 12),
                                  // Add Tag
                                  MongolIconButton(
                                    icon: const Icon(Icons.label_outline, color: Colors.white),
                                    onPressed: _showAddTagDialog,
                                    tooltip: 'Tag / ᠱᠢᠪᠢᠰ',
                                  ),
                                  const SizedBox(height: 12),
                                  // Settings (Theme & Font)
                                  MongolPopupMenuButton<String>(
                                    icon: const Icon(Icons.palette, color: Colors.white),
                                    tooltip: 'Style / ᠬᠡᠯᠪᠡᠷ',
                                      onSelected: (value) async {
                                        _titleFocusNode.unfocus();
                                        _contentFocusNode.unfocus();
                                        setState(() {
                                          if (['Paper', 'Night', 'Nostalgic'].contains(value)) {
                                            _currentTheme = value;
                                          } else {
                                            _currentFont = value;
                                          }
                                        });
                                        if (['Paper', 'Night', 'Nostalgic'].contains(value)) {
                                          await _storageService.saveTheme(value);
                                        } else {
                                          await _storageService.saveFont(value);
                                        }
                                      },
                                    itemBuilder: (context) => [
                                      const MongolPopupMenuItem(
                                        enabled: false,
                                        child: MongolText('Themes', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      MongolPopupMenuItem(
                                        value: 'Paper',
                                        child: Column(
                                          children: [
                                            const MongolText('Paper'),
                                            if (_currentTheme == 'Paper') const Icon(Icons.check, size: 14),
                                          ],
                                        ),
                                      ),
                                      MongolPopupMenuItem(
                                        value: 'Night',
                                        child: Column(
                                          children: [
                                            const MongolText('Night'),
                                            if (_currentTheme == 'Night') const Icon(Icons.check, size: 14),
                                          ],
                                        ),
                                      ),
                                      MongolPopupMenuItem(
                                        value: 'Nostalgic',
                                        child: Column(
                                          children: [
                                            const MongolText('Nostalgic'),
                                            if (_currentTheme == 'Nostalgic') const Icon(Icons.check, size: 14),
                                          ],
                                        ),
                                      ),
                                      const MongolPopupMenuDivider(),
                                      const MongolPopupMenuItem(
                                        enabled: false,
                                        child: MongolText('Fonts', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      MongolPopupMenuItem(
                                        value: 'Utasuaat',
                                        child: Column(
                                          children: [
                                            const MongolText('Utasuaat'),
                                            if (_currentFont == 'Utasuaat') const Icon(Icons.check, size: 14),
                                          ],
                                        ),
                                      ),
                                      MongolPopupMenuItem(
                                        value: 'Xinhei',
                                        child: Column(
                                          children: [
                                            const MongolText('Xinhei'),
                                            if (_currentFont == 'Xinhei') const Icon(Icons.check, size: 14),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                   // Recycle Bin (3rd from bottom)
                                  MongolIconButton(
                                    icon: const Icon(Icons.auto_delete, color: Colors.white),
                                    onPressed: () async {
                                      _titleFocusNode.unfocus();
                                      _contentFocusNode.unfocus();
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RecycleBinScreen(
                                            storageService: _storageService,
                                            initialTheme: _currentTheme,
                                            initialFont: _currentFont,
                                          ),
                                        ),
                                      );
                                      _loadNotes(); // Refresh to reflect restorations/deletions
                                    },
                                    tooltip: 'Bin / ᠪᠤᠯᠠᠩ',
                                  ),
                                  const SizedBox(height: 12),
                                  // Cloud Backup (2nd from bottom)
                                  MongolIconButton(
                                    icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                                    onPressed: () {
                                      _titleFocusNode.unfocus();
                                      _contentFocusNode.unfocus();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => SettingsScreen(
                                            storageService: _storageService,
                                            initialTheme: _currentTheme,
                                            initialFont: _currentFont,
                                          ),
                                        ),
                                      ).then((_) {
                                        _loadNotes(); // Refresh in case of restore
                                      });
                                    },
                                    tooltip: 'Backup / ᠨᠡᠭᠡᠴᠢᠯᠡᠬᠦ',
                                  ),
                                  const SizedBox(height: 12),
                                  // Oyun Keyboard (Bottom)
                                  MongolIconButton(
                                    icon: const Icon(Icons.keyboard, color: Colors.white70),
                                    onPressed: _launchKeyboardDownload,
                                    tooltip: 'ᠮᠣᠩᠭᠣᠯ ᠦᠰᠦᠭ ᠪᠢᠴᠢᠭᠯᠡᠬᠦ ᠠᠷᠭ᠎ᠠ / Mongol Keyboard',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Vertical Search Panel
                          if (_isSearchVisible)
                            Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: (_themeData['sidebar'] as Color).withAlpha(30),
                                border: Border(right: BorderSide(color: _themeData['divider'])),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: MongolTextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        hintText: 'ᠬᠠᠢᠬᠤ...',
                                        hintStyle: TextStyle(color: (_themeData['text'] as Color).withAlpha(100), fontSize: 14),
                                        border: InputBorder.none,
                                      ),
                                      style: _getTextStyle(16),
                                      onChanged: (value) {
                                        setState(() {
                                          _searchQuery = value;
                                        });
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close, size: 20, color: _themeData['divider']),
                                    onPressed: () {
                                      setState(() {
                                        _isSearchVisible = false;
                                        _searchQuery = '';
                                        _searchController.clear();
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          // Note List
                          if (!isKeyboardOpen)
                            Expanded(
                              child: _filteredNotes.isEmpty
                                  ? Center(child: MongolText('ᠲᠡᠮᠳᠡᠭᠯᠡᠯ ᠪᠠᠢᠭᠤᠢ', style: TextStyle(color: _themeData['text'])))
                                  : ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.all(12),
                                      itemCount: _filteredNotes.length,
                                      itemBuilder: (context, index) {
                                        final note = _filteredNotes[index];
                                        final isSelected = _selectedNote?.id == note.id;
                                        return GestureDetector(
                                          onTap: () => _selectNote(note),
                                          child: Container(
                                            width: 130,
                                            margin: const EdgeInsets.only(right: 12),
                                            child: Card(
                                              elevation: isSelected ? 8 : 2,
                                              color: isSelected ? (_themeData['text'] as Color).withAlpha(20) : _themeData['paper'],
                                              shape: isSelected
                                                  ? RoundedRectangleBorder(
                                                      side: BorderSide(color: _themeData['divider'], width: 2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    )
                                                  : null,
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Stack(
                                                  children: [
                                                    Column(
                                                      children: [
                                                        Expanded(
                                                          child: MongolText(
                                                            note.title.isNotEmpty ? note.title : 'ᠭᠠᠷᠴᠠᠭ ᠦᠭᠡᠢ',
                                                            style: _getTextStyle(15, isBold: isSelected),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        Divider(height: 8, color: _themeData['divider']),
                                                        Text(
                                                          DateFormat('MM/dd').format(note.updatedAt),
                                                          style: TextStyle(fontSize: 10, color: (_themeData['text'] as Color).withAlpha(150)),
                                                        ),
                                                      ],
                                                    ),
                                                    if (note.isPinned)
                                                      Positioned(
                                                        top: 0,
                                                        right: 0,
                                                        child: Icon(
                                                          Icons.push_pin,
                                                          size: 14,
                                                          color: Colors.amber[700],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              // Custom Vertical Notification (slides in from right border of bottom section)
              if (!isKeyboardOpen)
                Positioned(
                  right: 0,
                  bottom: screenHeight * 0.1, // Positioned near the bottom note list
                  child: SlideTransition(
                    position: _notificationOffset,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.brown[800]?.withAlpha((0.9 * 255).round()),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.3 * 255).round()),
          blurRadius: 10,
                            offset: const Offset(-2, 0),
                          ),
                        ],
                      ),
                      child: MongolText(
                        _notificationMessage,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              // Floating Formatting Toolbar (now contextual and unified)
              ValueListenableBuilder<bool>(
                valueListenable: _isContentFocused,
                builder: (context, contentFocused, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _isTitleFocused,
                    builder: (context, titleFocused, _) {
                      final bool showToolbar = contentFocused || titleFocused;
                      if (!showToolbar) return const SizedBox.shrink();

                      return Positioned(
                        right: 20,
                        top: isKeyboardOpen ? 40 : 80,
                        bottom: isKeyboardOpen ? (MediaQuery.of(context).viewInsets.bottom + 10) : null,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _themeData['paper'].withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                            border: Border.all(color: _themeData['divider']!, width: 1),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Toolbar Actions
                                _buildFormatButton(
                                  icon: Icons.close,
                                  tooltip: 'ᠪᠣᠯᠢᠬᠤ / Cancel',
                                  onTap: _cancelEdit,
                                ),
                                const SizedBox(height: 12),
                                // "Done/Save" button - always visible in toolbar
                                _buildFormatButton(
                                  icon: Icons.check,
                                  tooltip: 'ᠬᠠᠳᠠᠭᠠᠯᠠᠬᠤ / Save',
                                  onTap: () => _saveCurrentNote(dismissKeyboard: true),
                                ),
                                const SizedBox(height: 12),
                                _buildFormatButton(
                                  icon: Icons.delete_outline,
                                  tooltip: 'ᠠᠷᠠᠰᠢᠯᠠᠬᠤ / Delete',
                                  onTap: _selectedNote != null ? _deleteCurrentNote : null,
                                  isEnabled: _selectedNote != null,
                                ),
                              
                              // If content is focused, show rich text tools
                              if (contentFocused) ...[
                                const SizedBox(height: 12),
                                ListenableBuilder(
                                  listenable: _contentController,
                                  builder: (context, _) {
                                    return _buildFormatButton(
                                      icon: Icons.undo,
                                      tooltip: 'ᠪᠠᠴᠠᠭᠠᠬᠤ / Undo',
                                      onTap: _contentController.canUndo ? () => _contentController.undo() : null,
                                      isEnabled: _contentController.canUndo,
                                    );
                                  }
                                ),
                                const SizedBox(height: 12),
                                ListenableBuilder(
                                  listenable: _contentController,
                                  builder: (context, _) {
                                    return _buildFormatButton(
                                      icon: Icons.redo,
                                      tooltip: 'ᠳᠠᠬᠢᠨ ᠦᠢᠯᠡᠳᠬᠦ / Redo',
                                      onTap: _contentController.canRedo ? () => _contentController.redo() : null,
                                      isEnabled: _contentController.canRedo,
                                    );
                                  }
                                ),
                                const SizedBox(height: 12),
                                const Divider(height: 1, thickness: 1),
                                const SizedBox(height: 12),
                                _buildFormatButton(
                                  icon: Icons.format_bold,
                                  tooltip: 'B',
                                  onTap: () => _applyFormat('B'),
                                ),
                                const SizedBox(height: 12),
                                _buildFormatButton(
                                  icon: Icons.format_underline,
                                  tooltip: 'U',
                                  onTap: () => _applyFormat('U'),
                                ),
                                const SizedBox(height: 12),
                                const SizedBox(height: 12),
                                const Divider(height: 1, thickness: 1),
                                const SizedBox(height: 12),
                                // Text Size
                                // Text Size Buttons
                                const SizedBox(height: 12),
                                Column(
                                  children: [
                                    _buildLabelButton(
                                      label: 'S',
                                      tooltip: 'Small / ᠪᠠᠭᠠ (18)',
                                      onTap: () => _applyFontSize(18.0),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildLabelButton(
                                      label: 'M',
                                      tooltip: 'Medium / ᠳᠤᠮᠳᠠ (24)',
                                      onTap: () => _applyFontSize(24.0),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildLabelButton(
                                      label: 'L',
                                      tooltip: 'Large / ᠶᠡᠬᠡ (32)',
                                      onTap: () => _applyFontSize(32.0),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                /* 
                                // Image Insertion - Disabled due to lack of WidgetSpan support in MongolTextField
                                _buildFormatButton(
                                  icon: Icons.image_outlined,
                                  tooltip: 'ᠵᠢᠷᠤᠭ / Image',
                                  onTap: _pickImage,
                                ),
                                const SizedBox(height: 12),
                                */
                                const Divider(height: 1, thickness: 1),
                                const SizedBox(height: 12),
                                ...[Colors.red, Colors.blue, Colors.green, Colors.black].map((color) => 
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: MongolTooltip(
                                      message: color == Colors.red ? 'ᠤᠯᠠᠭᠠᠨ / Red' : 
                                               color == Colors.blue ? 'ᠬᠦᠬᠡ / Blue' :
                                               color == Colors.green ? 'ᠨᠣᠭᠣᠭᠠᠨ / Green' : 'ᠬᠠᠷᠠ / Black',
                                      child: GestureDetector(
                                        onTap: () => _applyColor(color),
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ).toList(),
                                const SizedBox(height: 4),
                                _buildFormatButton(
                                  icon: Icons.format_color_reset,
                                  tooltip: 'Reset Color',
                                  onTap: () => _applyColor(null),
                                ),
                                const SizedBox(height: 12),
                                _buildFormatButton(
                                  icon: Icons.format_clear,
                                  tooltip: 'Clear All',
                                  onTap: () => _applyFormat('CLEAR'),
                                ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      floatingActionButton: !isKeyboardOpen ? FloatingActionButton(
        onPressed: _createNewNote,
        backgroundColor: _themeData['sidebar'],
        tooltip: 'ᠰᠢᠨᠡ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ / New Note',
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }
}
