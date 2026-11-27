import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../services/goodreads_sync.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/star_rating.dart';
import 'wishlist_screen.dart' show AmazonButton;

class BookDetailScreen extends StatefulWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late final TextEditingController _review, _quote, _page, _pages, _price, _amz, _cover;

  @override
  void initState() {
    super.initState();
    final b = context.read<LibraryStore>().byId(widget.bookId);
    _review = TextEditingController(text: b?.review ?? '');
    _quote = TextEditingController(text: b?.quote ?? '');
    _page = TextEditingController(text: (b?.currentPage ?? 0) == 0 ? '' : '${b!.currentPage}');
    _pages = TextEditingController(text: b?.pages?.toString() ?? '');
    _price = TextEditingController(text: b?.price?.toString() ?? '');
    _amz = TextEditingController(text: b?.amz ?? '');
    _cover = TextEditingController(text: b?.coverUrl ?? '');
  }

  @override
  void dispose() {
    _review.dispose();
    _quote.dispose();
    _page.dispose();
    _pages.dispose();
    _price.dispose();
    _amz.dispose();
    _cover.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open the link.')));
    }
  }

  Future<void> _pickDate(LibraryStore store, Book b, bool isStart) async {
    final now = DateTime.now();
    final initial = (isStart ? b.start : b.end) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d == null) return;
    if (isStart) {
      b.start = d;
    } else {
      b.end = d;
    }
    store.touch(b);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final b = store.byId(widget.bookId);
    if (b == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This book was removed.')));
    }
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final info = [
      if (b.pages != null) '${b.pages} pages',
      if (b.year != null) '${b.year}',
      if (b.publisher.isNotEmpty) b.publisher,
    ].join(' · ');

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: b.fav ? 'Remove favourite' : 'Mark as favourite',
            onPressed: () {
              b.fav = !b.fav;
              store.touch(b);
            },
            icon: Icon(b.fav ? Icons.favorite : Icons.favorite_border, color: b.fav ? const Color(0xFFE0457B) : null),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Remove this book?'),
                    content: Text('“${b.title}” will be removed from your library.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  Navigator.pop(context);
                  store.remove(b);
                }
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove from library'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BookCover(book: b, width: 120, showReal: store.showCovers),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.title, style: serif(24, color: scheme.onSurface)),
                    const SizedBox(height: 6),
                    Text(b.author, style: TextStyle(color: muted, fontSize: 15)),
                    if (b.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(b.subtitle, style: TextStyle(color: muted, fontSize: 13)),
                    ],
                    if (info.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(info, style: TextStyle(color: muted, fontSize: 13)),
                    ],
                    if (b.isbn.isNotEmpty)
                      Text('ISBN ${b.isbn}', style: TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: AmazonButton(url: b.amazonLink, label: 'Buy on Amazon.in ↗')),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Goodreads'),
                  onPressed: () => _open(GoodreadsSync.goodreadsUrl(b)),
                ),
              ),
            ],
          ),
          label('Status'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.6,
            children: ReadStatus.values.map((s) {
              final on = b.status == s;
              return on
                  ? FilledButton(onPressed: () {}, child: Text(s.label))
                  : OutlinedButton(
                      onPressed: () {
                        store.setStatus(b, s);
                        if (s == ReadStatus.read && b.pages != null) _page.text = '${b.pages}';
                      },
                      child: Text(s.label),
                    );
            }).toList(),
          ),
          label('Do you own it?'),
          SegmentedButton<String>(
            segments: kOwnLabels.entries
                .map((e) => ButtonSegment(value: e.key, label: Text(e.value, style: const TextStyle(fontSize: 12.5))))
                .toList(),
            selected: {b.own},
            showSelectedIcon: false,
            onSelectionChanged: (s) => store.setOwn(b, s.first),
          ),
          if (b.isWish) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (₹)', hintText: 'e.g. 399'),
                    onChanged: (v) {
                      b.price = int.tryParse(v);
                      store.touch(b);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: kPriorities.contains(b.prio) ? b.prio : null,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: kPriorities.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                    onChanged: (v) {
                      b.prio = v ?? '';
                      store.touch(b);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F5A35)),
              icon: const Icon(Icons.check),
              label: const Text('I bought it'),
              onPressed: () {
                store.setOwn(b, 'own');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to your shelf — enjoy!')));
              },
            ),
          ],
          label('Your rating'),
          Row(
            children: [
              StarPicker(
                rating: b.rating,
                onChanged: (v) {
                  b.rating = v;
                  store.touch(b);
                },
              ),
              const SizedBox(width: 8),
              Text(b.rating == 0 ? 'Tap to rate' : '${b.rating} / 5',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          Text('Tap the left half of a star for a half star.', style: TextStyle(color: muted, fontSize: 12)),
          if (b.status == ReadStatus.reading) ...[
            label('Where are you up to?'),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: b.progress,
                minHeight: 9,
                backgroundColor: AppColors.chip,
                color: AppColors.rose,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _page,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Current page'),
                    onChanged: (v) {
                      b.currentPage = int.tryParse(v) ?? 0;
                      store.touch(b);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pages,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Total pages'),
                    onChanged: (v) {
                      b.pages = int.tryParse(v);
                      store.touch(b);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [10, 25, 50].map((n) {
                return ActionChip(
                  label: Text('+$n pages'),
                  onPressed: () {
                    var v = b.currentPage + n;
                    if (b.pages != null && v > b.pages!) v = b.pages!;
                    b.currentPage = v;
                    _page.text = '$v';
                    store.touch(b);
                    if (b.pages != null && v >= b.pages!) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('You reached the last page!'),
                        action: SnackBarAction(label: 'Mark as read', onPressed: () => store.setStatus(b, ReadStatus.read)),
                      ));
                    }
                  },
                );
              }).toList(),
            ),
          ],
          label('Dates'),
          Row(
            children: [
              Expanded(child: _DateBox(title: 'Started', date: b.start, onTap: () => _pickDate(store, b, true), onClear: () {
                b.start = null;
                store.touch(b);
              })),
              const SizedBox(width: 10),
              Expanded(child: _DateBox(title: 'Finished', date: b.end, onTap: () => _pickDate(store, b, false), onClear: () {
                b.end = null;
                store.touch(b);
              })),
            ],
          ),
          label('Details'),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: kFormats.contains(b.format) ? b.format : null,
                  decoration: const InputDecoration(labelText: 'Format'),
                  items: kFormats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    b.format = v;
                    store.touch(b);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: kGenres.contains(b.genre) ? b.genre : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Genre'),
                  items: kGenres.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    b.genre = v;
                    store.touch(b);
                  },
                ),
              ),
            ],
          ),
          if (b.status != ReadStatus.reading) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _pages,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pages'),
              onChanged: (v) {
                b.pages = int.tryParse(v);
                store.touch(b);
              },
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _amz,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Amazon link (optional)', hintText: 'Paste the exact product page'),
            onChanged: (v) {
              b.amz = v.trim();
              store.touch(b);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cover,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Cover image link (optional)', hintText: 'https://… to use your own cover'),
            onChanged: (v) {
              final t = v.trim();
              if (t.isEmpty || t.startsWith('https://')) {
                b.coverUrl = t;
                store.touch(b);
              }
            },
          ),
          label('Mood'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kMoods.map((m) {
              final on = b.moods.contains(m);
              return FilterChip(
                label: Text(m),
                selected: on,
                selectedColor: AppColors.gold,
                onSelected: (sel) {
                  if (sel) {
                    b.moods.add(m);
                  } else {
                    b.moods.remove(m);
                  }
                  store.touch(b);
                },
              );
            }).toList(),
          ),
          label('My review'),
          TextField(
            controller: _review,
            minLines: 4,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What did you love? What stayed with you?'),
            onChanged: (v) {
              b.review = v;
              store.touch(b);
            },
          ),
          label('Favourite quote'),
          TextField(
            controller: _quote,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'A line worth keeping…'),
            onChanged: (v) {
              b.quote = v;
              store.touch(b);
            },
          ),
          if (b.summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('About this book', style: TextStyle(fontWeight: FontWeight.w700)),
              children: [Text(b.summary, style: TextStyle(color: muted, height: 1.5))],
            ),
          ],
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final String title;
  final DateTime? date;
  final VoidCallback onTap, onClear;
  const _DateBox({required this.title, required this.date, required this.onTap, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: title,
          suffixIcon: date == null
              ? const Icon(Icons.event_outlined)
              : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear, tooltip: 'Clear date'),
        ),
        child: Text(date == null ? 'Add date' : Book.dateLabel(date)),
      ),
    );
  }
}
