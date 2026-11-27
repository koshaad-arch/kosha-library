import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../services/file_channel.dart';
import '../services/library_store.dart';
import '../theme.dart';

void _snack(BuildContext context, String msg) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

String _inr(int x) => x.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+\d$)'), (m) => '${m[1]},');

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final thisYear = DateTime.now().year;
    final read = store.read;

    String yOf(Book b) => b.end == null ? '' : '${b.end!.year}';
    final years = {...read.map(yOf).where((y) => y.isNotEmpty), '$thisYear'}.toList()..sort((a, b) => b.compareTo(a));
    var sel = store.statsYear;
    if (sel != 'all' && !years.contains(sel)) sel = '$thisYear';
    final allTime = sel == 'all';
    final r = allTime ? read : read.where((b) => yOf(b) == sel).toList();
    final lbl = allTime ? 'all time' : sel;

    Map<String, int> tally(Iterable<String> xs) {
      final m = <String, int>{};
      for (final x in xs) {
        if (x.isNotEmpty) m[x] = (m[x] ?? 0) + 1;
      }
      return m;
    }

    final ratings = <String, int>{};
    for (final x in [5.0, 4.5, 4.0, 3.5, 3.0, 2.5, 2.0, 1.5, 1.0, 0.5]) {
      final n = r.where((b) => b.rating == x).length;
      if (n > 0) ratings['$x ★'] = n;
    }
    final rated = r.where((b) => b.rating > 0).toList();
    final avg = rated.isEmpty ? '–' : (rated.fold(0.0, (s, b) => s + b.rating) / rated.length).toStringAsFixed(1);
    final withP = r.where((b) => (b.pages ?? 0) > 0).toList()..sort((a, b) => b.pages!.compareTo(a.pages!));
    final pages = r.fold<int>(0, (s, b) => s + (b.pages ?? 0));
    final longest = withP.isEmpty ? null : withP.first;
    final shortest = withP.length < 2 ? null : withP.last;
    final best = ([...rated]..sort((a, b) {
          final c = b.rating.compareTo(a.rating);
          return c != 0 ? c : (b.end ?? DateTime(1900)).compareTo(a.end ?? DateTime(1900));
        }))
        .firstOrNull;
    final favs = r.where((b) => b.fav).length;
    final dnf = store.books
        .where((b) => b.status == ReadStatus.dnf && (allTime || '${(b.end ?? b.start)?.year}' == sel))
        .length;
    final days = r
        .where((b) => b.start != null && b.end != null)
        .map((b) => b.end!.difference(b.start!).inDays)
        .where((d) => d >= 0)
        .toList();
    final avgDays = days.isEmpty ? '–' : '${(days.reduce((a, b) => a + b) / days.length).round()}';
    final genres = tally(r.map((b) => b.genre));
    final topGenre = (genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).firstOrNull?.key ?? '–';
    final isThis = sel == '$thisYear';
    final undated = allTime ? read.where((b) => b.end == null).length : 0;

    final List<int> barVals;
    final List<String> barLbls;
    if (allTime) {
      final ys = years.reversed.toList();
      barVals = ys.map((y) => read.where((b) => yOf(b) == y).length).toList();
      barLbls = ys.map((y) => "'${y.substring(2)}").toList();
    } else {
      barVals = List.filled(12, 0);
      for (final b in r) {
        barVals[b.end!.month - 1]++;
      }
      barLbls = 'JFMAMJJASOND'.split('');
    }

    Widget tile(String n, String l) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(child: Text(n, style: serif(22, color: scheme.onSurface))),
              Text(l, style: TextStyle(color: muted, fontSize: 12.5)),
            ],
          ),
        );
    Widget fact(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$k  ', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.rose)),
            TextSpan(text: v),
          ])),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('Your reading, in numbers', style: serif(28, color: scheme.onSurface)),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final y in ['all', ...years])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(y == 'all' ? 'All time' : y),
                    selected: sel == y,
                    onSelected: (_) => store.setStatsYear(y),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: '${allTime ? 'All-time' : sel} at a glance',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.1,
                children: [
                  tile('${r.length}', 'books finished'),
                  tile(_inr(pages), 'pages read'),
                  tile(withP.isEmpty ? '–' : '${(pages / withP.length).round()}', 'avg pages / book'),
                  tile(avg, 'average rating'),
                  tile('$favs', 'new favourites'),
                  tile('$dnf', 'did not finish'),
                  tile(avgDays, 'avg days per book'),
                  isThis ? tile('${r.length}/${store.goal}', 'reading goal') : tile(topGenre, 'top genre'),
                ],
              ),
              if (longest != null) fact('Longest', '${longest.title} · ${longest.pages} pages'),
              if (shortest != null && shortest != longest) fact('Shortest', '${shortest.title} · ${shortest.pages} pages'),
              if (best != null) fact('Top rated', '${best.title} · ${best.rating} ★'),
              if (undated > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('$undated read book${undated > 1 ? 's have' : ' has'} no finish date, so only counted here.',
                      style: TextStyle(color: muted, fontSize: 12.5)),
                ),
            ],
          ),
        ),
        _Panel(
          title: allTime ? 'Books finished each year' : 'Finished each month, $sel',
          child: _ColBars(values: barVals, labels: barLbls),
        ),
        _Panel(
          title: 'How you rated them',
          child: ratings.isEmpty ? Text('No rated books for $lbl yet.') : _HBars(data: ratings, sort: false),
        ),
        _Panel(
            title: 'Genres you read',
            child: genres.isEmpty ? Text('Nothing finished for $lbl yet.') : _HBars(data: genres)),
        _Panel(
          title: 'Most-read authors',
          child: Builder(builder: (_) {
            final a = tally(r.map((b) => b.firstAuthor));
            final multi = Map.fromEntries(a.entries.where((e) => e.value > 1));
            return a.isEmpty ? Text('Nothing finished for $lbl yet.') : _HBars(data: multi.isNotEmpty ? multi : a);
          }),
        ),
        _Panel(
          title: 'Waiting on your shelf',
          child: _HBars(data: tally(store.books.where((b) => b.status == ReadStatus.tbr).map((b) => b.genre))),
        ),
        const _Panel(title: 'Bring in your Goodreads', child: _GoodreadsPanel()),
        const _Panel(title: 'Your owned books & Amazon wishlist', child: _ImportPanel()),
        _Panel(
          title: 'Backup & settings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save a backup before reinstalling or updating the app, then restore it afterwards — '
                'nothing is lost.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Export backup'),
                    onPressed: () async {
                      final d = DateTime.now();
                      final name =
                          'kosha-library-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
                      final ok = await FileChannel.save(name, store.backupJson());
                      if (context.mounted) _snack(context, ok ? 'Backup saved' : 'Backup was not saved');
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore backup'),
                    onPressed: () async {
                      final f = await FileChannel.pick();
                      if (f == null) return;
                      final msg = store.restoreBackup(FileChannel.text(f.$2));
                      if (context.mounted) _snack(context, msg);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy library as CSV'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: store.toCsv()));
                      if (context.mounted) _snack(context, 'Copied — paste into Excel, Sheets or the web tracker');
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.paste_rounded),
                    label: const Text('Import web tracker CSV'),
                    onPressed: () => _importWebCsv(context, store),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show real book covers'),
                subtitle: const Text('Finds covers online by ISBN or title'),
                value: store.showCovers,
                onChanged: store.setShowCovers,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importWebCsv(BuildContext context, LibraryStore store) async {
    final ctrl = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text?.startsWith('Title,') == true) ctrl.text = clip!.text!;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import from the web tracker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('On the web page tap “Copy my library as CSV”, then paste it here.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(controller: ctrl, minLines: 5, maxLines: 8, decoration: const InputDecoration(hintText: 'Paste the CSV')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    final (updated, added) = store.importCsv(ctrl.text);
    if (context.mounted) _snack(context, 'Updated $updated books, added $added new');
  }
}

class _GoodreadsPanel extends StatelessWidget {
  const _GoodreadsPanel();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Brings in your Goodreads shelves, star ratings, finish dates and reviews. '
          'Books you already have are updated, not added twice. Books only on Goodreads are not marked as owned.',
          style: TextStyle(color: muted, fontSize: 13.5),
        ),
        const SizedBox(height: 10),
        const Text(
          '1. Tap “Open Goodreads export page” and tap “Export Library”.\n'
          '2. Tap the “Your export from…” link to download the file.\n'
          '3. Come back and tap “Import Goodreads file”, then choose it.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Import Goodreads file'),
              onPressed: () async {
                final f = await FileChannel.pick();
                if (f == null) return;
                final msg = store.importGoodreadsCsv(FileChannel.text(f.$2));
                if (context.mounted) _snack(context, msg);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open Goodreads export page'),
              onPressed: () => launchUrl(Uri.parse('https://www.goodreads.com/review/import'),
                  mode: LaunchMode.externalApplication),
            ),
          ],
        ),
        if (store.grLastSync != null) ...[
          const SizedBox(height: 8),
          Text('Last imported ${Book.dateLabel(store.grLastSync)}. ${store.syncMessage}',
              style: TextStyle(color: muted, fontSize: 12.5)),
        ],
      ],
    );
  }
}

/// Reads CSV, or the first sheet of an Excel file, into header→value rows.
List<Map<String, String>> _rowsFromFile(String name, Uint8List bytes) {
  if (RegExp(r'\.xlsx$', caseSensitive: false).hasMatch(name)) {
    final book = xl.Excel.decodeBytes(bytes);
    final sheet = book.tables[book.tables.keys.first];
    if (sheet == null || sheet.rows.isEmpty) return [];
    String cell(dynamic c) => c?.value?.toString().trim() ?? '';
    final head = sheet.rows.first.map(cell).toList();
    return sheet.rows.skip(1).map((row) {
      final vals = row.map(cell).toList();
      return {for (var i = 0; i < head.length; i++) head[i]: i < vals.length ? vals[i] : ''};
    }).toList();
  }
  return LibraryStore.csvMaps(FileChannel.text(bytes));
}

const _amzHelper =
    "(async()=>{const S=ms=>new Promise(r=>setTimeout(r,ms));let n=-1;for(let i=0;i<60;i++){scrollTo(0,document.body.scrollHeight);await S(1200);const c=document.querySelectorAll('li[data-itemid]').length;if(c===n&&(document.querySelector('#endOfListMarker')||i>3))break;n=c}const rows=[['Title','Author','Price','Amazon link','ASIN']];document.querySelectorAll('li[data-itemid]').forEach(li=>{const a=li.querySelector('a[id^=\"itemName_\"]');if(!a)return;const t=(a.getAttribute('title')||a.textContent).trim();const h=new URL(a.getAttribute('href'),location.origin);const asin=(h.pathname.match(/\\/dp\\/([A-Z0-9]{10})/)||[])[1]||'';const by=(li.querySelector('[id^=\"item-byline-\"]')?.textContent||'').trim().replace(/^by\\s+/i,'').replace(/\\s*\\([^)]*\\)\\s*\$/,'');const pr=li.getAttribute('data-price');rows.push([t,by,pr&&isFinite(+pr)&&+pr>0?pr:'',asin?location.origin+'/dp/'+asin:h.origin+h.pathname,asin])});if(rows.length<2){alert('No wishlist items found. Open your wishlist page on Amazon first, then run this again.');return}const csv=rows.map(r=>r.map(v=>'\"'+String(v).replace(/\"/g,'\"\"')+'\"').join(',')).join('\\n');const l=document.createElement('a');l.href=URL.createObjectURL(new Blob(['\\ufeff'+csv],{type:'text/csv'}));l.download='amazon-wishlist.csv';document.body.appendChild(l);l.click();alert('Saved '+(rows.length-1)+' items to amazon-wishlist.csv - now import it in the app.')})();";

class _ImportPanel extends StatelessWidget {
  const _ImportPanel();

  Future<void> _owned(BuildContext context, LibraryStore store) async {
    final f = await FileChannel.pick();
    if (f == null) return;
    List<Map<String, String>> rows;
    try {
      rows = _rowsFromFile(f.$1, f.$2);
    } catch (_) {
      if (context.mounted) _snack(context, 'Could not read that file — save it as CSV and try again.');
      return;
    }
    final (msg, gone) = store.importOwned(rows, f.$1);
    if (!context.mounted) return;
    if (gone.isEmpty) {
      _snack(context, msg);
      return;
    }
    final mark = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Owned list updated'),
        content: SingleChildScrollView(
          child: Text('$msg\n\n${gone.length} book${gone.length > 1 ? 's' : ''} you own here '
              '${gone.length > 1 ? 'are' : 'is'} not in this file:\n'
              '${gone.take(80).map((b) => b.title).join(' · ')}${gone.length > 80 ? ' …' : ''}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep them as owned')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Mark ${gone.length} as not owned')),
        ],
      ),
    );
    if (mark == true) {
      store.markNotOwned(gone);
      if (context.mounted) _snack(context, 'Marked ${gone.length} as not owned. You can change any back on its page.');
    }
  }

  Future<void> _amazon(BuildContext context, LibraryStore store) async {
    final f = await FileChannel.pick();
    if (f == null) return;
    final msg = store.importAmazon(LibraryStore.csvMaps(FileChannel.text(f.$2)));
    if (context.mounted) {
      _snack(context, msg);
      store.setTab(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Owned books: choose a CSV or Excel (.xlsx) list with a Title column. Author, ISBN, Pages, Genre, '
          'Publisher, Year and Status are used if present. Books already here are marked owned; new ones are added.',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.library_books_outlined),
          label: const Text('Import owned books (CSV / Excel)'),
          onPressed: () => _owned(context, store),
        ),
        const SizedBox(height: 16),
        Text(
          'Amazon wishlist: Amazon has no export button, so a small helper makes the file. On a computer: '
          'tap “Copy helper” here (or on the web tracker), open your wishlist on amazon.in, press F12 → Console, '
          'paste and press Enter. It downloads amazon-wishlist.csv — send it to your phone and choose it here.',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Import Amazon wishlist'),
              onPressed: () => _amazon(context, store),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_copy_rounded),
              label: const Text('Copy helper'),
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: _amzHelper));
                if (context.mounted) _snack(context, 'Helper copied — paste it in the Amazon tab’s console');
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ColBars extends StatelessWidget {
  final List<int> values;
  final List<String> labels;
  const _ColBars({required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    final mx = values.fold(1, (a, b) => a > b ? a : b);
    final bar = Theme.of(context).brightness == Brightness.dark ? AppColors.rose : AppColors.plum;
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final n = values[i];
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (n > 0) Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Container(
                  height: 2 + 86 * n / mx,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: const TextStyle(fontSize: 11, color: AppColors.mute)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF231928) : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dark ? const Color(0xFF3A2A3F) : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: serif(18, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HBars extends StatelessWidget {
  final Map<String, int> data;
  final bool sort;
  const _HBars({required this.data, this.sort = true});

  @override
  Widget build(BuildContext context) {
    var entries = data.entries.toList();
    if (sort) entries.sort((a, b) => b.value.compareTo(a.value));
    entries = entries.take(6).toList();
    if (entries.isEmpty) return const Text('Nothing here yet.');
    final mx = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Column(
      children: entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 120, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: e.value / mx,
                    minHeight: 11,
                    backgroundColor: AppColors.chip,
                    color: AppColors.rose,
                  ),
                ),
              ),
              SizedBox(width: 32, child: Text('${e.value}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        );
      }).toList(),
    );
  }
}
