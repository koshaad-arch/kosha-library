import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/book_lookup.dart';
import '../services/library_store.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import 'book_detail_screen.dart';
import 'scan_screen.dart';

/// Add a book by scanning its barcode, typing an ISBN, searching by title, or by hand.
class AddBookScreen extends StatefulWidget {
  final bool startScanning;
  final String defaultOwn;
  const AddBookScreen({super.key, this.startScanning = false, this.defaultOwn = 'own'});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final _search = TextEditingController();
  List<FoundBook> _results = [];
  bool _loading = false;
  String _message = '';
  late String _own = widget.defaultOwn;
  String _format = 'Paperback';

  @override
  void initState() {
    super.initState();
    if (widget.startScanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final isbn = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (isbn == null || !mounted) return;
    _search.text = isbn;
    await _find();
  }

  Future<void> _find() async {
    final text = _search.text.trim();
    if (text.isEmpty) return;
    final store = context.read<LibraryStore>();
    FocusScope.of(context).unfocus();

    if (BookLookup.looksLikeIsbn(text)) {
      final existing = store.byIsbn(text);
      if (existing != null) {
        _alreadyOwned(existing);
        return;
      }
    }

    setState(() {
      _loading = true;
      _message = '';
      _results = [];
    });
    final res = BookLookup.looksLikeIsbn(text) ? await BookLookup.byIsbn(text) : await BookLookup.search(text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _results = res;
      _message = res.isEmpty
          ? 'No book found for “$text”. Check your internet connection, try the title instead, or add it by hand below.'
          : '';
    });
  }

  void _alreadyOwned(Book b) {
    final store = context.read<LibraryStore>();
    if (!b.isOwned && _own == 'own') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('“${b.title}” is already here — ${b.isWish ? 'on your wishlist' : 'marked “Don’t own”'}.'),
        action: SnackBarAction(label: 'I own it now', onPressed: () => store.setOwn(b, 'own')),
        duration: const Duration(seconds: 6),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('“${b.title}” is already in your library${b.isOwned ? ' (owned)' : b.isWish ? ' (wishlist)' : ''}'),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: b.id)),
        ),
      ),
    ));
  }

  void _add(FoundBook f, ReadStatus status) {
    final store = context.read<LibraryStore>();
    if (f.isbn.isNotEmpty) {
      final existing = store.byIsbn(f.isbn);
      if (existing != null) {
        _alreadyOwned(existing);
        return;
      }
    }
    final b = f.toBook(status, own: _own)..format = _format;
    store.add(b);
    if (f.coverUrl.isEmpty) b.coverUrl = '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_own == 'wish' ? 'Added “${b.title}” to your wishlist' : 'Added “${b.title}” to your shelf')));
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: b.id)));
  }

  Future<void> _manual() async {
    final t = TextEditingController(text: BookLookup.looksLikeIsbn(_search.text) ? '' : _search.text.trim());
    final a = TextEditingController();
    final p = TextEditingController();
    final isbn = TextEditingController(text: BookLookup.looksLikeIsbn(_search.text) ? _search.text.trim() : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add a book by hand'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: t, decoration: const InputDecoration(labelText: 'Title'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 10),
              TextField(controller: a, decoration: const InputDecoration(labelText: 'Author'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 10),
              TextField(controller: p, decoration: const InputDecoration(labelText: 'Pages'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              TextField(controller: isbn, decoration: const InputDecoration(labelText: 'ISBN (optional)'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || t.text.trim().isEmpty || !mounted) return;
    _add(
      FoundBook(
        title: t.text.trim(),
        author: a.text.trim(),
        pages: int.tryParse(p.text),
        isbn: LibraryStore.normIsbn(isbn.text),
      ),
      ReadStatus.tbr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(title: const Text('Add a book')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SizedBox(
            height: 120,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _scan,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, size: 40),
                  const SizedBox(height: 8),
                  Text('Scan the barcode', style: serif(20, color: Colors.white)),
                  const Text('on the back cover'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Adding as', style: TextStyle(color: muted)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'own', label: Text('📚 Own it')),
              ButtonSegment(value: 'wish', label: Text('🛒 Need to buy')),
              ButtonSegment(value: 'none', label: Text("📖 Don't own")),
            ],
            selected: {_own},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _own = s.first),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Paperback', label: Text('📚 Physical')),
              ButtonSegment(value: 'Kindle', label: Text('📱 Kindle')),
              ButtonSegment(value: 'eBook', label: Text('💻 eBook')),
              ButtonSegment(value: 'Audiobook', label: Text('🎧 Audio')),
            ],
            selected: {_format},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 18),
          Text('…or type an ISBN or a title', style: TextStyle(color: muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _find(),
                  decoration: const InputDecoration(
                    hintText: 'e.g. 9780735211308 or Atomic Habits',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 54,
                child: FilledButton.tonal(onPressed: _loading ? null : _find, child: const Text('Find')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_message, style: TextStyle(color: muted)),
            ),
          ..._results.map((f) => _ResultCard(found: f, onAdd: (s) => _add(f, s))),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: _manual,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Add a book by hand'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final FoundBook found;
  final void Function(ReadStatus) onAdd;
  const _ResultCard({required this.found, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final preview = found.toBook(ReadStatus.tbr);
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final meta = [
      if (found.year != null) '${found.year}',
      if (found.pages != null) '${found.pages} pages',
      if (found.genre.isNotEmpty) found.genre,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCover(book: preview, width: 72),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(found.title, style: serif(17, color: Theme.of(context).colorScheme.onSurface)),
                      if (found.author.isNotEmpty) Text(found.author, style: TextStyle(color: muted)),
                      if (meta.isNotEmpty) Text(meta, style: TextStyle(color: muted, fontSize: 12.5)),
                      if (found.isbn.isNotEmpty) Text('ISBN ${found.isbn}', style: TextStyle(color: muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton(onPressed: () => onAdd(ReadStatus.tbr), child: const Text('Want to read')),
                OutlinedButton(onPressed: () => onAdd(ReadStatus.reading), child: const Text('Reading')),
                OutlinedButton(onPressed: () => onAdd(ReadStatus.read), child: const Text('Read')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
