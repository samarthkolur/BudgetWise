/// Money, periods and budget arithmetic — the rules the product is about.
///
/// Shared by the Flutter app and the API server on purpose. The server
/// validates that a month's category allocations sum exactly to spendable
/// income; the client computes that split. If the two used separate
/// implementations they would drift, and the failure would look like the server
/// rejecting a plan the user watched the app build correctly.
///
/// Pure Dart. No Flutter, no database, no I/O — which is what lets the whole
/// thing be tested in milliseconds and run identically on both sides.
library;

export 'src/allocation.dart';
export 'src/budget_math.dart';
export 'src/health_score.dart';
export 'src/investing_unlock.dart';
export 'src/money.dart';
export 'src/period.dart';
