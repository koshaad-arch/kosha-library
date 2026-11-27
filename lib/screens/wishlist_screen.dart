import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../services/picks.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import 'shelf_screen.dart' show openBook;

Future<void> openAmazon(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t open Amazon.')));
  }
}

class AmazonButton extends StatelessWidget {
  final String url;
  final String label;
  const AmazonButton({super.key, required this.url, this.label = 'Amazon ↗'});
  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF9900),
          foregroundColor: const Color(0xFF1B1209),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => openAmazon(context, url),
        child: Text(label),
      );
}

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  String _inr(int x) => x.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+\d$)'), (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final wish = store.wishlist;
    final priced = wish.where((b) => (b.price ?? 0) > 0).toList();
    final total = priced.fold<int>(0, (s, b) => s + b.price!);
    final picks = store.picks(kPicks);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Text('🛒 Wishlist', style: serif(28, color: scheme.onSurface)),
        const SizedBox(height: 4),
        Text(
          wish.isEmpty
              ? 'Books you want to buy show up here.'
              : '${wish.length} book${wish.length > 1 ? 's' : ''} to buy'
                  '${priced.isNotEmpty ? ' · ₹${_inr(total)} for the ${priced.length} with a price' : ''}',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 12),
        if (wish.isEmpty)
          Text('Open any book and choose “Need to buy”, add one from the picks below, or scan a book in a shop.',
              style: TextStyle(color: muted))
        else
          ...wish.map((b) => _WishTile(book: b, showReal: store.showCovers)),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(child: Text('✨ Picked for you', style: serif(24, color: scheme.onSurface))),
            TextButton.icon(onPressed: store.morePicks, icon: const Icon(Icons.refresh), label: const Text('Other picks')),
          ],
        ),
        Text('Based on the genres you read most', style: TextStyle(color: muted)),
        const SizedBox(height: 10),
        if (picks.isEmpty)
          Text('Mark a few books as read and give them a genre, and suggestions will appear here.',
              style: TextStyle(color: muted))
        else
          ...picks.map((p) {
            final (genre, n, list) = p;
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: genre, style: serif(19, color: scheme.onSurface)),
                    TextSpan(
                        text: n > 0 ? '   you’ve read $n' : '   from your shelf',
                        style: TextStyle(color: muted, fontSize: 13)),
                  ])),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    Text('You already have every pick in this genre — impressive!', style: TextStyle(color: muted))
                  else
                    ...list.map((x) => _PickTile(title: x.$1, author: x.$2, genre: genre, showReal: store.showCovers)),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _WishTile extends StatelessWidget {
  final Book book;
  final bool showReal;
  const _WishTile({required this.book, required this.showReal});

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final prioColors = {
      'High': (const Color(0xFFFFD6DE), const Color(0xFF8A1538)),
      'Medium': (const Color(0xFFFFE6B3), const Color(0xFF6B4300)),
      'Low': (const Color(0xFFE3ECF5), const Color(0xFF24425E)),
    };
    final pc = prioColors[book.prio];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openBook(context, book),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              BookCover(book: book, width: 56, showReal: showReal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(16, color: scheme.onSurface)),
                    Text(book.firstAuthor, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (pc != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: pc.$1, borderRadius: BorderRadius.circular(99)),
                            child: Text('${book.prio} priority',
                                style: TextStyle(color: pc.$2, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        if ((book.price ?? 0) > 0) Text('₹${book.price}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 112,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmazonButton(url: book.amazonLink),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: const Color(0xFF1F5A35)),
                    onPressed: () {
                      store.setOwn(book, 'own');
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('“${book.title}” moved to your shelf — enjoy!')));
                    },
                    child: const Text('✓ Bought'),
                  ),
                ],
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  final String title, author, genre;
  final bool showReal;
  const _PickTile({required this.title, required this.author, required this.genre, required this.showReal});

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final preview = Book(id: 'pick:$title', title: title, author: author, genre: genre);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            BookCover(book: preview, width: 50, showReal: showReal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: serif(15, color: scheme.onSurface)),
                  Text(author, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                ],
              ),
            ),
            SizedBox(
              width: 112,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AmazonButton(url: preview.amazonLink),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () {
                    store.addToWishlist(title, author, genre);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added “$title” to your wishlist')));
                  },
                  child: const Text('+ Wishlist'),
                ),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }
}
