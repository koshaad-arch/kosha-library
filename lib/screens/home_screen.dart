import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/library_store.dart';
import 'add_book_screen.dart';
import 'shelf_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _autoSynced = false;

  Future<void> _autoSync(LibraryStore store) async {
    final msg = await store.syncGoodreads(maxAge: const Duration(hours: 3));
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = context.select<LibraryStore, bool>((s) => s.loaded);
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_autoSynced) {
      _autoSynced = true;
      final store = context.read<LibraryStore>();
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync(store));
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: const [ShelfScreen(), StatsScreen()],
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddBookScreen(startScanning: true)),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan / add'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'Shelf'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Stats'),
        ],
      ),
    );
  }
}
