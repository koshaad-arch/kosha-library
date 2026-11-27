import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/file_channel.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import 'ebook_store.dart';
import 'reader_screen.dart';

Future<void> openReader(BuildContext context, Ebook e) async {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(ebook: e)));
}

class EbooksScreen extends StatelessWidget {
  const EbooksScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final f = await FileChannel.pick();
    if (f == null || !context.mounted) return;
    if (!f.$1.toLowerCase().endsWith('.epub')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(f.$1.toLowerCase().endsWith('.pdf')
              ? 'PDFs aren’t supported yet — choose an EPUB file.'
              : f.$1.toLowerCase().contains('.az') || f.$1.toLowerCase().endsWith('.kfx') || f.$1.toLowerCase().endsWith('.mobi')
                  ? 'Kindle files are locked to the Kindle app — choose an EPUB file instead.'
                  : 'Please choose an .epub file.')));
      return;
    }
    final store = context.read<EbookStore>();
    final lib = context.read<LibraryStore>();
    try {
      final e = await store.importEpub(f.$2, lib);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added “${e.title}”')));
        openReader(context, e);
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That EPUB could not be opened. It may be damaged or DRM-protected.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EbookStore>();
    final lib = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final list = store.recent;
    final current = list.where((e) => e.lastOpened != null).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Text('📖 Read', style: serif(28, color: scheme.onSurface)),
        const SizedBox(height: 4),
        Text('Your e-books, with highlights, notes, dictionary and reading time — saved on this phone.',
            style: TextStyle(color: muted)),
        const SizedBox(height: 14),
        if (current != null) ...[
          Card(
            color: AppColors.plum,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => openReader(context, current),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  _EbookCover(e: current, width: 70),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Continue reading', style: TextStyle(color: Color(0xFFE2C6D3), fontSize: 12)),
                      Text(current.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(18, color: const Color(0xFFFBEEF2))),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: current.progress,
                          minHeight: 7,
                          backgroundColor: Colors.white24,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${(current.progress * 100).round()}% · ${current.highlights.length} highlights',
                          style: const TextStyle(color: Color(0xFFE2C6D3), fontSize: 12)),
                    ]),
                  ),
                  const Icon(Icons.play_circle_fill, color: AppColors.gold, size: 40),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Add EPUB from phone'),
            onPressed: () => _import(context),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.public),
            label: const Text('Free classics'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FreeBooksScreen())),
          ),
        ]),
        const SizedBox(height: 18),
        if (list.isEmpty)
          Text(
            'No e-books yet. Tap “Free classics” to download one in a tap (Pride and Prejudice, Sherlock Holmes, '
            'Tagore and 70,000 more), or “Add EPUB from phone” for books you have bought DRM-free.',
            style: TextStyle(color: muted),
          )
        else
          ...list.map((e) {
            final shelf = lib.byId(e.bookId);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(10),
                leading: _EbookCover(e: e, width: 44),
                title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(15, color: scheme.onSurface)),
                subtitle: Text(
                  '${e.author}\n${(e.progress * 100).round()}% read'
                  '${e.highlights.isNotEmpty ? ' · ${e.highlights.length} highlights' : ''}'
                  '${shelf != null ? ' · ${shelf.status.label}' : ''}',
                ),
                isThreeLine: true,
                onTap: () => openReader(context, e),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'remove') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Remove this e-book?'),
                          content: const Text('The file, highlights and notes are deleted. The book stays on your shelf.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (ok == true) store.remove(e);
                    }
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove e-book'))],
                ),
              ),
            );
          }),
        const SizedBox(height: 18),
        Text(
          'Reads EPUB files without DRM: free classics, books from Standard Ebooks, Project Gutenberg, Google Play '
          '“DRM-free” downloads, and many indie authors. Kindle books bought from Amazon are locked to the Kindle app '
          'and can’t be opened here.',
          style: TextStyle(color: muted, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _EbookCover extends StatelessWidget {
  final Ebook e;
  final double width;
  const _EbookCover({required this.e, required this.width});
  @override
  Widget build(BuildContext context) {
    if (e.coverFile.isNotEmpty && File(e.coverFile).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(e.coverFile), width: width, height: width * 1.5, fit: BoxFit.cover),
      );
    }
    return SizedBox(width: width, height: width * 1.5, child: DesignedCover(title: e.title, author: e.author, width: width));
  }
}

class FreeBooksScreen extends StatefulWidget {
  const FreeBooksScreen({super.key});
  @override
  State<FreeBooksScreen> createState() => _FreeBooksScreenState();
}

class _FreeBooksScreenState extends State<FreeBooksScreen> {
  final _q = TextEditingController();
  List<FreeBook>? _results;
  String? _err;
  bool _loading = false;
  final Set<int> _downloading = {};

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await EbookStore.searchFree(_q.text);
      setState(() => _results = r);
    } catch (e) {
      setState(() => _err = 'Couldn’t reach the free library. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _get(FreeBook f) async {
    setState(() => _downloading.add(f.id));
    try {
      final e = await context.read<EbookStore>().downloadFree(f, context.read<LibraryStore>());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded “${e.title}”')));
      openReader(context, e);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed. Try again in a moment.')));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(f.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(title: const Text('Free classics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search title or author, e.g. Austen, Tagore, Sherlock',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
            ),
          ),
          const SizedBox(height: 6),
          Text('From Project Gutenberg — free, legal, public-domain books.', style: TextStyle(color: muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          if (_loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          if (_err != null) Text(_err!),
          if (!_loading && _results != null && _results!.isEmpty) const Text('Nothing found. Try another word.'),
          if (!_loading && _results != null)
            ..._results!.map((f) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: f.coverUrl.isEmpty
                        ? const Icon(Icons.menu_book, size: 40)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(f.coverUrl, width: 40, height: 60, fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(Icons.menu_book, size: 40)),
                          ),
                    title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(f.author, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: _downloading.contains(f.id)
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : FilledButton.tonal(onPressed: () => _get(f), child: const Text('Get')),
                  ),
                )),
        ],
      ),
    );
  }
}
