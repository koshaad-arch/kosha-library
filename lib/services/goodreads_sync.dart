import '../models/book.dart';

/// One book as it appears on a Goodreads shelf RSS feed.
class GrItem {
  final String grId, title, author, isbn, review, imageUrl, description, shelf;
  final double rating;
  final DateTime? readAt, addedAt;
  final int? pages, year;
  GrItem({
    required this.grId,
    required this.title,
    required this.author,
    required this.isbn,
    required this.review,
    required this.imageUrl,
    required this.description,
    required this.shelf,
    required this.rating,
    required this.readAt,
    required this.addedAt,
    required this.pages,
    required this.year,
  });

  ReadStatus get status => switch (shelf) {
        'read' => ReadStatus.read,
        'currently-reading' => ReadStatus.reading,
        _ => ReadStatus.tbr,
      };

  /// Changes only when something on Goodreads changes, so local edits are kept
  /// until you change that book on Goodreads again.
  String get signature =>
      '$shelf|${rating.toStringAsFixed(1)}|${readAt?.toIso8601String() ?? ''}|${review.hashCode}';
}

class GoodreadsSync {
  /// Loose key for matching the same book across sources.
  static String matchKey(String title, String author) {
    var t = title.toLowerCase();
    t = t.replaceAll(RegExp(r'\(.*?\)'), '').split(':').first;
    t = t.replaceAll(RegExp(r'^(the|a|an) '), '').replaceAll(RegExp(r'[^a-z0-9]'), '');
    final parts = author.toLowerCase().split(',').first.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last.replaceAll(RegExp(r'[^a-z]'), '');
    return '$t|$last';
  }

  static String amazonUrl(Book b) => b.isbn.isNotEmpty
      ? 'https://www.amazon.in/s?k=${Uri.encodeQueryComponent(b.isbn)}&i=stripbooks'
      : 'https://www.amazon.in/s?k=${Uri.encodeQueryComponent('${b.title} ${b.firstAuthor}')}&i=stripbooks';

  static String goodreadsUrl(Book b) => b.goodreadsId.isNotEmpty
      ? 'https://www.goodreads.com/book/show/${b.goodreadsId}'
      : 'https://www.goodreads.com/search?q=${Uri.encodeQueryComponent(b.isbn.isNotEmpty ? b.isbn : '${b.title} ${b.firstAuthor}')}';
}
