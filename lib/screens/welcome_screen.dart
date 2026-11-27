import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/library_store.dart';
import '../theme.dart';
import 'add_book_screen.dart';
import 'stats_screen.dart' show importOwnedFlow, importGoodreadsFlow, importAmazonFlow, restoreBackupFlow;

/// Shown whenever the library is empty (e.g. right after installing).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);

    Widget option({
      required String emoji,
      required String title,
      required String text,
      required VoidCallback onTap,
      Widget? extra,
    }) =>
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: serif(18, color: scheme.onSurface)),
                    const SizedBox(height: 4),
                    Text(text, style: TextStyle(color: muted, fontSize: 13.5, height: 1.35)),
                    if (extra != null) extra,
                  ]),
                ),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: AppColors.plum, borderRadius: BorderRadius.circular(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Kosha's Library", style: serif(32, color: const Color(0xFFFBEEF2))),
                const SizedBox(height: 8),
                const Text('Your shelf is empty. Bring your books in any of these ways — you can use more than one, '
                    'and books already added are updated, never duplicated.',
                    style: TextStyle(color: Color(0xFFE7CDD9), height: 1.4)),
              ]),
            ),
            const SizedBox(height: 18),
            option(
              emoji: '📄',
              title: 'Upload a CSV or Excel list',
              text: 'Your own list of books (like MyLibrary.xlsx) or a CSV copied from the web tracker. '
                  'Needs a Title column; Author, ISBN, Pages, Genre, Read, Reading periods and Summary are used if present.',
              onTap: () => importOwnedFlow(context),
            ),
            option(
              emoji: '📚',
              title: 'Import from Goodreads',
              text: 'On goodreads.com: My Books → Import and export → Export Library, download the file, then choose it here. '
                  'Brings in shelves, ratings, dates and reviews.',
              onTap: () => importGoodreadsFlow(context),
              extra: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Goodreads export page'),
                onPressed: () => launchUrl(Uri.parse('https://www.goodreads.com/review/import'), mode: LaunchMode.externalApplication),
              ),
            ),
            option(
              emoji: '🛒',
              title: 'Import your Amazon wishlist',
              text: 'Choose the amazon-wishlist.csv made by the helper (Settings → Copy helper, run once on a computer). '
                  'Books land on your Wishlist with prices.',
              onTap: () => importAmazonFlow(context),
            ),
            option(
              emoji: '📷',
              title: 'Scan or add books yourself',
              text: 'Scan the barcode on the back of each book, type an ISBN or title, or add one by hand.',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddBookScreen(startScanning: true))),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('Restore a backup from this app'),
                onPressed: () => restoreBackupFlow(context),
              ),
            ),
            if (store.findingPages || store.pagesMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(store.pagesMessage, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}
