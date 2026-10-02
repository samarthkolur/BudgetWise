/// Money, periods and budget arithmetic — the rules the product is about.
///
/// Shared by the Flutter app and the API server on purpose. Both sides derive
/// savings targets, spendable income and the health score from the same
/// functions, so they cannot drift — a plan the app built correctly can never
/// be rejected by the server doing the same arithmetic differently.
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
export 'src/sms_transaction.dart';
