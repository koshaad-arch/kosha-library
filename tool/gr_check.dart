// CI smoke test: fetch a public Goodreads profile's shelves and print a summary.
// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;
import 'package:kosha_library/services/goodreads_sync.dart';

Future<void> main(List<String> args) async {
  final input = args.isEmpty ? '152185079' : args.first;
  final acc = GoodreadsSync.parse(input);
  if (acc == null) {
    print('GR CHECK could not parse $input');
    return;
  }
  for (final path in ['/review/list_rss/${acc.userId}?shelf=read', '/user/show/${acc.userId}']) {
    final r = await http.get(Uri.parse('https://www.goodreads.com$path'), headers: {'User-Agent': 'KoshasLibrary/1.0'});
    final body = r.body.replaceAll(RegExp(r'\s+'), ' ');
    print('GR RAW $path -> ${r.statusCode} ${r.headers['content-type']} :: ${body.substring(0, body.length < 220 ? body.length : 220)}');
  }
  try {
    final items = await GoodreadsSync.fetchAll(acc);
    final byShelf = <String, int>{};
    for (final i in items) {
      byShelf[i.shelf] = (byShelf[i.shelf] ?? 0) + 1;
    }
    print('GR CHECK user ${acc.userId}: ${items.length} items $byShelf');
    for (final i in items.take(5)) {
      print('  ${i.shelf} | ${i.title} | ${i.author} | isbn=${i.isbn} | rating=${i.rating} | read=${i.readAt} | pages=${i.pages} | img=${i.imageUrl.isNotEmpty}');
    }
  } catch (e) {
    print('GR CHECK FAILED: $e');
  }
}
