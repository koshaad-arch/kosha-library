// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? '152185079' : args.first;
  const ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36'};
  final page = await http.get(Uri.parse('https://www.goodreads.com/review/list/$id?shelf=read'), headers: ua);
  print('PROBE shelf page ${page.statusCode} len=${page.body.length}');
  final links = RegExp(r'''https?://www\.goodreads\.com/review/list_rss/[^"'\s<]+''').allMatches(page.body).map((m) => m.group(0)!).toSet();
  final rel = RegExp(r'''["'](/review/list_rss/[^"'\s<]+)''').allMatches(page.body).map((m) => m.group(1)!).toSet();
  print('PROBE rss links abs=${links.length} rel=${rel.length}');
  for (final l in [...links, ...rel.map((r) => 'https://www.goodreads.com$r')].take(3)) {
    final u = l.replaceAll('&amp;', '&');
    final r = await http.get(Uri.parse(u), headers: ua);
    final b = r.body.replaceAll(RegExp(r'\s+'), ' ');
    print('PROBE ${u.replaceAll(RegExp(r'key=[^&]+'), 'key=XXX')} -> ${r.statusCode} items=${'<item>'.allMatches(r.body).length} :: ${b.substring(0, b.length < 160 ? b.length : 160)}');
  }
  for (final u in ['https://www.goodreads.com/review/list_rss/$id', 'https://www.goodreads.com/review/list/$id.xml?shelf=read', 'https://www.goodreads.com/user/updates_rss/$id']) {
    final r = await http.get(Uri.parse(u), headers: ua);
    print('PROBE $u -> ${r.statusCode} items=${'<item>'.allMatches(r.body).length}');
  }
}
