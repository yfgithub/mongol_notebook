import 'package:flutter/material.dart';
import 'package:mongol/mongol.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/storage_service.dart';
import '../services/backup_service.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storageService;
  final String? initialTheme;
  final String? initialFont;
  
  const SettingsScreen({super.key, required this.storageService, this.initialTheme, this.initialFont});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backupService = BackupService();
  bool _isLoading = false;
  String _statusMessage = '';
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
  }

  void _setStatus(String msg) {
    setState(() {
      _statusMessage = msg;
    });
  }

  Future<void> _backupAndShare() async {
    setState(() => _isLoading = true);
    _setStatus('Preparing backup...');
    try {
      final notes = await widget.storageService.loadNotes();
      if (notes.isEmpty) {
        _setStatus('❌ No notes to backup.');
        setState(() => _isLoading = false);
        return;
      }

      final zipPath = await _backupService.createBackup(notes);
      
      _setStatus('✅ Backup created. Sharing...');
      
      // Share Sheet
      final result = await Share.shareXFiles(
        [XFile(zipPath)],
        text: 'Mongol Notebook Backup',
      );
      
      if (result.status == ShareResultStatus.success) {
        _setStatus('✅ Backup shared successfully.');
      } else if (result.status == ShareResultStatus.dismissed) {
        _setStatus('Backup saved to temp (Share dismissed).');
      }
      
    } catch (e) {
      _setStatus('❌ Backup failed: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _restoreFromFile() async {
    setState(() => _isLoading = true);
    _setStatus('Select backup file...');
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        
        // Confirm Dialog
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore Mode / ᠰᠡᠷᠭᠦᠭᠡᠬᠦ'),
            content: const Text(
                'How should we restore?\n\n'
                '• MERGE: Keep new notes, overwrite existing ones with backup version.\n'
                '• REPLACE: Delete ALL local notes and use backup exactly.'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false), // Cancel
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true), // Treat true as Merge
                child: const Text('MERGE (Safe)'),
              ),
            ],
          ),
        );

        if (confirm != null) { // User chose Merge (true)
          _setStatus('Restoring...');
          
          final restoredNotes = await _backupService.restoreBackup(filePath, widget.storageService);
          final currentNotes = await widget.storageService.loadNotes();
          
          // Merge Logic: 
          // 1. Create a map of current notes for easy lookup
          final currentMap = {for (var n in currentNotes) n.id: n};
          
          // 2. Overwrite/Add from backup
          for (var note in restoredNotes) {
            currentMap[note.id] = note;
          }
          
          // 3. Convert back to list (New notes created AFTER backup are preserved in currentMap if they have unique IDs)
          // Wait, if note was NOT in backup, it stays in map? Yes.
          // Example: 
          // Backup: [A, B]
          // Current: [A, B, C(new)]
          // Result: [A(backup), B(backup), C(new)]
          // This is exactly what the user wants.
          
          final finalNotes = currentMap.values.toList();
          
          // Sort by updated time desc
          finalNotes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          await widget.storageService.saveNotes(finalNotes);
          
          _setStatus('✅ Restore complete! (Merged)');
           if (mounted) {
             Future.delayed(const Duration(seconds: 1), () {
                if (mounted) Navigator.pop(context, true);
             });
           }
        }
      } else {
        _setStatus('Restore cancelled.');
      }
    } catch (e) {
      _setStatus('❌ Restore failed');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore Error / ᠠᠯᠳᠠᠭ᠎ᠠ'),
            content: SingleChildScrollView(child: Text(e.toString())),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _themeData['paper'],
      appBar: AppBar(
        title: MongolText('Backup & Restore / ᠬᠠᠳᠠᠭᠠᠯᠠᠬᠤ ᠪᠠ ᠰᠡᠷᠭᠦᠭᠡᠬᠦ', style: TextStyle(color: _themeData['text'], fontFamily: _currentFont)),
        backgroundColor: _themeData['paper'],
        elevation: 1,
        leading: IOExceptionButton(
          onPressed: () => Navigator.pop(context),
          color: _themeData['text'],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            // Backup Section
            _buildCard(
              icon: Icons.upload_file,
              title: 'Backup to File',
              subtitle: 'Export all notes to a ZIP file. Save to Files or Share.',
              buttonText: 'Export Backup',
              color: Colors.blue.shade50,
              onTap: _isLoading ? null : _backupAndShare,
            ),
            const SizedBox(height: 20),
            // Restore Section
            _buildCard(
              icon: Icons.download_for_offline,
              title: 'Restore from File',
              subtitle: 'Import a backup ZIP file. Overwrites current notes.',
              buttonText: 'Import Backup',
              color: Colors.orange.shade50,
              onTap: _isLoading ? null : _restoreFromFile,
            ),
            const Spacer(),
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _statusMessage.startsWith('❌') ? Colors.red : Colors.green[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.black54),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

class IOExceptionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;
  const IOExceptionButton({super.key, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: color ?? Colors.black),
      onPressed: onPressed,
    );
  }
}
