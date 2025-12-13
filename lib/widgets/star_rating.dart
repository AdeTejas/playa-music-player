// lib/widgets/star_rating.dart
import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int rating;
  final int maxRating;
  final double size;
  final ValueChanged<int>? onRatingChanged;

  const StarRating({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.size = 24.0,
    this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxRating, (index) {
        final starIndex = index + 1;
        return GestureDetector(
          onTap:
              onRatingChanged != null
                  ? () => onRatingChanged!(starIndex)
                  : null,
          child: Icon(
            starIndex <= rating ? Icons.star : Icons.star_border,
            size: size,
            color: starIndex <= rating ? Colors.amber : Colors.grey,
          ),
        );
      }),
    );
  }
}
