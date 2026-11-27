import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/library_store.dart';
import '../ebook/ebooks_screen.dart';
import 'add_book_screen.dart';
import 'shelf_screen.dart';
import 'stats_screen.dart';
import 'wishlist_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: store.tab,
          children: const [ShelfScreen(), EbooksScreen(), WishlistScreen(), StatsScreen()],
        ),
      ),
      floatingActionButton: store.tab == 1 || store.tab == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddBookScreen(startScanning: true, defaultOwn: store.tab == 2 ? 'wish' : 'own'),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan / add'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: store.tab,
        onDestinationSelected: store.setTab,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'Shelf'),
          const NavigationDestination(
              icon: Icon(Icons.chrome_reader_mode_outlined), selectedIcon: Icon(Icons.chrome_reader_mode), label: 'Read'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: store.wishlist.isNotEmpty,
              label: Text('${store.wishlist.length}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            selectedIcon: const Icon(Icons.shopping_bag),
            label: 'Wishlist',
          ),
          const NavigationDestination(
              icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Stats'),
        ],
      ),
    );
  }
}
