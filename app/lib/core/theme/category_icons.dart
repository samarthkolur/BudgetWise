import 'package:flutter/material.dart';

/// Maps a category key to a single outline icon.
///
/// Presentation-only: the data layer still stores `CategoryTemplate.icon` as
/// the emoji string it always has (unchanged, since that's what the server
/// contract and local schema both persist) — this is a second, purely visual
/// lookup used wherever a category needs a monochrome badge instead. Unknown
/// and custom (`custom:<slug>`) keys fall back to a neutral glyph rather than
/// guessing.
IconData categoryIconFor(String key) => switch (key) {
  'food' => Icons.restaurant_outlined,
  'transport' => Icons.directions_bus_outlined,
  'bills' => Icons.receipt_long_outlined,
  'healthcare' => Icons.medication_outlined,
  'shopping' => Icons.shopping_bag_outlined,
  'entertainment' => Icons.movie_outlined,
  'subscriptions' => Icons.subscriptions_outlined,
  'education' => Icons.school_outlined,
  'misc' => Icons.auto_awesome_outlined,
  _ => Icons.category_outlined,
};
