import 'package:flutter/material.dart';

/// Look of each category the laptop can assign.
class CategoryStyle {
  final IconData icon;
  final Color color;

  const CategoryStyle(this.icon, this.color);
}

const _styles = {
  'Food': CategoryStyle(Icons.restaurant, Color(0xFFE67E22)),
  'Transport': CategoryStyle(Icons.directions_car, Color(0xFF2E86C1)),
  'Shopping': CategoryStyle(Icons.shopping_bag, Color(0xFF8E44AD)),
  'Bills': CategoryStyle(Icons.receipt, Color(0xFFC0392B)),
  'Entertainment': CategoryStyle(Icons.movie, Color(0xFFD81B60)),
  'Education': CategoryStyle(Icons.school, Color(0xFF16A085)),
  'Health': CategoryStyle(Icons.favorite, Color(0xFF27AE60)),
  'Other': CategoryStyle(Icons.category, Color(0xFF7F8C8D)),
};

/// Label used for entries the laptop hasn't read yet.
const String notSyncedCategory = 'Not synced yet';

CategoryStyle categoryStyle(String? category) {
  if (category == notSyncedCategory) {
    return const CategoryStyle(Icons.hourglass_empty, Color(0xFF95A5A6));
  }
  return _styles[category] ?? _styles['Other']!;
}

/// Round coloured icon for a category.
class CategoryAvatar extends StatelessWidget {
  final String? category;
  final IconData? overrideIcon;
  final Color? overrideColor;
  final double radius;

  const CategoryAvatar({
    super.key,
    required this.category,
    this.overrideIcon,
    this.overrideColor,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(category);
    final color = overrideColor ?? style.color;

    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.16),
      child: Icon(
        overrideIcon ?? style.icon,
        color: color,
        size: radius,
      ),
    );
  }
}
