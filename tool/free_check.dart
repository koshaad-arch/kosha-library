// CI check: download classics from the same mirror addresses the app uses and parse them.
// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;
import 'package:kosha_library/ebook/epub.dart';

Future<void> main() async {
  for (final id in [1342, 64317, 7164, 2600]) {
    final urls = [
      'https://gutenberg.pglaf.org/cache/epub/$id/pg$id-images-3.epub',
      'https://aleph.pglaf.org/cache/epub/$id/pg$id-images-3.epub',
      'https://gutenberg.pglaf.org/cache/epub/$id/pg$id.epub',
    ];
    var ok = false;
    for (final u in urls) {
      try {
        final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 150));
        final b = r.bodyBytes;
        if (r.statusCode == 200 && b.length > 1000 && b[0] == 0x50 && b[1] == 0x4B) {
          final e = EpubBook.parse(b);
          print('FREE OK $id from $u: "${e.title}" by ${e.author} · ${e.sections.length} sections · ${e.toc.length} toc · ${(b.length / 1024).round()} KB');
          ok = true;
          break;
        }
        print('FREE try $id $u -> ${r.statusCode}');
      } catch (err) {
        print('FREE try $id $u -> $err');
      }
    }
    if (!ok) print('FREE FAILED $id');
  }
}
