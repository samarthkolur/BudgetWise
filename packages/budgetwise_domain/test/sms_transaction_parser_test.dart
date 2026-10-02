import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:test/test.dart';

void main() {
  final receivedAt = DateTime(2026, 1, 12, 14, 30);

  group('debit SMS is parsed', () {
    test('HDFC-style "Rs.X debited ... at MERCHANT."', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'HDFCBK',
        body:
            'Rs.499.00 debited from a/c XX1234 on 12-01-26 at AMAZON PAY. '
            'Avl bal Rs.15,230.00',
        receivedAt: receivedAt,
      );

      expect(result, isNotNull);
      expect(result!.amount, const Money(49900));
      expect(result.merchant, 'AMAZON PAY');
      expect(result.occurredOn, receivedAt);
    });

    test('ICICI-style debit with a comma-grouped amount and no "at/to"', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'ICICIB',
        body:
            'ICICI Bank Acct XX567 debited for Rs 1,499.00 on 14-Jan-26; '
            'Info: UPI-PAYTM-MERCHANT. Avl Bal: Rs 22,150.75',
        receivedAt: receivedAt,
      );

      expect(result, isNotNull);
      expect(result!.amount, const Money(149900));
      expect(result.merchant, isNull);
    });

    test('generic UPI "paid ... to NAME using UPI"', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'VM-UPIPAY',
        body: 'You have paid Rs.150 to Rahul Sharma using UPI. '
            'UPI Ref No 123456789012.',
        receivedAt: receivedAt,
      );

      expect(result, isNotNull);
      expect(result!.amount, const Money(15000));
      expect(result.merchant, 'Rahul Sharma');
    });

    test('INR-denominated amount with no decimals or commas', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'SBIINB',
        body: 'INR 75 debited towards Uber ride at UBER INDIA on 01-02-26',
        receivedAt: receivedAt,
      );

      expect(result, isNotNull);
      expect(result!.amount, const Money(7500));
      expect(result.merchant, 'UBER INDIA');
    });

    test('carries the raw sender and body through untouched', () {
      const body = 'Rs.99 spent at CHAIWALA on 12-01-26';
      final result = SmsTransactionParser.tryParse(
        sender: 'AX-SBIINB',
        body: body,
        receivedAt: receivedAt,
      );

      expect(result!.rawSender, 'AX-SBIINB');
      expect(result.rawBody, body);
    });
  });

  group('non-debit SMS is rejected', () {
    test('OTP message, even one that mentions an amount and "txn of"', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'AX-SBIINB',
        body: '123456 is your OTP for txn of Rs.5000 at AMAZON. '
            'Do not share it with anyone.',
        receivedAt: receivedAt,
      );

      expect(result, isNull);
    });

    test('credit SMS', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'HDFCBK',
        body: 'Rs.299.00 credited to your a/c XX1234 on 12-01-26. '
            'Avl bal Rs.15,729.00',
        receivedAt: receivedAt,
      );

      expect(result, isNull);
    });

    test('refund/reversal SMS that also contains "debited"', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'HDFCBK',
        body: 'Rs.500.00 debited from A/c XX1234 towards order have been '
            'reversed. Refund Rs.500 credited.',
        receivedAt: receivedAt,
      );

      expect(result, isNull);
    });

    test('promotional SMS mentioning cashback', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'AD-BIGBZR',
        body: 'Get 10% cashback on your next purchase at BigBazaar! '
            'T&C apply.',
        receivedAt: receivedAt,
      );

      expect(result, isNull);
    });

    test('promotional SMS with no debit keyword at all', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'AD-FLPKRT',
        body: 'Flat 50% off on Big Billion Days! Shop now at Flipkart.',
        receivedAt: receivedAt,
      );

      expect(result, isNull);
    });

    test('debit keyword present but no parseable amount', () {
      final result = SmsTransactionParser.tryParse(
        sender: 'HDFCBK',
        body: 'Your account was debited. Contact support for details.',
        receivedAt: receivedAt,
      );

      expect(result, isNull);
    });
  });
}
