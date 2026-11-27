import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import 'ebook_store.dart';
import 'local_server.dart';
import 'reader_screen.dart' show DefinitionSheet;

const _pdfThemes = {
  'white': (Color(0xFFE9E4E6), 'Paper'),
  'sepia': (Color(0xFFEFE6D2), 'Sepia'),
  'night': (Color(0xFF111111), 'Night'),
};
const _hl = {
  'y': Color(0xFFFDE047),
  'b': Color(0xFF93C5FD),
  'p': Color(0xFFF9A8D4),
  'o': Color(0xFFFDBA74),
};

class PdfReaderScreen extends StatefulWidget {
  final Ebook ebook;
  const PdfReaderScreen({super.key, required this.ebook});
  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  late final WebViewController _web;
  int _page = 1, _pages = 0;
  bool _menu = false, _ready = false;
  String _selection = '';
  String? _error;
  List<(String, int, int)> _outline = [];
  DateTime _lastTurn = DateTime.now();
  String? _pendingNote;
  bool _searching = false;
  final _q = TextEditingController();
  int _found = 0, _foundAt = 0;
  Timer? _clock;

  Ebook get e => widget.ebook;
  EbookStore get _store => context.read<EbookStore>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFE9E4E6))
      ..addJavaScriptChannel('K', onMessageReceived: (m) => _onMsg(m.message));
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _start();
  }

  Future<void> _start() async {
    try {
      final port = await LocalServer.start();
      await _web.loadRequest(Uri.parse('http://127.0.0.1:$port/reader.html'));
      final lib = context.read<LibraryStore>();
      final shelf = lib.byId(e.bookId);
      if (shelf != null && shelf.status == ReadStatus.tbr) lib.setStatus(shelf, ReadStatus.reading);
      e.lastOpened = DateTime.now();
      _store.changed();
    } catch (err) {
      setState(() => _error = 'The reader could not start. $err');
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _store.save();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _js(String code) => _web.runJavaScript(code);

  void _onMsg(String raw) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'ready':
        final s = _store.settings;
        final file = LocalServer.register(e.file);
        _js('openDoc(${jsonEncode(file)}, ${e.section + 1}, ${jsonEncode(s.pdfTheme)}, ${jsonEncode(s.pdfMode)})');
      case 'meta':
        _pages = m['pages'] as int;
        e.pdfPages = _pages;
        _store.changed();
        final lib = context.read<LibraryStore>();
        final shelf = lib.byId(e.bookId);
        if (shelf != null && (shelf.pages ?? 0) <= 0) {
          shelf.pages = _pages;
          lib.touch(shelf);
        }
        final hls = e.highlights.map((h) => {'id': h.id, 'page': h.section + 1, 'c': h.color, 'rects': h.rects, 'text': h.text}).toList();
        _js('loadHL(${jsonEncode(hls)})');
        setState(() => _ready = true);
      case 'cover':
        if (e.coverFile.isEmpty) {
          try {
            _store.saveCover(e, base64Decode(m['data'] as String));
          } catch (_) {}
        }
      case 'outline':
        setState(() => _outline = ((m['items'] as List?) ?? [])
            .map((x) => ((x as Map)['title'] as String, x['page'] as int, (x['depth'] ?? 0) as int))
            .toList());
      case 'page':
        final p = m['page'] as int;
        if ((p - _page).abs() == 1) _countTurn();
        setState(() {
          _page = p;
          _pages = m['pages'] as int;
        });
        _savePos();
      case 'end':
        _finished();
      case 'menu':
        setState(() => _menu = !_menu);
      case 'sel':
        setState(() => _selection = (m['text'] ?? '') as String);
      case 'hl':
        final rects = ((m['rects'] as List?) ?? []).map((r) => (r as List).map((v) => (v as num).toDouble()).toList()).toList();
        final h = Highlight(m['id'] as String, (m['page'] as int) - 1, (m['text'] ?? '') as String, (m['c'] ?? 'y') as String,
            _pendingNote ?? '', DateTime.now(), rects);
        _pendingNote = null;
        e.highlights.add(h);
        _store.changed();
        setState(() => _selection = '');
      case 'mark':
        _markTapped(m['id'] as String);
      case 'found':
        setState(() {
          _found = (m['total'] ?? 0) as int;
          _foundAt = (m['current'] ?? 0) as int;
        });
      case 'error':
        if (!_ready) setState(() => _error = 'This PDF could not be opened. It may be damaged or password-protected.');
    }
  }

  void _countTurn() {
    final now = DateTime.now();
    final dt = now.difference(_lastTurn).inSeconds;
    _lastTurn = now;
    if (dt >= 2 && dt <= 900) {
      e.readSeconds += dt;
      e.pagesTurned++;
    }
  }

  void _savePos() {
    e.section = _page - 1;
    e.progress = _pages <= 1 ? 0 : ((_page - 1) / (_pages - 1)).clamp(0, 1).toDouble();
    _store.save();
    final lib = context.read<LibraryStore>();
    final shelf = lib.byId(e.bookId);
    if (shelf != null && shelf.status != ReadStatus.read && shelf.currentPage != _page) {
      shelf.currentPage = _page;
      if ((shelf.pages ?? 0) <= 0) shelf.pages = _pages;
      lib.touch(shelf);
    }
  }

  String _mins(double seconds) {
    final m = (seconds / 60).round();
    if (m < 1) return 'less than a minute';
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return '$h h${r > 0 ? ' $r min' : ''}';
  }

  double get _leftSec => (_pages - _page).clamp(0, 1 << 20) * (e.pagesTurned >= 5 ? e.secPerPage : 90);

  String get _chapter {
    String t = '';
    for (final o in _outline) {
      if (o.$2 <= _page) t = o.$1;
    }
    return t;
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3)));
  }

  void _finished() {
    final lib = context.read<LibraryStore>();
    final shelf = lib.byId(e.bookId);
    showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎉 You reached the end', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(e.title, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (shelf != null && shelf.status != ReadStatus.read)
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Mark as read'),
              onPressed: () {
                lib.setStatus(shelf, ReadStatus.read);
                Navigator.pop(c);
                Navigator.pop(context);
              },
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Keep reading')),
        ]),
      ),
    );
  }

  // ---------------- highlights, notes, dictionary ----------------
  String _newId() => 'h${DateTime.now().microsecondsSinceEpoch}';

  void _highlight(String c) => _js("hl('${_newId()}','$c')");

  Future<void> _note() async {
    final n = await _askNote('');
    if (n == null) return;
    _pendingNote = n;
    _js("hl('${_newId()}','y')");
  }

  Future<String?> _askNote(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Note'),
        content: TextField(controller: ctrl, autofocus: true, minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: 'Your thoughts…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  void _markTapped(String id) {
    final h = e.highlights.where((x) => x.id == id).firstOrNull;
    if (h == null) return;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('“${h.text}”', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic)),
            if (h.note.isNotEmpty) ...[const SizedBox(height: 8), Text('Note: ${h.note}')],
            Row(children: [
              for (final k in _hl.keys)
                IconButton(
                  onPressed: () {
                    h.color = k;
                    _store.changed();
                    _js("recolor('${h.id}','$k')");
                    Navigator.pop(c);
                  },
                  icon: Icon(Icons.circle, color: _hl[k], size: 30),
                ),
            ]),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: Text(h.note.isEmpty ? 'Add note' : 'Edit note'),
                onPressed: () async {
                  Navigator.pop(c);
                  final n = await _askNote(h.note);
                  if (n != null) {
                    h.note = n;
                    _store.changed();
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '“${h.text}” — ${e.title}${e.author.isNotEmpty ? ', ${e.author}' : ''}, p. ${h.section + 1}'));
                  Navigator.pop(c);
                  _snack('Quote copied');
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
                onPressed: () {
                  e.highlights.removeWhere((x) => x.id == h.id);
                  _store.changed();
                  _js("unmark('${h.id}')");
                  Navigator.pop(c);
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _define() {
    final w = _selection.trim().split(RegExp(r'\s+')).first.replaceAll(RegExp(r'''^[^\w]+|[^\w]+$'''), '');
    if (w.isEmpty) return;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (c) => DefinitionSheet(word: w));
  }

  void _saveQuote() {
    final lib = context.read<LibraryStore>();
    final shelf = lib.byId(e.bookId);
    if (shelf == null) return;
    shelf.quote = _selection;
    lib.touch(shelf);
    _snack('Saved as this book’s favourite quote');
  }

  // ---------------- sheets ----------------
  void _showContents() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (c, sc) => ListView(controller: sc, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Contents', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          if (_outline.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('This PDF has no table of contents. Use “Go to page” or the slider instead.'),
            ),
          for (final o in _outline)
            ListTile(
              contentPadding: EdgeInsets.only(left: 16.0 + o.$3 * 18, right: 16),
              title: Text(o.$1, style: TextStyle(fontWeight: o.$1 == _chapter ? FontWeight.w700 : FontWeight.w400)),
              trailing: Text('p. ${o.$2}'),
              onTap: () {
                Navigator.pop(c);
                setState(() => _menu = false);
                _js('goPage(${o.$2})');
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _goToPage() async {
    final ctrl = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Go to page (1–$_pages)'),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)), child: const Text('Go')),
        ],
      ),
    );
    if (n != null) _js('goPage($n)');
  }

  void _showNotes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final hl = [...e.highlights]..sort((a, b) => a.section.compareTo(b.section));
        final bm = [...e.bookmarks]..sort((a, b) => a.section.compareTo(b.section));
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (c2, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
            Row(children: [
              const Expanded(child: Text('Notes & highlights', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              if (hl.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Copy all'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text: '${e.title}${e.author.isNotEmpty ? ' — ${e.author}' : ''}\n\n${hl.map((h) => '“${h.text}” (p. ${h.section + 1})${h.note.isNotEmpty ? '\nNote: ${h.note}' : ''}').join('\n\n')}'));
                    _snack('All highlights copied');
                  },
                ),
            ]),
            if (bm.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.only(top: 8, bottom: 4), child: Text('Bookmarks', style: TextStyle(fontWeight: FontWeight.w700))),
              for (final x in bm)
                ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: Text(x.label),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      e.bookmarks.removeWhere((y) => y.id == x.id);
                      _store.changed();
                      set(() {});
                      setState(() {});
                    },
                  ),
                  onTap: () {
                    Navigator.pop(c);
                    setState(() => _menu = false);
                    _js('goPage(${x.section + 1})');
                  },
                ),
            ],
            const Padding(padding: EdgeInsets.only(top: 8, bottom: 4), child: Text('Highlights', style: TextStyle(fontWeight: FontWeight.w700))),
            if (hl.isEmpty) const Text('Press and hold on any words to highlight them, add a note or look them up.'),
            for (final h in hl)
              ListTile(
                leading: Icon(Icons.format_quote, color: _hl[h.color]),
                title: Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                subtitle: Text('Page ${h.section + 1}${h.note.isNotEmpty ? ' · Note: ${h.note}' : ''}'),
                onTap: () {
                  Navigator.pop(c);
                  setState(() => _menu = false);
                  _js('goPage(${h.section + 1})');
                },
              ),
          ]),
        );
      }),
    );
  }

  void _showDisplay() {
    showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final s = _store.settings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Page colour', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                for (final t in _pdfThemes.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: t.value.$1, radius: 8),
                      label: Text(t.value.$2),
                      selected: s.pdfTheme == t.key,
                      onSelected: (_) {
                        s.pdfTheme = t.key;
                        _store.changed();
                        _web.setBackgroundColor(t.value.$1);
                        _js("setTheme('${t.key}')");
                        set(() {});
                      },
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              const Text('Reading mode', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'page', label: Text('Page by page'), icon: Icon(Icons.auto_stories)),
                  ButtonSegment(value: 'scroll', label: Text('Scroll'), icon: Icon(Icons.swap_vert)),
                ],
                selected: {s.pdfMode},
                onSelectionChanged: (v) {
                  s.pdfMode = v.first;
                  _store.changed();
                  _js("setMode('${v.first}');goPage($_page)");
                  set(() {});
                },
              ),
              const SizedBox(height: 14),
              const Text('Zoom', style: TextStyle(fontWeight: FontWeight.w700)),
              Row(children: [
                IconButton.outlined(onPressed: () => _js('zoom(0.85)'), icon: const Icon(Icons.zoom_out)),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => _js("zoom('fit')"), child: const Text('Fit')),
                const SizedBox(width: 8),
                IconButton.outlined(onPressed: () => _js('zoom(1.2)'), icon: const Icon(Icons.zoom_in)),
              ]),
              const Text('Tip: pinch to zoom, double-tap to fit the page again.', style: TextStyle(fontSize: 12)),
            ]),
          ),
        );
      }),
    );
  }

  void _toggleBookmark() {
    final here = e.bookmarks.where((b) => b.section == _page - 1).toList();
    if (here.isNotEmpty) {
      e.bookmarks.removeWhere((b) => here.contains(b));
      _snack('Bookmark removed');
    } else {
      e.bookmarks.add(Bookmark('b${DateTime.now().microsecondsSinceEpoch}', _page - 1, 0,
          'Page $_page${_chapter.isNotEmpty ? ' · $_chapter' : ''}', DateTime.now()));
      _snack('Page $_page bookmarked');
    }
    _store.changed();
    setState(() {});
  }

  bool get _bookmarked => e.bookmarks.any((b) => b.section == _page - 1);

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final s = context.watch<EbookStore>().settings;
    final night = s.pdfTheme == 'night';
    final faint = night ? Colors.white54 : Colors.black45;
    if (_error != null) {
      return Scaffold(appBar: AppBar(title: Text(e.title)), body: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    return Scaffold(
      backgroundColor: _pdfThemes[s.pdfTheme]?.$1 ?? const Color(0xFFE9E4E6),
      body: Stack(children: [
        Positioned.fill(child: WebViewWidget(controller: _web)),
        if (!_ready) const Center(child: CircularProgressIndicator()),
        if (_pages > 0 && !_menu)
          Positioned(
            bottom: 6,
            left: 14,
            right: 14,
            child: IgnorePointer(
              child: Row(children: [
                Expanded(child: Text('Page $_page of $_pages', style: TextStyle(color: faint, fontSize: 12))),
                if (_bookmarked) const Icon(Icons.bookmark, color: Color(0xFFC2416B), size: 16),
                Text('  ${_mins(_leftSec)} left · ${(e.progress * 100).round()}%', style: TextStyle(color: faint, fontSize: 12)),
              ]),
            ),
          ),
        if (_searching)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              elevation: 6,
              child: SafeArea(
                bottom: false,
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _js('findClose()');
                      setState(() => _searching = false);
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _q,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(hintText: 'Search this PDF', border: InputBorder.none, filled: false),
                      onSubmitted: (v) => _js('find(${jsonEncode(v)})'),
                    ),
                  ),
                  Text(_found > 0 ? '$_foundAt/$_found' : (_q.text.isEmpty ? '' : '0')),
                  IconButton(icon: const Icon(Icons.keyboard_arrow_up), onPressed: () => _js('find(${jsonEncode(_q.text)}, true, true)')),
                  IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => _js('find(${jsonEncode(_q.text)}, true, false)')),
                ]),
              ),
            ),
          ),
        if (_selection.isNotEmpty && !_menu)
          Positioned(
            left: 8,
            right: 8,
            bottom: 30,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFF2A1823),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in _hl.keys) IconButton(tooltip: 'Highlight', onPressed: () => _highlight(k), icon: Icon(Icons.circle, color: _hl[k])),
                  _Btn(Icons.edit_note, 'Note', _note),
                  _Btn(Icons.menu_book, 'Define', _define),
                  _Btn(Icons.format_quote, 'Quote', _saveQuote),
                  _Btn(Icons.search, 'Web', () => launchUrl(Uri.parse('https://www.google.com/search?q=${Uri.encodeQueryComponent(_selection)}'),
                      mode: LaunchMode.externalApplication)),
                ]),
              ),
            ),
          ),
        if (_menu && !_searching) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: const Color(0xF22A1823),
              child: SafeArea(
                bottom: false,
                child: Row(children: [
                  IconButton(color: Colors.white, icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                  IconButton(color: Colors.white, tooltip: 'Contents', icon: const Icon(Icons.toc), onPressed: _showContents),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() {
                      _searching = true;
                      _menu = false;
                    }),
                  ),
                  IconButton(color: Colors.white, tooltip: 'Notes & highlights', icon: const Icon(Icons.sticky_note_2_outlined), onPressed: _showNotes),
                  IconButton(color: Colors.white, tooltip: 'Display', icon: const Icon(Icons.tune), onPressed: _showDisplay),
                  IconButton(color: Colors.white, tooltip: 'Bookmark', icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border), onPressed: _toggleBookmark),
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Material(
              color: const Color(0xF22A1823),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_chapter.isNotEmpty)
                      Text(_chapter, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text('Page $_page of $_pages · ${_mins(_leftSec)} left in book · ${(e.progress * 100).round()}%',
                        style: const TextStyle(color: Color(0xFFE2C6D3), fontSize: 12)),
                    Row(children: [
                      IconButton(color: Colors.white, icon: const Icon(Icons.chevron_left), onPressed: () => _js('prev()')),
                      Expanded(
                        child: Slider(
                          value: _page.clamp(1, _pages < 1 ? 1 : _pages).toDouble(),
                          min: 1,
                          max: (_pages < 2 ? 2 : _pages).toDouble(),
                          divisions: _pages > 1 ? _pages - 1 : 1,
                          label: 'Page $_page',
                          activeColor: const Color(0xFFF0AC2E),
                          onChanged: (v) => setState(() => _page = v.round()),
                          onChangeEnd: (v) => _js('goPage(${v.round()})'),
                        ),
                      ),
                      IconButton(color: Colors.white, icon: const Icon(Icons.chevron_right), onPressed: () => _js('next()')),
                    ]),
                    TextButton(
                      onPressed: _goToPage,
                      child: const Text('Go to page…', style: TextStyle(color: Color(0xFFF0AC2E))),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Btn(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
