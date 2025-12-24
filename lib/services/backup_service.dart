import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import 'storage_service.dart';

class BackupService {
  
  Future<String> createBackup(List<Note> notes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final backupDir = Directory('${tempDir.path}/backup_temp');
      if (await backupDir.exists()) await backupDir.delete(recursive: true);
      await backupDir.create();

      // 1. Save Notes JSON
      final notesJson = jsonEncode(notes.map((n) => n.toJson()).toList());
      final notesFile = File('${backupDir.path}/notes.json');
      await notesFile.writeAsString(notesJson);

      // 2. Identify and Copy Images
      final imagesDir = Directory('${backupDir.path}/images');
      await imagesDir.create();
      
      int imageCount = 0;
      for (var note in notes) {
        for (var attr in note.attributes) {
           if (attr.attribute.imagePath != null) {
             final File imgFile = File(attr.attribute.imagePath!);
             if (await imgFile.exists()) {
               final fileName = path.basename(imgFile.path);
               await imgFile.copy('${imagesDir.path}/$fileName');
               imageCount++;
             }
           }
        }
      }
      print('Backup: Collected $imageCount images.');

      // 3. Create Zip (Manual Addition)
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final zipFileName = 'mongol_notebook_backup_$timestamp.zip';
      final zipFilePath = '${tempDir.path}/$zipFileName';

      var encoder = ZipFileEncoder();
      encoder.create(zipFilePath);
      
      // Add notes.json at root
      await encoder.addFile(notesFile);
      
      // Add images folder
      if (imageCount > 0) {
        final images = imagesDir.listSync();
        for (var img in images) {
          if (img is File) {
            await encoder.addFile(img, 'images/${path.basename(img.path)}');
          }
        }
      }
      
      encoder.close();

      // Cleanup temp
      await backupDir.delete(recursive: true);

      return zipFilePath;
    } catch (e) {
      print('Backup Error: $e');
      throw e;
    }
  }

  Future<List<Note>> restoreBackup(String zipPath, StorageService storageService) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final restoreDir = Directory('${tempDir.path}/restore_extracted');
      if (await restoreDir.exists()) await restoreDir.delete(recursive: true);
      await restoreDir.create();

      // 1. Unzip
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File('${restoreDir.path}/$filename')
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory('${restoreDir.path}/$filename').create(recursive: true);
        }
      }

      // 2. Find notes.json (recursively, in case of nested folders)
      File? notesFile;
      Directory? baseDir;
      
      await for (final entity in restoreDir.list(recursive: true)) {
        if (entity is File && path.basename(entity.path) == 'notes.json') {
          notesFile = entity;
          baseDir = entity.parent;
          break;
        }
      }

      if (notesFile == null || !await notesFile.exists()) {
        // Debug: print structure
        print('Restore failed. Structure:');
        await for (final entity in restoreDir.list(recursive: true)) {
           print(' - ${entity.path}');
        }
        throw Exception('Invalid backup: notes.json missing');
      }
      
      final String notesJson = await notesFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(notesJson);
      final List<Note> restoredNotes = jsonList.map((j) => Note.fromJson(j)).toList();

      // 3. Restore Images (relative to notes.json)
      if (baseDir != null) {
        final imagesDir = Directory('${baseDir.path}/images');
        if (await imagesDir.exists()) {
          final appDocDir = await getApplicationDocumentsDirectory();
          await for (final file in imagesDir.list()) {
            if (file is File) {
               final fileName = path.basename(file.path);
               final targetPath = '${appDocDir.path}/$fileName';
               await file.copy(targetPath);
            }
          }
        }
      }
      
      // 4. Fix Image Paths in Notes
       final appDocDir = await getApplicationDocumentsDirectory();
       for (var note in restoredNotes) {
         for (var i = 0; i < note.attributes.length; i++) {
           final attr = note.attributes[i].attribute;
           if (attr.imagePath != null) {
             final fileName = path.basename(attr.imagePath!);
             final newPath = '${appDocDir.path}/$fileName';
             note.attributes[i] = note.attributes[i].copyWith(
               attribute: attr.copyWith(imagePath: newPath)
             );
           }
         }
       }

      // Cleanup
      await restoreDir.delete(recursive: true);

      return restoredNotes;
    } catch (e) {
      print('Restore Error: $e');
      throw e;
    }
  }
}
