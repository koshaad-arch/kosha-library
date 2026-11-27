import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/library_store.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => LibraryStore()..load(),
      child: const KoshaLibraryApp(),
    ),
  );
}

class KoshaLibraryApp extends StatelessWidget {
  const KoshaLibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Kosha's Library",
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
