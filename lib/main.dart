import 'package:flutter/material.dart';
import 'package:mongol/mongol.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const MongolNotebookApp());
}

class MongolNotebookApp extends StatelessWidget {
  const MongolNotebookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mongol Notebook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
        fontFamily: 'Xinhei', // Set as global default
        scaffoldBackgroundColor: const Color(0xFFFDF5E6), // OldLace/Paper color
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.brown,
          foregroundColor: Colors.white,
        ),
      ),
      // Crucial for handling vertical text editing shortcuts on desktop/web
      builder: (context, child) => MongolTextEditingShortcuts(child: child!),
      home: const HomeScreen(),
    );
  }
}
