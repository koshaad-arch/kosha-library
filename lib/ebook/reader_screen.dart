import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import 'ebook_store.dart';
import 'epub.dart';

const _themes = {
  'white': (Color(0xFFFFFFFF), Color(0xFF1A1A1A), 'White'),
  'sepia': (Color(0xFFF6EEDC), Color(0xFF3B2F22), 'Sepia'),
  'green': (Color(0xFFDCEBDD), Color(0xFF1E2B1F), 'Green'),
  'dark': (Color(0xFF2B2B2E), Color(0xFFE3E3E3), 'Dark'),
  'black': (Color(0xFF000000), Color(0xFFC8C8C8), 'Black'),
};
const _fonts = {
  'serif': ('Serif', "'Noto Serif', Georgia, serif"),
  'sans': ('Sans', "Roboto, 'Noto Sans', sans-serif"),
  'condensed': ('Condensed', "'sans-serif-condensed', 'Roboto Condensed', sans-serif"),
  'mono': ('Mono', "'Droid Sans Mono', monospace"),
};
const _hlColors = {
  'y': Color(0xFFFDE68A),
  'b': Color(0xFFBFDBFE),
  'p': Color(0xFFFBCFE8),
  'o': Color(0xFFFED7AA),
};

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class ReaderScreen extends StatefulWidget {
  final Ebook ebook;
  const ReaderScreen({super.key, required this.ebook});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final WebViewController _web;
  EpubBook? _book;
  String? _error;
  int _section = 0;
  int _page = 0, _pages = 1;
  bool _menu = false;
  String _selection = '';
  DateTime _lastTurn = DateTime.now();
  DateTime _sessionStart = DateTime.now();
  String? _pendingFind;
  List<int> _charsBefore = [];
  Timer? _clock;

  Ebook get e => widget.ebook;
  EbookStore get _store => context.read<EbookStore>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('K', onMessageReceived: (m) => _onMsg(m.message));
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await _store.open(e);
      var acc = 0;
      _charsBefore = [for (final s in b.sections) (acc += s.text.length) - s.text.length];
      setState(() => _book = b);
      final lib = context.read<LibraryStore>();
      final shelf = lib.byId(e.bookId);
      if (shelf != null && shelf.status == ReadStatus.tbr) lib.setStatus(shelf, ReadStatus.reading);
      e.lastOpened = DateTime.now();
      _store.changed();
      _render(e.section.clamp(0, b.sections.length - 1), frac: e.frac);
    } catch (err) {
      setState(() => _error = 'This book could not be opened. $err');
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _saveSession();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _saveSession() {
    final secs = DateTime.now().difference(_sessionStart).inSeconds;
    if (secs > 0 && secs < 6 * 3600) {
      // reading time is counted via page turns; this only keeps the last position safe
    }
    _store.save();
  }

  // ---------------------------------------------------------------- rendering
  void _render(int section, {double frac = 0, bool last = false}) {
    final b = _book;
    if (b == null) return;
    _section = section;
    final s = _store.settings;
    final (bg, fg, _) = _themes[s.theme] ?? _themes['white']!;
    final dark = s.theme == 'dark' || s.theme == 'black';
    final hls = e.highlights.where((h) => h.section == section).map((h) => {'id': h.id, 'c': h.color, 't': h.text}).toList();
    final init = last ? -1.0 : frac;
    final css = '''
html,body{margin:0;padding:0;height:100%;overflow:hidden;background:${_hex(bg)};color:${_hex(fg)};-webkit-text-size-adjust:none;-webkit-tap-highlight-color:transparent}
#c{position:absolute;left:${s.margin}px;top:34px;height:calc(100vh - 74px);width:calc(100vw - ${s.margin * 2}px);
 column-width:calc(100vw - ${s.margin * 2}px);column-gap:${s.margin * 2}px;column-fill:auto;
 font-family:${_fonts[s.font]?.$2 ?? 'serif'};font-size:${s.fontSize}px;line-height:${s.lineHeight};
 text-align:${s.justify ? 'justify' : 'left'};hyphens:auto;-webkit-hyphens:auto;overflow-wrap:break-word;will-change:transform}
#c *{max-width:100%;box-sizing:border-box;font-family:inherit!important;color:inherit!important;background:transparent!important;line-height:inherit}
#c img,#c svg,#c image{max-width:100%!important;max-height:calc(100vh - 90px)!important;height:auto!important;width:auto;display:block;margin:.6em auto;break-inside:avoid}
#c p{margin:0 0 .7em}#c h1,#c h2,#c h3{line-height:1.25;text-align:left;break-after:avoid}
#c a{text-decoration:none}
mark{color:inherit!important;border-radius:2px;padding:0 1px}
mark.y{background:${dark ? 'rgba(253,230,138,.38)' : '#fde68a'}!important}mark.b{background:${dark ? 'rgba(147,197,253,.38)' : '#bfdbfe'}!important}
mark.p{background:${dark ? 'rgba(249,168,212,.38)' : '#fbcfe8'}!important}mark.o{background:${dark ? 'rgba(253,186,116,.38)' : '#fed7aa'}!important}
''';
    final js = '''
const c=document.getElementById('c');let page=0,pages=1;const W=()=>window.innerWidth;
function count(){pages=Math.max(1,Math.ceil((c.scrollWidth-4)/W()));}
function send(o){K.postMessage(JSON.stringify(o))}
function go(p,anim){count();page=Math.max(0,Math.min(pages-1,p));c.style.transition=anim?'transform .22s ease-out':'none';c.style.transform='translateX('+(-page*W())+'px)';send({t:'page',page:page,pages:pages})}
function next(){count();if(page<pages-1)go(page+1,true);else send({t:'next'})}
function prev(){if(page>0)go(page-1,true);else send({t:'prev'})}
function frac(f){count();go(f<0?pages-1:Math.round(f*(pages-1)),false)}
function wrapRange(r,id,color){const nodes=[];const root=r.commonAncestorContainer;
 if(root.nodeType===3){nodes.push(root)}else{const it=document.createNodeIterator(root,NodeFilter.SHOW_TEXT);let n;while(n=it.nextNode()){if(r.intersectsNode(n))nodes.push(n)}}
 nodes.forEach(n=>{let s=0,e=n.length;if(n===r.startContainer)s=r.startOffset;if(n===r.endContainer)e=r.endOffset;if(s>=e||!n.data.slice(s,e).trim())return;
  const mid=n.splitText(s);mid.splitText(e-s);const m=document.createElement('mark');m.className=color;m.dataset.id=id;mid.parentNode.insertBefore(m,mid);m.appendChild(mid)})}
function selectFrom(text){const sel=getSelection();sel.removeAllRanges();const r0=document.createRange();r0.setStart(c,0);r0.collapse(true);sel.addRange(r0);
 return window.find(text,false,false,false,false,false,false)}
function apply(id,color,text){try{if(selectFrom(text))wrapRange(getSelection().getRangeAt(0),id,color)}catch(e){}getSelection().removeAllRanges()}
function hl(id,color){const s=getSelection();if(!s.rangeCount)return;wrapRange(s.getRangeAt(0),id,color);s.removeAllRanges()}
function unmark(id){document.querySelectorAll('mark[data-id="'+id+'"]').forEach(m=>{m.replaceWith(...m.childNodes)})}
function recolor(id,color){document.querySelectorAll('mark[data-id="'+id+'"]').forEach(m=>m.className=color)}
function findGo(text){try{if(selectFrom(text)){const rect=getSelection().getRangeAt(0).getBoundingClientRect();count();go(Math.floor((rect.left+page*W())/W()),false);setTimeout(()=>getSelection().removeAllRanges(),2500);return}}catch(e){}send({t:'nofind'})}
function pageText(){const r=document.caretRangeFromPoint?document.caretRangeFromPoint(${s.margin + 4},44):null;if(!r)return '';const n=r.startContainer;return (n.textContent||'').slice(r.startOffset,r.startOffset+90)}
let sx=0,sy=0,st=0,moved=false;
document.addEventListener('touchstart',ev=>{const t=ev.touches[0];sx=t.clientX;sy=t.clientY;st=Date.now();moved=false},{passive:true});
document.addEventListener('touchmove',ev=>{moved=true},{passive:true});
document.addEventListener('touchend',ev=>{const t=ev.changedTouches[0];const dx=t.clientX-sx,dy=t.clientY-sy;if(String(getSelection()).trim())return;
 if(Math.abs(dx)>45&&Math.abs(dx)>Math.abs(dy)*1.3){dx<0?next():prev();return}
 if(Date.now()-st<400&&Math.abs(dx)<12&&Math.abs(dy)<12){const mk=ev.target.closest&&ev.target.closest('mark');if(mk){send({t:'mark',id:mk.dataset.id});return}
  const x=t.clientX/W();if(x<0.28)prev();else if(x>0.72)next();else send({t:'menu'})}});
let selT=null;document.addEventListener('selectionchange',()=>{clearTimeout(selT);selT=setTimeout(()=>send({t:'sel',text:String(getSelection()).trim().slice(0,3000)}),300)});
window.addEventListener('resize',()=>{const f=pages>1?page/(pages-1):0;setTimeout(()=>frac(f),120)});
const HL=${jsonEncode(hls).replaceAll('</', '<\\/')};
function boot(){HL.forEach(h=>apply(h.id,h.c,h.t));frac($init);send({t:'ready'})}
if(document.readyState==='complete')setTimeout(boot,60);else window.addEventListener('load',()=>setTimeout(boot,60));
''';
    final html = '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">'
        '<style>$css</style></head><body><div id="c">${b.sections[section].html}</div><script>$js</script></body></html>';
    _web.setBackgroundColor(bg);
    _web.loadHtmlString(html);
    setState(() {
      _page = 0;
      _pages = 1;
      _selection = '';
    });
  }

  void _onMsg(String raw) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'page':
        final p = m['page'] as int, n = m['pages'] as int;
        if ((p - _page).abs() == 1 && n == _pages) _countTurn();
        setState(() {
          _page = p;
          _pages = n;
        });
        _savePos();
      case 'ready':
        final f = _pendingFind;
        if (f != null) {
          _pendingFind = null;
          _js('findGo(${jsonEncode(f)})');
        }
      case 'next':
        if (_section < _book!.sections.length - 1) {
          _countTurn();
          _render(_section + 1);
        } else {
          _finished();
        }
      case 'prev':
        if (_section > 0) _render(_section - 1, last: true);
      case 'menu':
        setState(() => _menu = !_menu);
      case 'sel':
        setState(() => _selection = (m['text'] ?? '') as String);
      case 'mark':
        _markTapped(m['id'] as String);
      case 'nofind':
        _snack('Could not find that spot on the page.');
    }
  }

  void _js(String code) => _web.runJavaScript(code);

  void _countTurn() {
    final now = DateTime.now();
    final dt = now.difference(_lastTurn).inSeconds;
    _lastTurn = now;
    if (dt >= 2 && dt <= 600) {
      e.readSeconds += dt;
      e.pagesTurned++;
    }
  }

  void _savePos() {
    final b = _book;
    if (b == null) return;
    e.section = _section;
    e.frac = _pages > 1 ? _page / (_pages - 1) : 0;
    final total = b.totalChars == 0 ? 1 : b.totalChars;
    e.progress = ((_charsBefore[_section] + e.frac * b.sections[_section].text.length) / total).clamp(0, 1).toDouble();
    _store.save();
    final lib = context.read<LibraryStore>();
    final shelf = lib.byId(e.bookId);
    if (shelf != null && (shelf.pages ?? 0) > 0) {
      final cp = (e.progress * shelf.pages!).round();
      if (cp != shelf.currentPage && shelf.status != ReadStatus.read) {
        shelf.currentPage = cp;
        lib.touch(shelf);
      }
    }
  }

  // ---------------------------------------------------------------- helpers
  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3)));
  }

  String _mins(double seconds) {
    final m = (seconds / 60).round();
    if (m < 1) return 'less than a minute';
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return '$h h ${r > 0 ? '$r min' : ''}'.trim();
  }

  String get _chapterTitle {
    final b = _book;
    if (b == null) return '';
    String t = '';
    for (final x in b.toc) {
      if (x.section <= _section) t = x.title;
    }
    return t.isNotEmpty ? t : (b.sections[_section].title.isNotEmpty ? b.sections[_section].title : 'Section ${_section + 1}');
  }

  double get _leftInChapterSec => (_pages - 1 - _page).clamp(0, 1 << 20) * e.secPerPage;

  double get _leftInBookSec {
    final b = _book;
    if (b == null || _pages == 0) return 0;
    final charsPerPage = (b.sections[_section].text.length / _pages).clamp(400, 5000);
    final remaining = b.totalChars * (1 - e.progress);
    return remaining / charsPerPage * e.secPerPage;
  }

  void _finished() {
    final lib = context.read<LibraryStore>();
    final shelf = lib.byId(e.bookId);
    showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉 You reached the end', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(e.title, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (shelf != null && shelf.status != ReadStatus.read)
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Mark as read & rate it'),
                onPressed: () {
                  lib.setStatus(shelf, ReadStatus.read);
                  Navigator.pop(c);
                  Navigator.pop(context, 'rate');
                },
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Keep reading')),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- selection actions
  void _highlight(String color) {
    final text = _selection;
    if (text.isEmpty) return;
    final h = Highlight('h${DateTime.now().microsecondsSinceEpoch}', _section, text, color, '', DateTime.now());
    e.highlights.add(h);
    _store.changed();
    _js("hl('${h.id}','$color')");
    setState(() => _selection = '');
  }

  Future<void> _noteForSelection() async {
    final text = _selection;
    if (text.isEmpty) return;
    final note = await _askNote('');
    if (note == null) return;
    final h = Highlight('h${DateTime.now().microsecondsSinceEpoch}', _section, text, 'y', note, DateTime.now());
    e.highlights.add(h);
    _store.changed();
    _js("hl('${h.id}','y')");
    setState(() => _selection = '');
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('“${h.text}”', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic)),
              if (h.note.isNotEmpty) ...[const SizedBox(height: 8), Text('Note: ${h.note}')],
              const SizedBox(height: 12),
              Row(children: [
                for (final k in _hlColors.keys)
                  IconButton(
                    onPressed: () {
                      h.color = k;
                      _store.changed();
                      _js("recolor('${h.id}','$k')");
                      Navigator.pop(c);
                    },
                    icon: Icon(Icons.circle, color: _hlColors[k], size: 30),
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
                    Clipboard.setData(ClipboardData(text: '“${h.text}” — ${e.title}, ${e.author}'));
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _define() async {
    final word = _selection.trim().split(RegExp(r'\s+')).first.replaceAll(RegExp(r'''^[^\w]+|[^\w]+$'''), '');
    if (word.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DefinitionSheet(word: word),
    );
  }

  void _saveQuote() {
    final lib = context.read<LibraryStore>();
    final shelf = lib.byId(e.bookId);
    if (shelf == null) return;
    shelf.quote = _selection;
    lib.touch(shelf);
    _snack('Saved as this book’s favourite quote');
    setState(() => _selection = '');
  }

  // ---------------------------------------------------------------- sheets
  void _showToc() {
    final b = _book!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (c, sc) => ListView(
          controller: sc,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Contents', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            for (final t in b.toc)
              ListTile(
                contentPadding: EdgeInsets.only(left: 16.0 + t.depth * 18, right: 16),
                title: Text(t.title, style: TextStyle(fontWeight: t.section == _section ? FontWeight.w700 : FontWeight.w400)),
                trailing: Text('${(_charsBefore[t.section] / (b.totalChars == 0 ? 1 : b.totalChars) * 100).round()}%'),
                onTap: () {
                  Navigator.pop(c);
                  setState(() => _menu = false);
                  _render(t.section);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showNotes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final hl = [...e.highlights]..sort((a, b) => a.section != b.section ? a.section.compareTo(b.section) : a.created.compareTo(b.created));
          final bm = [...e.bookmarks]..sort((a, b) => a.section != b.section ? a.section.compareTo(b.section) : a.frac.compareTo(b.frac));
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (c2, sc) => ListView(
              controller: sc,
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  const Expanded(child: Text('Notes & highlights', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                  if (hl.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.copy_all),
                      label: const Text('Copy all'),
                      onPressed: () {
                        final txt = '${e.title} — ${e.author}\n\n' +
                            hl.map((h) => '“${h.text}”${h.note.isNotEmpty ? '\nNote: ${h.note}' : ''}').join('\n\n');
                        Clipboard.setData(ClipboardData(text: txt));
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
                        _render(x.section, frac: x.frac);
                      },
                    ),
                ],
                const Padding(padding: EdgeInsets.only(top: 8, bottom: 4), child: Text('Highlights', style: TextStyle(fontWeight: FontWeight.w700))),
                if (hl.isEmpty) const Text('Press and hold on any words while reading to highlight them, add a note or look them up.'),
                for (final h in hl)
                  ListTile(
                    leading: Icon(Icons.format_quote, color: _hlColors[h.color]),
                    title: Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                    subtitle: h.note.isNotEmpty ? Text('Note: ${h.note}') : null,
                    onTap: () {
                      Navigator.pop(c);
                      setState(() => _menu = false);
                      _pendingFind = h.text;
                      _render(h.section);
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSearch() {
    final b = _book!;
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final q = ctrl.text.trim().toLowerCase();
        final hits = <(int, int, String)>[];
        if (q.length >= 2) {
          for (var i = 0; i < b.sections.length && hits.length < 150; i++) {
            final t = b.sections[i].text;
            final lower = t.toLowerCase();
            var from = 0;
            while (hits.length < 150) {
              final at = lower.indexOf(q, from);
              if (at < 0) break;
              final s0 = (at - 50).clamp(0, t.length), s1 = (at + q.length + 70).clamp(0, t.length);
              hits.add((i, at, '…${t.substring(s0, s1)}…'));
              from = at + q.length;
            }
          }
        }
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(c).size.height * 0.8,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Search this book', prefixIcon: Icon(Icons.search)),
                  onChanged: (_) => set(() {}),
                ),
              ),
              if (q.length >= 2) Text('${hits.length}${hits.length >= 150 ? '+' : ''} results'),
              Expanded(
                child: ListView(
                  children: [
                    for (final h in hits)
                      ListTile(
                        title: Text(h.$3, maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${(_charsBefore[h.$1] / (b.totalChars == 0 ? 1 : b.totalChars) * 100).round()}% · ${b.sections[h.$1].title}'),
                        onTap: () {
                          Navigator.pop(c);
                          setState(() => _menu = false);
                          _pendingFind = b.sections[h.$1].text.substring(h.$2, (h.$2 + q.length).clamp(0, b.sections[h.$1].text.length));
                          _render(h.$1);
                        },
                      ),
                  ],
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final s = _store.settings;
        void apply() {
          _store.changed();
          set(() {});
          final f = _pages > 1 ? _page / (_pages - 1) : 0.0;
          _render(_section, frac: f);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('A', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Slider(
                      value: s.fontSize,
                      min: 13,
                      max: 32,
                      divisions: 19,
                      label: '${s.fontSize.round()}',
                      onChanged: (v) => set(() => s.fontSize = v),
                      onChangeEnd: (_) => apply(),
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 26)),
                ]),
                Wrap(spacing: 6, children: [
                  for (final f in _fonts.entries)
                    ChoiceChip(
                      label: Text(f.value.$1),
                      selected: s.font == f.key,
                      onSelected: (_) {
                        s.font = f.key;
                        apply();
                      },
                    ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  for (final t in _themes.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          s.theme = t.key;
                          apply();
                        },
                        child: Column(children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: t.value.$1,
                              shape: BoxShape.circle,
                              border: Border.all(color: s.theme == t.key ? const Color(0xFFC2416B) : Colors.grey, width: s.theme == t.key ? 3 : 1),
                            ),
                            child: Center(child: Text('Aa', style: TextStyle(color: t.value.$2, fontWeight: FontWeight.w700))),
                          ),
                          Text(t.value.$3, style: const TextStyle(fontSize: 11)),
                        ]),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                const Text('Line spacing', style: TextStyle(fontWeight: FontWeight.w700)),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 1.3, label: Text('Tight')),
                    ButtonSegment(value: 1.6, label: Text('Normal')),
                    ButtonSegment(value: 2.0, label: Text('Wide')),
                  ],
                  selected: {[1.3, 1.6, 2.0].reduce((a, b) => (a - s.lineHeight).abs() < (b - s.lineHeight).abs() ? a : b)},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    s.lineHeight = v.first;
                    apply();
                  },
                ),
                const SizedBox(height: 8),
                const Text('Margins', style: TextStyle(fontWeight: FontWeight.w700)),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 12, label: Text('Narrow')),
                    ButtonSegment(value: 22, label: Text('Normal')),
                    ButtonSegment(value: 40, label: Text('Wide')),
                  ],
                  selected: {[12, 22, 40].reduce((a, b) => (a - s.margin).abs() < (b - s.margin).abs() ? a : b)},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    s.margin = v.first;
                    apply();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Justify text'),
                  value: s.justify,
                  onChanged: (v) {
                    s.justify = v;
                    apply();
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _toggleBookmark() async {
    final f = _pages > 1 ? _page / (_pages - 1) : 0.0;
    final here = e.bookmarks.where((b) => b.section == _section && (b.frac - f).abs() < 0.5 / (_pages == 0 ? 1 : _pages)).toList();
    if (here.isNotEmpty) {
      e.bookmarks.removeWhere((b) => here.contains(b));
      _store.changed();
      setState(() {});
      _snack('Bookmark removed');
      return;
    }
    String snippet = '';
    try {
      final r = await _web.runJavaScriptReturningResult('pageText()');
      snippet = (r is String ? r : '$r').replaceAll('"', '').trim();
    } catch (_) {}
    final label = '${_chapterTitle} · ${(e.progress * 100).round()}%${snippet.isNotEmpty ? ' — “$snippet…”' : ''}';
    e.bookmarks.add(Bookmark('b${DateTime.now().microsecondsSinceEpoch}', _section, f, label, DateTime.now()));
    _store.changed();
    setState(() {});
    _snack('Page bookmarked');
  }

  bool get _isBookmarked {
    final f = _pages > 1 ? _page / (_pages - 1) : 0.0;
    return e.bookmarks.any((b) => b.section == _section && (b.frac - f).abs() < 0.5 / (_pages == 0 ? 1 : _pages));
  }

  void _jumpToProgress(double p) {
    final b = _book!;
    final target = p * b.totalChars;
    var s = 0;
    for (var i = 0; i < b.sections.length; i++) {
      if (_charsBefore[i] <= target) s = i;
    }
    final len = b.sections[s].text.length;
    final f = len == 0 ? 0.0 : ((target - _charsBefore[s]) / len).clamp(0.0, 1.0);
    _render(s, frac: f);
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final s = context.watch<EbookStore>().settings;
    final (bg, fg, _) = _themes[s.theme] ?? _themes['white']!;
    final faint = fg.withValues(alpha: 0.55);
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    if (_book == null) {
      return Scaffold(backgroundColor: bg, body: const Center(child: CircularProgressIndicator()));
    }
    final now = TimeOfDay.now().format(context);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _web)),
          // always-visible header / footer (like Kindle)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Row(children: [
                Expanded(child: Text(_chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: faint, fontSize: 12))),
                if (_isBookmarked) Icon(Icons.bookmark, color: const Color(0xFFC2416B).withValues(alpha: 0.9), size: 20),
                const SizedBox(width: 8),
                Text(now, style: TextStyle(color: faint, fontSize: 12)),
              ]),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Row(children: [
                Expanded(
                  child: Text('${_mins(_leftInChapterSec)} left in chapter',
                      style: TextStyle(color: faint, fontSize: 12)),
                ),
                Text('${(e.progress * 100).round()}%', style: TextStyle(color: faint, fontSize: 12)),
              ]),
            ),
          ),
          if (_selection.isNotEmpty && !_menu)
            Positioned(
              left: 8,
              right: 8,
              bottom: 36,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF2A1823),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final k in _hlColors.keys)
                        IconButton(tooltip: 'Highlight', onPressed: () => _highlight(k), icon: Icon(Icons.circle, color: _hlColors[k])),
                      _SelBtn(icon: Icons.edit_note, label: 'Note', onTap: _noteForSelection),
                      _SelBtn(icon: Icons.menu_book, label: 'Define', onTap: _define),
                      _SelBtn(icon: Icons.format_quote, label: 'Quote', onTap: _saveQuote),
                      _SelBtn(
                        icon: Icons.search,
                        label: 'Web',
                        onTap: () => launchUrl(Uri.parse('https://www.google.com/search?q=${Uri.encodeQueryComponent(_selection)}'),
                            mode: LaunchMode.externalApplication),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          if (_menu) ...[
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
                    Expanded(
                      child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(color: Colors.white, tooltip: 'Contents', icon: const Icon(Icons.toc), onPressed: _showToc),
                    IconButton(color: Colors.white, tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _showSearch),
                    IconButton(color: Colors.white, tooltip: 'Notes & highlights', icon: const Icon(Icons.sticky_note_2_outlined), onPressed: _showNotes),
                    IconButton(color: Colors.white, tooltip: 'Text & theme', icon: const Icon(Icons.text_fields), onPressed: _showSettings),
                    IconButton(
                      color: Colors.white,
                      tooltip: 'Bookmark this page',
                      icon: Icon(_isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                      onPressed: _toggleBookmark,
                    ),
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
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      Text(
                        'Page ${_page + 1} of $_pages in this chapter · ${_mins(_leftInChapterSec)} left in chapter · ${_mins(_leftInBookSec)} left in book',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFE2C6D3), fontSize: 12),
                      ),
                      Row(children: [
                        IconButton(
                          color: Colors.white,
                          tooltip: 'Previous chapter',
                          icon: const Icon(Icons.skip_previous),
                          onPressed: _section > 0 ? () => _render(_section - 1) : null,
                        ),
                        Expanded(
                          child: Slider(
                            value: e.progress.clamp(0.0, 1.0),
                            onChanged: (v) => setState(() => e.progress = v),
                            onChangeEnd: _jumpToProgress,
                            activeColor: const Color(0xFFF0AC2E),
                            label: '${(e.progress * 100).round()}%',
                            divisions: 200,
                          ),
                        ),
                        IconButton(
                          color: Colors.white,
                          tooltip: 'Next chapter',
                          icon: const Icon(Icons.skip_next),
                          onPressed: _section < _book!.sections.length - 1 ? () => _render(_section + 1) : null,
                        ),
                      ]),
                      Text('${(e.progress * 100).round()}% read · tap the middle of the page to hide',
                          style: const TextStyle(color: Color(0xFFE2C6D3), fontSize: 11)),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SelBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

class DefinitionSheet extends StatefulWidget {
  final String word;
  const DefinitionSheet({super.key, required this.word});
  @override
  State<DefinitionSheet> createState() => _DefinitionSheetState();
}

class _DefinitionSheetState extends State<DefinitionSheet> {
  List<(String, String)>? _defs; // part of speech, definition
  String _phonetic = '';
  String? _err;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final r = await http
          .get(Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/${widget.word.toLowerCase()}'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        setState(() => _err = 'No dictionary entry for “${widget.word}”.');
        return;
      }
      final list = jsonDecode(r.body) as List;
      final out = <(String, String)>[];
      for (final entry in list) {
        final m = entry as Map;
        if (_phonetic.isEmpty) _phonetic = (m['phonetic'] ?? '') as String;
        for (final meaning in (m['meanings'] as List? ?? [])) {
          final mm = meaning as Map;
          for (final d in (mm['definitions'] as List? ?? []).take(3)) {
            out.add(((mm['partOfSpeech'] ?? '') as String, ((d as Map)['definition'] ?? '') as String));
          }
        }
      }
      setState(() => _defs = out.take(8).toList());
    } catch (_) {
      setState(() => _err = 'Couldn’t reach the dictionary. Check your internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.word, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            if (_phonetic.isNotEmpty) Text(_phonetic, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            if (_defs == null && _err == null) const LinearProgressIndicator(),
            if (_err != null) Text(_err!),
            if (_defs != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in _defs!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${d.$1}  ', style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFFC2416B))),
                          TextSpan(text: d.$2),
                        ])),
                      ),
                  ],
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('More on the web'),
              onPressed: () => launchUrl(Uri.parse('https://www.google.com/search?q=define+${Uri.encodeQueryComponent(widget.word)}'),
                  mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      ),
    );
  }
}
