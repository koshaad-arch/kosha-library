import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book.dart';
import '../services/cover_service.dart';

const _palette = [
  [Color(0xFF7B2D4F), Color(0xFFFBE3EA)],
  [Color(0xFF1F4E5A), Color(0xFFE5F3EE)],
  [Color(0xFFE9B44C), Color(0xFF3B1F14)],
  [Color(0xFFF2D0C7), Color(0xFF6B2238)],
  [Color(0xFF2F2A4F), Color(0xFFF4D58D)],
  [Color(0xFFC4553B), Color(0xFFFFF0E2)],
  [Color(0xFF93A87D), Color(0xFF1F2B18)],
  [Color(0xFFD8C3E6), Color(0xFF3D2357)],
  [Color(0xFF0F3D3E), Color(0xFFF1B6A6)],
  [Color(0xFFF6E2B3), Color(0xFF7A2E1D)],
  [Color(0xFF5A3A2E), Color(0xFFF3D9C4)],
  [Color(0xFFB8D8E0), Color(0xFF173A4A)],
  [Color(0xFFE98AA4), Color(0xFF3A0F20)],
  [Color(0xFF264653), Color(0xFFE9C46A)],
];

int _hash(String s) {
  var h = 7;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

/// Shows the real cover (from the lookup, or Open Library by ISBN) and falls
/// back to a designed cover while loading or when none exists.
/// Shows the real cover (your own link, or one found online) and falls back to a
/// designed cover while loading or when none exists.
class BookCover extends StatelessWidget {
  final Book book;
  final double width;
  final bool showReal;
  const BookCover({super.key, required this.book, this.width = 120, this.showReal = true});

  @override
  Widget build(BuildContext context) {
    final designed = DesignedCover(title: book.title, author: book.firstAuthor, width: width);
    Widget child = designed;
    if (showReal) {
      child = ValueListenableBuilder<String?>(
        valueListenable: CoverService.instance.coverFor(book),
        builder: (context, url, _) => (url == null || url.isEmpty)
            ? designed
            : Image.network(
                url,
                width: width,
                height: width * 1.5,
                fit: BoxFit.cover,
                loadingBuilder: (c, w, p) => p == null ? w : designed,
                errorBuilder: (c, e, s) => designed,
              ),
      );
    }
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          bottomLeft: Radius.circular(3),
          topRight: Radius.circular(9),
          bottomRight: Radius.circular(9),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF280A1E).withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: width * 0.06,
            child: Container(color: Colors.black.withValues(alpha: 0.14)),
          ),
          if (book.fav)
            const Positioned(
              top: 5,
              right: 6,
              child: Icon(Icons.favorite, size: 16, color: Color(0xFFFF6F91)),
            ),
        ],
      ),
    );
  }
}

class DesignedCover extends StatelessWidget {
  final String title, author;
  final double width;
  const DesignedCover({super.key, required this.title, required this.author, required this.width});

  @override
  Widget build(BuildContext context) {
    final p = _palette[_hash(title + author) % _palette.length];
    final variant = _hash(author + title) % 4;
    final bg = p[0], fg = p[1];
    final h = width * 1.5;
    return Container(
      color: bg,
      child: Stack(
        children: [
          if (variant == 0)
            Positioned(
              left: 0,
              right: 0,
              top: h * 0.58,
              height: h * 0.12,
              child: Container(color: fg.withValues(alpha: 0.22)),
            ),
          if (variant == 1)
            Positioned(
              right: -width * 0.18,
              bottom: -width * 0.08,
              child: Container(
                width: width * 0.7,
                height: width * 0.7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: fg.withValues(alpha: 0.2)),
              ),
            ),
          if (variant == 2)
            Positioned.fill(child: CustomPaint(painter: _Stripes(fg.withValues(alpha: 0.16)))),
          if (variant == 3)
            Positioned.fill(
              child: Container(
                margin: EdgeInsets.fromLTRB(width * 0.11, h * 0.05, width * 0.07, h * 0.05),
                decoration: BoxDecoration(
                  border: Border.all(color: fg.withValues(alpha: 0.5), width: 1.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(width * 0.16, h * 0.1, width * 0.1, h * 0.07),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: (width * 0.115).clamp(10, 22).toDouble(),
                    height: 1.1,
                  ),
                ),
                Text(
                  author,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: (width * 0.075).clamp(8, 13).toDouble()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stripes extends CustomPainter {
  final Color color;
  _Stripes(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Stripes old) => old.color != color;
}
