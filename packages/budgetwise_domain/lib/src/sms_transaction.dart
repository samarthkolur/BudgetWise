import 'package:budgetwise_domain/src/money.dart';
import 'package:meta/meta.dart';

/// A candidate expense read off a bank or UPI debit SMS, before a human has
/// confirmed it belongs to any category.
///
/// No payment method: the SMS text is not a reliable signal for it (a "debit
/// card" SMS and a UPI SMS use overlapping wording), and the app only needs
/// the user to make one decision — which category — so it defaults new
/// expenses built from this to UPI and leaves correcting that to the same
/// edit flow every other expense already has.
@immutable
class DetectedTransaction {
  const DetectedTransaction({
    required this.amount,
    required this.occurredOn,
    required this.merchant,
    required this.rawSender,
    required this.rawBody,
  });

  final Money amount;
  final DateTime occurredOn;

  /// Best-effort guess from "at X" / "to X" phrasing. `null` when the SMS
  /// doesn't confidently name one — the review UI always shows [rawBody], so
  /// a missing merchant is never a silently wrong one, just a less
  /// pre-filled one.
  final String? merchant;

  final String rawSender;
  final String rawBody;

  @override
  bool operator ==(Object other) =>
      other is DetectedTransaction &&
      other.amount == amount &&
      other.occurredOn == occurredOn &&
      other.merchant == merchant &&
      other.rawSender == rawSender &&
      other.rawBody == rawBody;

  @override
  int get hashCode =>
      Object.hash(amount, occurredOn, merchant, rawSender, rawBody);
}

/// Turns a raw bank/UPI SMS into a [DetectedTransaction], or returns `null`
/// when the message isn't confidently a debit.
///
/// Heuristic and deliberately conservative: banks do not share a message
/// format, so this recognises common phrasing rather than parsing a grammar.
/// A missed SMS just means one more expense gets entered by hand, same as
/// today; a wrongly-accepted one would silently put a real rupee figure in
/// front of the user to confirm, which is the failure mode worth avoiding —
/// hence the explicit rejects below running before the accept pattern, and
/// requiring a debit keyword rather than inferring one from an amount alone.
abstract final class SmsTransactionParser {
  static final _otpPattern = RegExp(
    r'\b(otp|one[\s-]?time\s*password|verification\s*code)\b',
    caseSensitive: false,
  );

  // Checked before the debit keywords below: "credited" and "debited" can
  // both appear in the same balance-update SMS, and a refund/reversal SMS
  // often echoes the original debit wording ("Rs.500 debited... has been
  // reversed").
  static final _creditPattern = RegExp(
    r'\b(credited|refund(ed)?|reversed|cashback|received)\b',
    caseSensitive: false,
  );

  static final _debitPattern = RegExp(
    r'\b(debited|spent|paid|purchase\s+of|txn\s+of|withdrawn)\b',
    caseSensitive: false,
  );

  // ₹1,234.50 / Rs.1234 / Rs 1,234 / INR 1234.5 — the currency marker must
  // lead so a phone number or reference ID elsewhere in the body isn't
  // mistaken for the amount.
  static final _amountPattern = RegExp(
    r'(?:₹|rs\.?|inr)\s?([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // "at MERCHANT on" / "to MERCHANT on" / "at MERCHANT." / end of string —
  // stops at the next date/reference marker rather than swallowing the rest
  // of the SMS as a merchant name.
  static final _merchantPattern = RegExp(
    r'\b(?:at|to)\s+([A-Za-z0-9][A-Za-z0-9 &.\-]{1,40}?)'
    r'(?=\s+(?:on|via|ref|dated|txn|for|using)\b|[,.]|\s*$)',
    caseSensitive: false,
  );

  static DetectedTransaction? tryParse({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    if (_otpPattern.hasMatch(body)) return null;
    if (_creditPattern.hasMatch(body)) return null;
    if (!_debitPattern.hasMatch(body)) return null;

    final amountMatch = _amountPattern.firstMatch(body);
    if (amountMatch == null) return null;
    final amount = Money.tryParse(amountMatch.group(1)!);
    if (amount == null || !amount.isPositive) return null;

    final merchantMatch = _merchantPattern.firstMatch(body);
    final merchant = merchantMatch?.group(1)?.trim();

    return DetectedTransaction(
      amount: amount,
      occurredOn: receivedAt,
      merchant: (merchant == null || merchant.isEmpty) ? null : merchant,
      rawSender: sender,
      rawBody: body,
    );
  }
}
