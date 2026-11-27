// CI check: look up real page counts for books in the bundled list that have none.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:kosha_library/models/book.dart';
import 'package:kosha_library/services/page_finder.dart';

Future<void> main() async {
  final list = (jsonDecode(File('tool/sample_books.json').readAsStringSync()) as List)
      .map((e) => Book.fromJson(Map<String, dynamic>.from(e as Map)))
      .where((b) => (b.pages ?? 0) <= 0)
      .toList();
  print('PAGES missing in bundled list: ${list.length}');
  var found = 0;
  for (final b in list.take(15)) {
    final (p, cats) = await PageFinder.find(b);
    if (p != null) found++;
    print('PAGES ${b.title} | ${b.isbn} -> ${p ?? 'not found'} | ${cats.length > 60 ? cats.substring(0, 60) : cats}');
  }
  print('PAGES found $found of ${list.take(15).length}');
}
