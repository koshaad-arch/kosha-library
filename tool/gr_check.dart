// CI smoke test for the Goodreads CSV import parser (no Flutter needed).
// ignore_for_file: avoid_print
import 'package:kosha_library/services/goodreads_sync.dart';

void main() {
  print('GR CHECK matchKey: ${GoodreadsSync.matchKey("The Silent Patient", "Alex Michaelides")}');
}
