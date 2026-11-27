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

class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key});
  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  final _listKey = GlobalKey();
  int _seenTick = 0;

  void _jumpToList() {
    final ctx = _listKey.currentContext;
    if (ctx == null) return;
    final pos = Scrollable.of(ctx).position;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic).then((_) {
      // the search/filter bar stays pinned on top, so step back by its height
      final target = (pos.pixels - 130).clamp(0.0, pos.maxScrollExtent);
      pos.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    if (store.scrollTick != _seenTick) {
      _seenTick = store.scrollTick;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToList());
    }
    final allBooks = store.filtered;
    final size = store.pageSize;
    final pages = size == 0 ? 1 : ((allBooks.length + size - 1) ~/ size).clamp(1, 1 << 20);
    final page = store.page.clamp(0, pages - 1);
    final books = size == 0 ? allBooks : allBooks.skip(page * size).take(size).toList();
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
            child: Builder(builder: (context) {
              final filtered = store.statusFilter != 'all' || store.query.isNotEmpty || store.genreFilter.isNotEmpty;
              final what = [
                if (store.statusFilter != 'all') LibraryStore.filterNames[store.statusFilter] ?? '',
                store.genreFilter,
                if (store.query.isNotEmpty) '“${store.query}”',
              ].where((x) => x.isNotEmpty).join(' · ');
              return Row(
                key: _listKey,
                children: [
                  Expanded(
                    child: Text(
                      '${allBooks.length} ${allBooks.length == 1 ? 'book' : 'books'}${filtered ? ' · $what' : ' on your shelf'}',
                      style: const TextStyle(color: AppColors.mute),
                    ),
                  ),
                  if (filtered)
                    TextButton.icon(
                      onPressed: store.clearFilters,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Show all'),
                    ),
                ],
              );
            }),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.42,
              ),
              delegate: SliverChildBuilderDelegate(
                (c, i) => _BookTile(book: books[i], showReal: store.showCovers),
                childCount: books.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            child: _Pager(page: page, pages: pages, total: allBooks.length, size: size, store: store),
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
          _Tiles(store: store),
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
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text('$done of ${store.goal} books in $year', style: serif(18, color: onPlum)),
                          if (done < store.goal) _PacePill(done: done, goal: store.goal),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        done >= store.goal ? 'Goal reached — wonderful!' : '${store.goal - done} to go · about ${_perMonth(done, store.goal)} a month to finish on time',
                        style: const TextStyle(color: soft),
                      ),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                            onPressed: () => store.goTo('readyr'),
                            child: Text("See $year's books"),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                            onPressed: () => store.goTo('year'),
                            child: Text('$year stats'),
                          ),
                        ],
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

  static int _perMonth(int done, int goal) {
    final now = DateTime.now();
    final monthsLeft = (12 - now.month - now.day / 31).clamp(1, 12);
    return ((goal - done) / monthsLeft).ceil().clamp(1, 1000).toInt();
  }

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
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(status: book.status),
                if (book.isWish) const _MiniPill('🛒 To buy', Color(0xFFFFE0C2), Color(0xFF7A3D00)),
                if (book.own == 'none') const _MiniPill('Not owned', Color(0xFFE9E2E6), Color(0xFF5A4A53)),
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
      ('own', '📚 Owned'),
      ('wish', '🛒 Wishlist'),
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


class _MiniPill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const _MiniPill(this.text, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class _PacePill extends StatelessWidget {
  final int done, goal;
  const _PacePill({required this.done, required this.goal});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final doy = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final pace = done - (goal * doy / 365).floor();
    final on = pace >= 0;
    return _MiniPill(on ? 'on track' : '${-pace} behind', on ? const Color(0xFFD9EFE0) : const Color(0xFFFFE6B3),
        on ? const Color(0xFF1F5A35) : const Color(0xFF6B4300));
  }
}

/// The six tappable summary tiles from the web tracker.
class _Tiles extends StatelessWidget {
  final LibraryStore store;
  const _Tiles({required this.store});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final all = store.books;
    final read = store.read;
    final yr = store.readInYear(year);
    final owned = all.where((b) => b.isOwned).toList();
    final ownRead = owned.where((b) => b.status == ReadStatus.read).length;
    final pctR = owned.isEmpty ? 0 : (ownRead / owned.length * 100).round();
    final ownUnread = owned.where((b) => b.status == ReadStatus.tbr).length;
    final reading = store.reading;
    final wish = store.wishlist;
    final wTot = wish.fold<int>(0, (s, b) => s + (b.price ?? 0));
    final rated = read.where((b) => b.rating > 0).toList();
    final avg = rated.isEmpty ? '' : ' · avg ${(rated.fold<double>(0, (s, b) => s + b.rating) / rated.length).toStringAsFixed(1)} ★';
    final pYr = yr.fold<int>(0, (s, b) => s + (b.pages ?? 0));
    String n(int x) => x.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+\d$)'), (m) => '${m[1]},');
    final tiles = [
      ('own', '📚', '${owned.length}', 'books owned', '$pctR% of them read', pctR / 100.0),
      ('read', '✅', '${read.length}', 'books read', '${yr.length} in $year$avg', null),
      ('reading', '📖', '${reading.length}', 'reading now', reading.isEmpty ? 'nothing open' : reading.first.title + (reading.length > 1 ? ' +${reading.length - 1}' : ''), null),
      ('ownunread', '⏳', '$ownUnread', 'owned, not read', ownUnread > 0 ? 'your to-read pile' : 'all caught up!', null),
      ('wish', '🛒', '${wish.length}', 'on the wishlist', wTot > 0 ? '₹${n(wTot)} total' : 'books to buy', null),
      ('pages', '📄', n(store.pagesRead), 'pages read', '${n(pYr)} in $year', null),
    ];
    final cols = MediaQuery.sizeOf(context).width > 700 ? 6 : 3;
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: cols == 6 ? 0.95 : 0.74,
      children: tiles.map((t) {
        final on = store.statusFilter == t.$1;
        return Material(
          color: on ? const Color(0x2EF0AC2E) : Colors.white.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: on ? AppColors.gold : Colors.white.withValues(alpha: 0.08)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => store.goTo(t.$1),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.$2, style: const TextStyle(fontSize: 15)),
                  FittedBox(child: Text(t.$3, style: serif(22, color: const Color(0xFFFBEEF2)))),
                  Text(t.$4, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFF1DBE5), fontSize: 12, fontWeight: FontWeight.w700, height: 1.15)),
                  const Spacer(),
                  Text(t.$5, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFD6B7C6), fontSize: 11, height: 1.2)),
                  if (t.$6 != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: t.$6,
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          color: AppColors.gold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}


class _Pager extends StatelessWidget {
  final int page, pages, total, size;
  final LibraryStore store;
  const _Pager({required this.page, required this.pages, required this.total, required this.size, required this.store});

  @override
  Widget build(BuildContext context) {
    if (total <= 24) return const SizedBox.shrink();
    final from = size == 0 ? 1 : page * size + 1;
    final to = size == 0 ? total : ((page + 1) * size).clamp(0, total);
    final nums = <int>[];
    for (var k = 0; k < pages; k++) {
      if (k == 0 || k == pages - 1 || (k - page).abs() <= 1) nums.add(k);
    }
    final items = <Widget>[];
    int? prev;
    for (final k in nums) {
      if (prev != null && k - prev > 1) items.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('…')));
      items.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: k == page
            ? FilledButton(onPressed: null, style: FilledButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero), child: Text('${k + 1}'))
            : OutlinedButton(
                onPressed: () => store.setPage(k),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero),
                child: Text('${k + 1}')),
      ));
      prev = k;
    }
    return Column(
      children: [
        if (pages > 1)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 6,
            children: [
              IconButton(
                  tooltip: 'Previous page',
                  onPressed: page > 0 ? () => store.setPage(page - 1) : null,
                  icon: const Icon(Icons.chevron_left)),
              ...items,
              IconButton(
                  tooltip: 'Next page',
                  onPressed: page < pages - 1 ? () => store.setPage(page + 1) : null,
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$from–$to of $total  ·  Show ', style: const TextStyle(color: AppColors.mute)),
            DropdownButton<int>(
              value: size,
              underline: const SizedBox.shrink(),
              items: const [24, 48, 96, 0]
                  .map((z) => DropdownMenuItem(value: z, child: Text(z == 0 ? 'all' : '$z')))
                  .toList(),
              onChanged: (v) => store.setPageSize(v ?? 24),
            ),
            const Text(' per page', style: TextStyle(color: AppColors.mute)),
          ],
        ),
      ],
    );
  }
}
