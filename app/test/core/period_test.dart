import 'package:budgetwise/core/time/period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Period normalisation', () {
    test('renders the first of the month for the date column', () {
      expect(Period(2026, 8).isoDate, '2026-08-01');
      expect(
        Period.fromDate(DateTime(2026, 8, 31, 23, 59)).isoDate,
        '2026-08-01',
      );
    });

    test('rolls month overflow into the year', () {
      expect(Period(2026, 13), Period(2027, 1));
      expect(Period(2026, 0), Period(2025, 12));
      expect(Period(2026, 25), Period(2028, 1));
    });

    test('parses what Postgres returns', () {
      expect(Period.parse('2026-08-01'), Period(2026, 8));
      expect(Period.parse('2026-08-15'), Period(2026, 8));
    });
  });

  group('Period boundaries', () {
    test('knows month lengths including leap years', () {
      expect(Period(2026, 2).totalDays, 28);
      expect(Period(2024, 2).totalDays, 29);
      expect(Period(2026, 8).totalDays, 31);
      expect(Period(2026, 4).totalDays, 30);
    });

    test(
      'lastDay is the final instant, so an 11pm expense still lands inside',
      () {
        final august = Period(2026, 8);
        expect(august.contains(DateTime(2026, 8, 31, 23)), isTrue);
        expect(august.contains(DateTime(2026, 9)), isFalse);
        expect(august.lastDay.day, 31);
      },
    );
  });

  group('Period.daysRemaining', () {
    test(
      'includes today — a user checking at 9am still gets to spend today',
      () {
        final august = Period(2026, 8);
        expect(august.daysRemaining(now: DateTime(2026, 8, 31, 9)), 1);
        expect(august.daysRemaining(now: DateTime(2026, 8)), 31);
        expect(august.daysRemaining(now: DateTime(2026, 8, 15)), 17);
      },
    );

    test('a past month has nothing left, a future month has all of it', () {
      expect(Period(2026, 7).daysRemaining(now: DateTime(2026, 8, 15)), 0);
      expect(Period(2026, 9).daysRemaining(now: DateTime(2026, 8, 15)), 30);
    });

    test('elapsed and remaining always account for the whole month', () {
      final august = Period(2026, 8);
      final now = DateTime(2026, 8, 15);
      expect(august.daysRemaining(now: now) + august.daysElapsed(now: now), 31);
    });
  });

  group('Period navigation', () {
    test('steps across year boundaries', () {
      expect(Period(2026, 12).next, Period(2027, 1));
      expect(Period(2026, 1).previous, Period(2025, 12));
    });

    test('orders and measures distance', () {
      expect(Period(2026, 7).isBefore(Period(2026, 8)), isTrue);
      expect(Period(2027, 1).isAfter(Period(2026, 12)), isTrue);
      expect(Period(2026, 1).monthsUntil(Period(2027, 1)), 12);
      expect(Period(2026, 8).monthsUntil(Period(2026, 5)), -3);
    });

    test('labels for the month switcher', () {
      expect(Period(2026, 8).label, 'August 2026');
      expect(Period(2026, 8).shortLabel, 'Aug 2026');
    });
  });
}
