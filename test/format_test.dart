import 'package:expense_tracker/models/expense_entry.dart';
import 'package:expense_tracker/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('groups digits the Indian way', () {
      expect(formatMoney(24), '₹24');
      expect(formatMoney(1240), '₹1,240');
      expect(formatMoney(123456), '₹1,23,456');
      expect(formatMoney(12345678), '₹1,23,45,678');
    });

    test('keeps paise only when present', () {
      expect(formatMoney(24.5), '₹24.50');
      expect(formatMoney(589.6, wholeOnly: true), '₹590');
    });

    test('negative amounts', () {
      expect(formatMoney(-1500), '-₹1,500');
    });
  });

  group('amountFromText', () {
    test('first number in plain notes', () {
      expect(amountFromText('24 tea'), 24);
      expect(amountFromText('spent 150 on lunch yesterday'), 150);
      expect(amountFromText('Tea24'), 24);
      expect(amountFromText('bill 1,240.50'), 1240.5);
    });

    test('prefers the amount after Rs / ₹ / INR', () {
      expect(amountFromText('A/c XX1234 debited Rs.500 on 27-11'), 500);
      expect(amountFromText('Paid ₹ 349 to Swiggy'), 349);
      expect(amountFromText('INR 1,05,000 debited from a/c 9876'), 105000);
    });

    test('null without a number', () {
      expect(amountFromText('lunch'), isNull);
    });
  });

  test('plural', () {
    expect(plural(1, 'expense'), '1 expense');
    expect(plural(3, 'expense'), '3 expenses');
    expect(plural(2, 'entry', 'entries'), '2 entries');
  });

  test('dayLabel', () {
    final now = DateTime(2026, 11, 27, 10);
    expect(dayLabel(DateTime(2026, 11, 27, 8), now: now), 'Today');
    expect(dayLabel(DateTime(2026, 11, 26, 23), now: now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 11, 23), now: now), 'Mon, 23 Nov');
    expect(dayLabel(DateTime(2025, 12, 31), now: now), 'Wed, 31 Dec 2025');
  });

  test('timeLabel', () {
    expect(timeLabel(DateTime(2026, 1, 1, 0, 5)), '12:05 am');
    expect(timeLabel(DateTime(2026, 1, 1, 12, 0)), '12:00 pm');
    expect(timeLabel(DateTime(2026, 1, 1, 21, 30)), '9:30 pm');
  });

  group('ExpenseEntry', () {
    test('unsynced entry estimates from text', () {
      final e = ExpenseEntry({
        'id': 1,
        'raw_text': '120 mandi',
        'created_at': '2026-11-27T14:00:00',
        'sync_status': 'pending',
      });
      expect(e.amount, 120);
      expect(e.isEstimated, isTrue);
      expect(e.category, 'Not synced yet');
      expect(e.title, '120 mandi');
    });

    test('synced entry uses parsed values and date', () {
      final e = ExpenseEntry({
        'id': 2,
        'raw_text': '120 mandi yesterday',
        'created_at': '2026-11-27T14:00:00',
        'sync_status': 'synced',
        'amount': 120.0,
        'category': 'Food',
        'expense_date': '2026-11-26',
        'description': 'Mandi',
      });
      expect(e.isEstimated, isFalse);
      expect(e.category, 'Food');
      expect(e.title, 'Mandi');
      expect(e.day, DateTime(2026, 11, 26));
    });

    test('notification entry splits off the app name', () {
      final e = ExpenseEntry({
        'id': 3,
        'raw_text': '[GPay] Paid Rs.349 to Swiggy',
        'created_at': '2026-11-27T20:00:00',
        'sync_status': 'pending',
        'source': 'notification',
      });
      expect(e.sourceApp, 'GPay');
      expect(e.title, 'Paid Rs.349 to Swiggy');
      expect(e.amount, 349);
    });
  });
}
