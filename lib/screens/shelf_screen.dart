import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/star_rating.dart';
import 'book_detail_screen.dart';

void openBook(BuildContext context, Book b) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: b.id)),
    );

class ShelfScreen extends StatelessWidget {
  const ShelfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final books = store.filtered;
    final width = MediaQuery.sizeOf(context).width;
    final cols = (width / 150).floor().clamp(2, 8).toInt();

    return Container(
      child: CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _Header()),
        SliverPersistentHeader(pinned: true, delegate: _FilterBarDelegate()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              '${books.length} ${books.length == 1 ? 'book' : 'books'}',
              style: const TextStyle(color: AppColors.mute),
            ),
          ),
        ),
        if (books.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No books here yet. Try another filter, or tap “Scan / add”.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.mute)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.44,
              ),
              delegate: SliverChildBuilderDelegate(
                (c, i) => _BookTile(book: books[i], showReal: store.showCovers),
                childCount: books.length,
              ),
            ),
          ),
      ],
    ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final year = DateTime.now().year;
    final done = store.readInYear(year).length;
    final pct = store.goal == 0 ? 0.0 : (done / store.goal).clamp(0, 1).toDouble();
    final reading = store.reading;
    const onPlum = Color(0xFFFBEEF2);
    const soft = Color(0xFFE2C6D3);

    return Container(
      color: AppColors.plum,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Kosha's Library", style: serif(34, color: onPlum)),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('${store.books.length}', 'owned'),
              _stat('${store.read.length}', 'read'),
              _stat('${store.count('tbr')}', 'to read'),
              _stat(_k(store.pagesRead), 'pages'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  height: 58,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        color: AppColors.gold,
                        strokeCap: StrokeCap.round,
                      ),
                      Center(child: Text('${(pct * 100).round()}%', style: serif(14, color: onPlum))),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$done of ${store.goal} books in $year', style: serif(18, color: onPlum)),
                      const SizedBox(height: 2),
                      Text(
                        done >= store.goal ? 'Goal reached — wonderful!' : '${store.goal - done} to go',
                        style: const TextStyle(color: soft),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Change goal',
                  onPressed: () => _editGoal(context, store),
                  icon: const Icon(Icons.edit_outlined, color: soft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('On the nightstand', style: serif(20, color: onPlum)),
          const SizedBox(height: 10),
          if (reading.isEmpty)
            const Text('Nothing on the nightstand. Open a book and tap “Reading”.',
                style: TextStyle(color: soft))
          else
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: reading.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (c, i) => _NightCard(book: reading[i], showReal: store.showCovers),
              ),
            ),
        ],
      ),
    );
  }

  static String _k(int n) => n >= 10000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Widget _stat(String n, String l) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(child: Text(n, style: serif(22, color: const Color(0xFFFBEEF2)))),
              Text(l, style: const TextStyle(color: Color(0xFFE2C6D3), fontSize: 12)),
            ],
          ),
        ),
      );

  Future<void> _editGoal(BuildContext context, LibraryStore store) async {
    final ctrl = TextEditingController(text: '${store.goal}');
    final v = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Books to read in ${DateTime.now().year}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v != null && v > 0) store.setGoal(v);
  }
}

class _NightCard extends StatelessWidget {
  final Book book;
  final bool showReal;
  const _NightCard({required this.book, required this.showReal});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openBook(context, book),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 290,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFFFF6F2), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            BookCover(book: book, width: 66, showReal: showReal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(16, color: AppColors.ink)),
                  Text(book.firstAuthor, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.mute, fontSize: 13)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: book.progress,
                      minHeight: 7,
                      backgroundColor: const Color(0xFFF0DCD7),
                      color: AppColors.rose,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.pages == null
                        ? 'Tap to log your page'
                        : 'Page ${book.currentPage} of ${book.pages} · ${(book.progress * 100).round()}%',
                    style: const TextStyle(color: AppColors.mute, fontSize: 12),
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

class _BookTile extends StatelessWidget {
  final Book book;
  final bool showReal;
  const _BookTile({required this.book, required this.showReal});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return InkWell(
      onTap: () => openBook(context, book),
      borderRadius: BorderRadius.circular(10),
      child: LayoutBuilder(
        builder: (c, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(book: book, width: box.maxWidth, showReal: showReal),
            const SizedBox(height: 8),
            Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: serif(14, color: Theme.of(context).colorScheme.onSurface)),
            Text(book.firstAuthor, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Row(
              children: [
                StatusPill(status: book.status),
                const Spacer(),
                if (book.rating > 0) Stars(rating: book.rating, size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final ReadStatus status;
  const StatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      ReadStatus.read => (const Color(0xFFD9EFE0), const Color(0xFF1F5A35)),
      ReadStatus.reading => (const Color(0xFFFFE6B3), const Color(0xFF6B4300)),
      ReadStatus.dnf => (const Color(0xFFE9E2E6), const Color(0xFF5A4A53)),
      ReadStatus.tbr => (AppColors.chip, AppColors.ink),
    };
    final label = status == ReadStatus.tbr ? 'To read' : status == ReadStatus.dnf ? 'DNF' : status.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 124;
  @override
  double get maxExtent => 124;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      const _FilterBar();
}

class _FilterBar extends StatefulWidget {
  const _FilterBar();
  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  late final TextEditingController _q;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: context.read<LibraryStore>().query);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final chips = [
      ('all', 'All'),
      ('reading', 'Reading'),
      ('tbr', 'Want to read'),
      ('read', 'Read'),
      ('dnf', 'DNF'),
      ('fav', '♥ Favourites'),
    ];
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: TextField(
                      controller: _q,
                      onChanged: (v) => store.setFilter(q: v),
                      decoration: InputDecoration(
                        hintText: 'Search title, author, ISBN, mood…',
                        prefixIcon: const Icon(Icons.search),
                        contentPadding: EdgeInsets.zero,
                        suffixIcon: _q.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _q.clear();
                                  store.setFilter(q: '');
                                },
                              ),
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Genre',
                  icon: Icon(Icons.category_outlined,
                      color: store.genreFilter.isEmpty ? null : AppColors.rose),
                  onSelected: (g) => store.setFilter(genre: g),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(value: '', checked: store.genreFilter.isEmpty, child: const Text('All genres')),
                    ...store.genresInUse.map((g) =>
                        CheckedPopupMenuItem(value: g, checked: store.genreFilter == g, child: Text(g))),
                  ],
                ),
                PopupMenuButton<SortBy>(
                  tooltip: 'Sort',
                  icon: const Icon(Icons.sort_rounded),
                  onSelected: (s) => store.setFilter(sortBy: s),
                  itemBuilder: (_) => SortBy.values
                      .map((s) => CheckedPopupMenuItem(value: s, checked: store.sort == s, child: Text(s.label)))
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: chips
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text('${c.$2}  ${store.count(c.$1)}'),
                            selected: store.statusFilter == c.$1,
                            onSelected: (_) => store.setFilter(status: c.$1),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
