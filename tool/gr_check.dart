// CI smoke test: fetch a public Goodreads profile's shelves and print a summary.
import 'package:kosha_library/services/goodreads_sync.dart';

Future<void> main(List<String> args) async {
  final acc = GoodreadsSync.parse(args.isEmpty ? '1' : args.first)!;
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
