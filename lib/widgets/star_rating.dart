import 'package:flutter/material.dart';

import '../theme.dart';

/// Read-only stars, supports halves.
class Stars extends StatelessWidget {
  final double rating;
  final double size;
  const Stars({super.key, required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final v = rating - i;
        final icon = v >= 1
            ? Icons.star_rounded
            : v >= 0.5
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded;
        return Icon(icon, size: size, color: v > 0 ? AppColors.gold : AppColors.line);
      }),
    );
  }
}

/// Tappable rating. Tap the left half of a star for a half rating.
/// Tapping the current value again clears it.
class StarPicker extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final bool enabled;
  const StarPicker({super.key, required this.rating, required this.onChanged, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final star = i + 1;
        final v = rating - i;
        final icon = v >= 1
            ? Icons.star_rounded
            : v >= 0.5
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded;
        return Semantics(
          button: true,
          label: 'Rate $star stars',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: !enabled
                ? null
                : (d) {
                    final half = d.localPosition.dx < size / 2;
                    var nv = half ? star - 0.5 : star.toDouble();
                    if (nv == rating) nv = 0;
                    onChanged(nv);
                  },
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size, color: v > 0 ? AppColors.gold : AppColors.line),
            ),
          ),
        );
      }),
    );
  }
}
