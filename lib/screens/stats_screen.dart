import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../theme.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final year = DateTime.now().year;
    final read = store.read;

    final months = List.filled(12, 0);
    for (final b in store.readInYear(year)) {
      months[b.end!.month - 1]++;
    }

    Map<String, int> tally(Iterable<String> xs) {
      final m = <String, int>{};
      for (final x in xs) {
        if (x.isNotEmpty) m[x] = (m[x] ?? 0) + 1;
      }
      return m;
    }

    final ratings = <String, int>{};
    for (final r in [5.0, 4.5, 4.0, 3.5, 3.0, 2.5, 2.0, 1.5, 1.0, 0.5]) {
      final n = read.where((b) => b.rating == r).length;
      if (n > 0) ratings['$r ★'] = n;
    }
    final rated = read.where((b) => b.rating > 0).toList();
    final avg = rated.isEmpty ? null : rated.fold(0.0, (s, b) => s + b.rating) / rated.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('Your reading, in numbers', style: serif(28, color: scheme.onSurface)),
        const SizedBox(height: 6),
        Text(
          '${store.readInYear(year).length} finished in $year · ${read.length} read in total'
          '${avg == null ? '' : ' · average rating ${avg.toStringAsFixed(1)}'}',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 16),
        const _Panel(title: 'Bring in your Goodreads', child: _GoodreadsPanel()),
        _Panel(title: 'Finished each month, $year', child: _MonthBars(months: months)),
        _Panel(
          title: 'How you rated them',
          child: ratings.isEmpty
              ? const Text('Rate a book you have read and it shows up here.')
              : _HBars(data: ratings, sort: false),
        ),
        _Panel(title: 'Genres you’ve read', child: _HBars(data: tally(read.map((b) => b.genre)))),
        _Panel(title: 'Most-read authors', child: _HBars(data: tally(read.map((b) => b.firstAuthor)))),
        _Panel(
          title: 'Waiting on your shelf',
          child: _HBars(data: tally(store.books.where((b) => b.status == ReadStatus.tbr).map((b) => b.genre))),
        ),
        _Panel(
          title: 'Settings & backup',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show real book covers'),
                subtitle: const Text('Downloads covers by ISBN when you are online'),
                value: store.showCovers,
                onChanged: store.setShowCovers,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy library as CSV'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: store.toCsv()));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied — paste into Excel, Sheets or the web tracker')),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Import CSV'),
                    onPressed: () => _import(context, store),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'To bring ratings and reviews over from the web tracker, tap “Copy my library as CSV” there, '
                'then “Import CSV” here and paste.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _import(BuildContext context, LibraryStore store) async {
    final ctrl = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text?.startsWith('Title,') == true) ctrl.text = clip!.text!;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import CSV'),
        content: TextField(
          controller: ctrl,
          minLines: 6,
          maxLines: 10,
          decoration: const InputDecoration(hintText: 'Paste the CSV here'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    final (updated, added) = store.importCsv(ctrl.text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $updated books, added $added new')),
      );
    }
  }
}

class _GoodreadsPanel extends StatelessWidget {
  const _GoodreadsPanel();

  Future<void> _pick(BuildContext context, LibraryStore store) async {
    final res = await FilePicker.pickFiles(type: FileType.any, withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    final msg = store.importGoodreadsCsv(utf8.decode(bytes, allowMalformed: true));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Brings in your Goodreads shelves, star ratings, finish dates and reviews. '
          'Books you already have are updated, not added twice.',
          style: TextStyle(color: muted, fontSize: 13.5),
        ),
        const SizedBox(height: 10),
        Text(
          '1. In Chrome, open goodreads.com/review/import and tap “Export Library”.\n'
          '2. Tap the “Your export from…” link to download the file.\n'
          '3. Come back here and tap the button below, then choose that file.',
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
              onPressed: () => _pick(context, store),
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

class _MonthBars extends StatelessWidget {
  final List<int> months;
  const _MonthBars({required this.months});

  @override
  Widget build(BuildContext context) {
    final mx = months.fold(1, (a, b) => a > b ? a : b);
    const letters = 'JFMAMJJASOND';
    final bar = Theme.of(context).brightness == Brightness.dark ? AppColors.rose : AppColors.plum;
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(12, (i) {
          final n = months[i];
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
                Text(letters[i], style: const TextStyle(fontSize: 11, color: AppColors.mute)),
              ],
            ),
          );
        }),
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
