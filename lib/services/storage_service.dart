import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class StorageService {
  static const String _fileName = 'notes.json';
  static const String _fontFile = 'font_setting.txt';
  static const String _themeFile = 'theme_setting.txt';
  static const String _firstLaunchFile = 'is_first_launch.txt';

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/$_fileName');
  }

  Future<List<Note>> loadNotes() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) return [];
      
      final contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      return jsonList.map((json) => Note.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveNotes(List<Note> notes) async {
    final file = await _localFile;
    final jsonList = notes.map((note) => note.toJson()).toList();
    await file.writeAsString(json.encode(jsonList));
  }

  // Font Settings
  Future<void> saveFont(String font) async {
    final path = await _localPath;
    final file = File('$path/$_fontFile');
    await file.writeAsString(font);
  }

  Future<String?> loadFont() async {
    try {
      final path = await _localPath;
      final file = File('$path/$_fontFile');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      // Ignore error
    }
    return null;
  }

  // Theme Settings
  Future<void> saveTheme(String theme) async {
    final path = await _localPath;
    final file = File('$path/$_themeFile');
    await file.writeAsString(theme);
  }

  Future<String?> loadTheme() async {
    try {
      final path = await _localPath;
      final file = File('$path/$_themeFile');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      // Ignore error
    }
    return null;
  }

  // First Launch check for Input Method hint
  Future<bool> isFirstLaunch() async {
    try {
      final path = await _localPath;
      final file = File('$path/$_firstLaunchFile');
      return !await file.exists();
    } catch (e) {
      return true;
    }
  }

  Future<void> setFirstLaunchComplete() async {
    try {
      final path = await _localPath;
      final file = File('$path/$_firstLaunchFile');
      await file.writeAsString('done');
    } catch (e) {
      // ignore
    }
  }
}
