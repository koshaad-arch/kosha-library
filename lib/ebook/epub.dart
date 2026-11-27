import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One reading-order section of an EPUB (usually a chapter).
class EpubSection {
  final String href; // path inside the zip
  final String title;
  final String html; // body HTML with images inlined
  final String text; // plain text, for search and progress
  EpubSection(this.href, this.title, this.html, this.text);
}

class TocEntry {
  final String title;
  final int section;
  final int depth;
  TocEntry(this.title, this.section, this.depth);
}

/// Minimal, dependable EPUB 2/3 reader: metadata, spine, table of contents, images.
class EpubBook {
  final String title, author, language;
  final List<EpubSection> sections;
  final List<TocEntry> toc;
  final Uint8List? cover;
  EpubBook(this.title, this.author, this.language, this.sections, this.toc, this.cover);

  int get totalChars => sections.fold(0, (s, x) => s + x.text.length);

  static String _dir(String p) => p.contains('/') ? p.substring(0, p.lastIndexOf('/') + 1) : '';

  static String _join(String base, String rel) {
    rel = Uri.decodeFull(rel.split('#').first);
    final parts = (base + rel).split('/');
    final out = <String>[];
    for (final p in parts) {
      if (p == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else if (p != '.' && p.isNotEmpty) {
        out.add(p);
      }
    }
    return out.join('/');
  }

  static String _mime(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.svg')) return 'image/svg+xml';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static EpubBook parse(Uint8List bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{};
    for (final f in zip.files) {
      if (f.isFile) files[f.name] = f;
    }
    List<int>? raw(String name) {
      final f = files[name] ?? files[Uri.decodeFull(name)];
      if (f == null) return null;
      return (f.content as List).cast<int>();
    }

    String? str(String name) {
      final b = raw(name);
      return b == null ? null : utf8.decode(b, allowMalformed: true);
    }

    final container = str('META-INF/container.xml');
    if (container == null) throw const FormatException('Not an EPUB file (no META-INF/container.xml).');
    final opfPath = XmlDocument.parse(container).findAllElements('rootfile').first.getAttribute('full-path')!;
    final opf = XmlDocument.parse(str(opfPath) ?? '');
    final base = _dir(opfPath);

    String meta(String local) {
      final e = opf.descendants.whereType<XmlElement>().where((x) => x.name.local == local);
      return e.isEmpty ? '' : e.first.innerText.trim();
    }

    final title = meta('title');
    final author = meta('creator');
    final language = meta('language');

    final manifest = <String, (String, String, String)>{}; // id -> (href, media-type, properties)
    for (final item in opf.descendants.whereType<XmlElement>().where((x) => x.name.local == 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (_join(base, href), item.getAttribute('media-type') ?? '', item.getAttribute('properties') ?? '');
    }

    // cover image
    Uint8List? cover;
    String? coverHref;
    for (final m in manifest.values) {
      if (m.$3.contains('cover-image')) coverHref = m.$1;
    }
    if (coverHref == null) {
      final metaCover = opf.descendants
          .whereType<XmlElement>()
          .where((x) => x.name.local == 'meta' && x.getAttribute('name') == 'cover');
      if (metaCover.isNotEmpty) coverHref = manifest[metaCover.first.getAttribute('content')]?.$1;
    }
    if (coverHref != null) {
      final c = raw(coverHref);
      if (c != null) cover = Uint8List.fromList(c);
    }

    // spine (reading order)
    final spineIds = opf.descendants
        .whereType<XmlElement>()
        .where((x) => x.name.local == 'itemref' && x.getAttribute('linear') != 'no')
        .map((x) => x.getAttribute('idref'))
        .whereType<String>()
        .toList();
    final hrefs = spineIds.map((id) => manifest[id]?.$1).whereType<String>().toList();

    // table of contents: EPUB3 nav, else EPUB2 NCX
    final tocRaw = <(String, String, int)>[]; // title, href, depth
    final navId = manifest.entries.where((e) => e.value.$3.contains('nav')).map((e) => e.value.$1).firstOrNull;
    if (navId != null && str(navId) != null) {
      try {
        final nav = XmlDocument.parse(str(navId)!);
        final navEl = nav.descendants
            .whereType<XmlElement>()
            .where((x) => x.name.local == 'nav' && (x.getAttribute('epub:type') ?? x.getAttribute('type') ?? '') == 'toc')
            .firstOrNull ??
            nav.descendants.whereType<XmlElement>().where((x) => x.name.local == 'nav').firstOrNull;
        if (navEl != null) {
          for (final a in navEl.descendants.whereType<XmlElement>().where((x) => x.name.local == 'a')) {
            final h = a.getAttribute('href');
            if (h == null) continue;
            var depth = 0;
            XmlNode? p = a.parent;
            while (p != null && p != navEl) {
              if (p is XmlElement && p.name.local == 'ol') depth++;
              p = p.parent;
            }
            tocRaw.add((a.innerText.trim().replaceAll(RegExp(r'\s+'), ' '), _join(_dir(navId), h), (depth - 1).clamp(0, 4)));
          }
        }
      } catch (_) {}
    }
    if (tocRaw.isEmpty) {
      final ncxHref = manifest.values.where((m) => m.$2.contains('ncx')).map((m) => m.$1).firstOrNull;
      if (ncxHref != null && str(ncxHref) != null) {
        try {
          final ncx = XmlDocument.parse(str(ncxHref)!);
          for (final np in ncx.descendants.whereType<XmlElement>().where((x) => x.name.local == 'navPoint')) {
            final label = np.descendants.whereType<XmlElement>().where((x) => x.name.local == 'text').firstOrNull?.innerText.trim() ?? '';
            final src = np.descendants.whereType<XmlElement>().where((x) => x.name.local == 'content').firstOrNull?.getAttribute('src');
            if (src == null) continue;
            var depth = 0;
            XmlNode? p = np.parent;
            while (p is XmlElement && p.name.local == 'navPoint') {
              depth++;
              p = p.parent;
            }
            tocRaw.add((label, _join(_dir(ncxHref), src), depth.clamp(0, 4)));
          }
        } catch (_) {}
      }
    }

    // sections with inlined images
    final sections = <EpubSection>[];
    for (final h in hrefs) {
      final src = str(h);
      if (src == null) continue;
      var body = src;
      final bm = RegExp(r'<body[^>]*>([\s\S]*)</body>', caseSensitive: false).firstMatch(src);
      if (bm != null) body = bm.group(1)!;
      body = body.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
      final dir = _dir(h);
      body = body.replaceAllMapped(
          RegExp(r'''(<(?:img|image)\b[^>]*?(?:src|xlink:href|href)\s*=\s*)(["'])([^"']+)\2''', caseSensitive: false), (m) {
        final target = m.group(3)!;
        if (target.startsWith('data:') || target.startsWith('http')) return m.group(0)!;
        final p = _join(dir, target);
        final b = raw(p);
        if (b == null) return m.group(0)!;
        return '${m.group(1)}${m.group(2)}data:${_mime(p)};base64,${base64Encode(b)}${m.group(2)}';
      });
      // keep internal links harmless
      body = body.replaceAllMapped(
          RegExp(r'''<a\b([^>]*?)href\s*=\s*(["'])[^"']*\2''', caseSensitive: false), (m) => '<a${m.group(1)}');
      final text = body
          .replaceAll(RegExp(r'<(style|head)[\s\S]*?</\1>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll(RegExp(r'&#?\w+;'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final t = RegExp(r'<h[1-3][^>]*>([\s\S]*?)</h[1-3]>', caseSensitive: false).firstMatch(body)?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
      sections.add(EpubSection(h, t, body, text));
    }

    final toc = <TocEntry>[];
    for (final e in tocRaw) {
      final idx = sections.indexWhere((s) => s.href == e.$2);
      if (idx >= 0 && e.$1.isNotEmpty) toc.add(TocEntry(e.$1, idx, e.$3));
    }
    if (toc.isEmpty) {
      for (var i = 0; i < sections.length; i++) {
        if (sections[i].text.length > 200) {
          toc.add(TocEntry(sections[i].title.isNotEmpty ? sections[i].title : 'Section ${i + 1}', i, 0));
        }
      }
    }
    return EpubBook(title.isEmpty ? 'Untitled' : title, author, language, sections, toc, cover);
  }
}
