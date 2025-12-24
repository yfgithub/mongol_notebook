import 'package:flutter/material.dart';
import 'package:mongol/mongol.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../services/storage_service.dart';

class RecycleBinScreen extends StatefulWidget {
  final StorageService storageService;
  final String? initialTheme;
  final String? initialFont;

  const RecycleBinScreen({super.key, required this.storageService, this.initialTheme, this.initialFont});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> with SingleTickerProviderStateMixin {
  List<Note> _deletedNotes = [];
  Note? _selectedNote;
  bool _isLoading = true;

  late AnimationController _notificationController;
  late Animation<Offset> _notificationOffset;
  String _notificationMessage = '';

  late String _currentTheme;
  late String _currentFont;
  
  Map<String, dynamic> get _themeData {
    switch (_currentTheme) {
      case 'Night':
        return {
          'paper': const Color(0xFF2D2D2D),
          'sidebar': const Color(0xFF1A1A1A),
          'text': Colors.white,
          'divider': Colors.grey[800]!,
        };
      case 'Nostalgic':
        return {
          'paper': const Color(0xFFF4ECD8),
          'sidebar': const Color(0xFF5D4037),
          'text': const Color(0xFF3E2723),
          'divider': Colors.brown[300]!,
        };
      case 'Paper':
      default:
        return {
          'paper': const Color(0xFFFFFDF9),
          'sidebar': Colors.brown[700]!,
          'text': Colors.black,
          'divider': Colors.brown,
        };
    }
  }

  @override
  void initState() {
    super.initState();
    _currentTheme = widget.initialTheme ?? 'Paper';
    _currentFont = widget.initialFont ?? 'Xinhei';
    _loadSettings();
    _loadDeletedNotes();

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
    _notificationController.dispose();
    super.dispose();
  }

  void _showNotification(String message) {
    if (!mounted) return;
    setState(() {
      _notificationMessage = message;
    });
    _notificationController.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _notificationController.reverse();
    });
  }

  Future<void> _loadSettings() async {
    final theme = await widget.storageService.loadTheme();
    final font = await widget.storageService.loadFont();
    if (mounted) {
      setState(() {
        if (theme != null) _currentTheme = theme;
        if (font != null) {
          if (font.trim() == 'Utasuuat' || font.trim() == 'Utasuaat') {
            _currentFont = 'Utasuaat';
          } else {
            _currentFont = 'Xinhei';
          }
        }
      });
    }
  }

  Future<void> _loadDeletedNotes() async {
    setState(() => _isLoading = true);
    final allNotes = await widget.storageService.loadNotes();
    setState(() {
      _deletedNotes = allNotes.where((n) => n.isDeleted).toList();
      _deletedNotes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      
      // Update selection: if current selected is gone or null, pick first available
      if (_deletedNotes.isEmpty) {
        _selectedNote = null;
      } else if (_selectedNote == null || !_deletedNotes.any((n) => n.id == _selectedNote!.id)) {
        _selectedNote = _deletedNotes.first;
      }
      
      _isLoading = false;
    });
  }

  Future<void> _restoreNote(Note note) async {
    final allNotes = await widget.storageService.loadNotes();
    final index = allNotes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      allNotes[index].isDeleted = false;
      allNotes[index].updatedAt = DateTime.now(); 
      await widget.storageService.saveNotes(allNotes);
      await _loadDeletedNotes();
      
      if (mounted) {
        _showNotification('ᠰᠡᠷᠭᠦᠭᠡᠪᠡ'); // Restored
      }
    }
  }

  Future<void> _permanentlyDelete(Note note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _themeData['paper'],
        title: MongolText('ᠠᠷᠠᠰᠢᠯᠠᠬᠤ', style: TextStyle(color: _themeData['text'], fontWeight: FontWeight.bold)), 
        content: MongolText('ᠡᠨᠡ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ ᠢ ᠪᠦᠷᠮᠦᠰᠦᠨ ᠠᠷᠠᠰᠢᠯᠠᠬᠤ ᠤᠤ︖', style: TextStyle(color: _themeData['text'])), 
        actions: [
           TextButton(onPressed: () => Navigator.pop(context, false), child: MongolText('ᠪᠣᠯᠢᠬᠤ', style: TextStyle(color: _themeData['text']))),
           TextButton(onPressed: () => Navigator.pop(context, true), child: const MongolText('ᠠᠷᠠᠰᠢᠯᠠᠬᠤ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final allNotes = await widget.storageService.loadNotes();
      allNotes.removeWhere((n) => n.id == note.id);
      await widget.storageService.saveNotes(allNotes);
      if (_selectedNote?.id == note.id) _selectedNote = null;
      _loadDeletedNotes();
      _showNotification('ᠠᠷᠠᠰᠢᠯᠠᠪᠠ'); // Deleted permanently
    }
  }

  Future<void> _emptyBin() async {
    if (_deletedNotes.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _themeData['paper'],
        title: MongolText('ᠪᠤᠯᠠᠩ ᠴᠡᠪᠡᠷᠯᠡᠬᠦ', style: TextStyle(color: _themeData['text'], fontWeight: FontWeight.bold)), 
        content: MongolText('ᠪᠦᠬᠦ ᠲᠡᠮᠳᠡᠭᠯᠡᠯ ᠢ ᠪᠦᠷᠮᠦᠰᠦᠨ ᠠᠷᠠᠰᠢᠯᠠᠬᠤ ᠤᠤ︖', style: TextStyle(color: _themeData['text'])), 
        actions: [
           TextButton(onPressed: () => Navigator.pop(context, false), child: MongolText('ᠪᠣᠯᠢᠬᠤ', style: TextStyle(color: _themeData['text']))),
           TextButton(onPressed: () => Navigator.pop(context, true), child: const MongolText('ᠴᠡᠪᠡᠷᠯᠡᠬᠦ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final allNotes = await widget.storageService.loadNotes();
      allNotes.removeWhere((n) => n.isDeleted);
      await widget.storageService.saveNotes(allNotes);
      _selectedNote = null;
      _loadDeletedNotes();
      _showNotification('ᠴᠡᠪᠡᠷᠯᠡᠪᠡ'); // Cleaned/Emptied
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: MongolText(message, style: const TextStyle(color: Colors.white)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  TextSpan _buildFormattedTextSpan(String text, List<AttributeRange> attributeRanges) {
    if (text.isEmpty) return const TextSpan(text: '');
    final List<TextSpan> children = [];
    final List<AttributeRange> sortedAttrs = List.from(attributeRanges)..sort((a, b) => a.start.compareTo(b.start));
    int currentPos = 0;
    for (final attr in sortedAttrs) {
      if (attr.start > currentPos) {
        children.add(TextSpan(text: text.substring(currentPos, attr.start)));
      }
      final int actualEnd = attr.end.clamp(0, text.length);
      final int actualStart = attr.start.clamp(0, actualEnd);
      if (actualEnd > actualStart) {
        children.add(TextSpan(
          text: text.substring(actualStart, actualEnd),
          style: TextStyle(
            fontWeight: attr.attribute.isBold ? FontWeight.bold : FontWeight.normal,
            decoration: attr.attribute.isUnderline ? TextDecoration.overline : TextDecoration.none,
            color: attr.attribute.color,
            fontSize: attr.attribute.fontSize,
          ),
        ));
      }
      currentPos = actualEnd;
    }
    if (currentPos < text.length) children.add(TextSpan(text: text.substring(currentPos)));
    return TextSpan(children: children, style: TextStyle(fontSize: 18, color: _themeData['text'], fontFamily: _currentFont));
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: _themeData['paper'],
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
          Column(
            children: [
          // 1. TOP AREA (Large - Preview)
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              child: _selectedNote == null
                  ? Center(child: MongolText('ᠬᠣᠭᠣᠰᠣᠨ', style: TextStyle(fontSize: 24, color: Colors.grey[400])))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MongolText(
                            _selectedNote!.title.isNotEmpty ? _selectedNote!.title : 'ᠭᠠᠷᠴᠠᠭ ᠦᠭᠡᠢ',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _themeData['text']),
                          ),
                          const SizedBox(width: 40),
                          Container(width: 1, color: (_themeData['divider'] as Color).withAlpha(50)),
                          const SizedBox(width: 40),
                          MongolText.rich(
                            _buildFormattedTextSpan(_selectedNote!.content, _selectedNote!.attributes),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          
          Divider(height: 1, thickness: 2, color: _themeData['divider']),

          // 2. BOTTOM AREA (Small - 0.38 ratio overlap conceptually)
          SizedBox(
            height: screenHeight * 0.38,
            child: Row(
              children: [
                // sidebar (Left)
                Container(
                  width: 70,
                  color: _themeData['sidebar'],
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Back Button
                      MongolIconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'ᠪᠤᠴᠠᠬᠤ',
                      ),
                      const Spacer(),
                      // Empty Bin Button
                      MongolIconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        onPressed: _deletedNotes.isEmpty ? null : _emptyBin,
                        tooltip: 'Empty Bin / ᠴᠡᠪᠡᠷᠯᠡᠬᠦ',
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                
                // Deleted List (Right)
                Expanded(
                  child: Container(
                    color: (_themeData['text'] as Color).withAlpha(10), // Adaptive subtle contrast
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator())
                      : _deletedNotes.isEmpty
                        ? Center(child: MongolText('ᠲᠡᠮᠳᠡᠭᠯᠡᠯ ᠪᠠᠢᠭᠤᠢ', style: TextStyle(color: _themeData['text'])))
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.all(12),
                            itemCount: _deletedNotes.length,
                            itemBuilder: (context, index) {
                              final note = _deletedNotes[index];
                              final isSelected = _selectedNote?.id == note.id;
                              
                              return Container(
                                width: 150,
                                margin: const EdgeInsets.only(right: 12),
                                child: Column(
                                  children: [
                                    // Card Portion
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() => _selectedNote = note),
                                        child: Card(
                                          elevation: isSelected ? 8 : 2,
                                          color: isSelected 
                                            ? (_themeData['text'] as Color).withAlpha(30) 
                                            : _themeData['paper'],
                                          shape: isSelected
                                              ? RoundedRectangleBorder(
                                                  side: BorderSide(color: _themeData['divider'], width: 2),
                                                  borderRadius: BorderRadius.circular(8),
                                                )
                                              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Column(
                                              children: [
                                                Expanded(
                                                  child: MongolText(
                                                    note.title.isNotEmpty ? note.title : 'ᠭᠠᠷᠴᠠᠭ ᠦᠭᠡᠢ',
                                                    style: TextStyle(
                                                      fontSize: 15, 
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                      color: _themeData['text'],
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const Divider(height: 8),
                                                Text(
                                                  DateFormat('MM/dd').format(note.updatedAt),
                                                  style: TextStyle(fontSize: 10, color: (_themeData['text'] as Color).withAlpha(150)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Action Buttons Underneath
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        // Restore
                                        Tooltip(
                                          message: 'Restore / ᠰᠡᠷᠭᠦᠭᠡᠬᠦ',
                                          child: InkWell(
                                            onTap: () => _restoreNote(note),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              width: 44, height: 44,
                                              decoration: BoxDecoration(
                                                color: Colors.green.withAlpha(30),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.green.withAlpha(100)),
                                              ),
                                              child: const Icon(Icons.restore, color: Colors.green, size: 20),
                                            ),
                                          ),
                                        ),
                                        // Delete Forever
                                        Tooltip(
                                          message: 'Delete Permanently / ᠠᠷᠠᠰᠢᠯᠠᠬᠤ',
                                          child: InkWell(
                                            onTap: () => _permanentlyDelete(note),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              width: 44, height: 44,
                                              decoration: BoxDecoration(
                                                color: Colors.red.withAlpha(30),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.red.withAlpha(100)),
                                              ),
                                              child: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
            ],
          ),
          // Custom Vertical Notification (slides in from right border of bottom section)
          Positioned(
            right: 0,
            bottom: screenHeight * 0.1, // Match HomeScreen positioning
            child: SlideTransition(
              position: _notificationOffset,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: (_themeData['sidebar'] as Color).withAlpha((0.9 * 255).round()),
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
        ],
      ),
    ));
  }
}
