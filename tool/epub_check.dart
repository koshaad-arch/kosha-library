// CI check: parse a real EPUB and print what the reader will see.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:kosha_library/ebook/epub.dart';

void main(List<String> args) {
  for (final path in args) {
    try {
      final b = EpubBook.parse(File(path).readAsBytesSync());
      print('EPUB OK $path: "${b.title}" by ${b.author} · ${b.sections.length} sections · ${b.toc.length} toc · '
          '${b.totalChars} chars · cover=${b.cover?.length ?? 0} bytes');
      for (final t in b.toc.take(6)) {
        print('  toc: ${'  ' * t.depth}${t.title} -> section ${t.section}');
      }
      final s = b.sections.firstWhere((x) => x.text.length > 500, orElse: () => b.sections.first);
      print('  sample: ${s.text.substring(0, s.text.length < 160 ? s.text.length : 160)}');
      print('  images inlined: ${b.sections.fold<int>(0, (n, x) => n + 'data:image'.allMatches(x.html).length)}');
    } catch (e, st) {
      print('EPUB FAILED $path: $e\n$st');
    }
  }
}
