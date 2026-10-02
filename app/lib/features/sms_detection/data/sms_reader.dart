import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

/// One SMS inbox message, trimmed to the fields the parser and the dedup
/// check need.
class RawSmsMessage {
  const RawSmsMessage({
    required this.dedupKey,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  /// The Android SMS content provider's own row id, as a string. Using the
  /// system's id rather than hashing the message ourselves matters because
  /// Dart's default string hashing is seed-randomised per process — the same
  /// SMS would hash differently after every app restart and defeat the
  /// `UNIQUE` constraint this is stored under.
  final String dedupKey;

  final String sender;
  final String body;
  final DateTime receivedAt;
}

/// Reads the device's SMS inbox since a given instant. A function type
/// rather than a one-method abstract class, so tests can pass a plain
/// closure instead of a fake implementation.
typedef SmsReader = Future<List<RawSmsMessage>> Function(DateTime since);

/// The real, on-device reader, torn off as an [SmsReader] where it's wired up
/// (see `detectedExpenseRepositoryProvider` and friends in `core/providers.dart`).
///
/// `flutter_sms_inbox` has no server-side "since" filter, so this fetches the
/// most recent window and filters client-side — the same tradeoff the plugin
/// itself makes (`SmsQuery` caps a single query at 1000 messages). 500 is
/// comfortably more than a normal inbox accumulates between app opens.
Future<List<RawSmsMessage>> fetchDeviceSmsSince(DateTime since) async {
  final messages = await SmsQuery().querySms(count: 500, sort: true);

  return [
    for (final message in messages)
      if (message.id != null &&
          message.date != null &&
          message.date!.isAfter(since) &&
          message.body != null &&
          message.address != null)
        RawSmsMessage(
          dedupKey: message.id!.toString(),
          sender: message.address!,
          body: message.body!,
          receivedAt: message.date!,
        ),
  ];
}
