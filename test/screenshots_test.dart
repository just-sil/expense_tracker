// Renders the main screens to build/screenshots/ for visual review.
// Run: flutter test test/screenshots_test.dart
import 'package:expense_tracker/database/local_database.dart';
import 'package:expense_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Future<void> _openApp(WidgetTester tester) async {
  await tester.pumpWidget(const ExpenseApp());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initTestDatabase();
    await loadRealFonts();
  });

  setUp(clearDatabase);

  testWidgets('expenses tab', (tester) async {
    usePhoneSize(tester);
    await seedSampleWeek();
    await _openApp(tester);
    await screenshot(tester, 'expenses');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await screenshot(tester, 'expenses-scrolled');
  });

  testWidgets('typing and details', (tester) async {
    usePhoneSize(tester);
    await seedSampleWeek();
    await _openApp(tester);

    await tester.enterText(find.byType(TextField), '120 mandi');
    await tester.pumpAndSettle();
    await screenshot(tester, 'typing');

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Swiggy').first);
    await tester.pumpAndSettle();
    await screenshot(tester, 'details-failed');
  });

  testWidgets('summary tab', (tester) async {
    usePhoneSize(tester);
    await seedSampleWeek();
    await LocalDatabase.instance.setSetting('daily_limit', '400');
    await LocalDatabase.instance.setSetting('day_range', 'weekdays');
    await _openApp(tester);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'summary');

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await screenshot(tester, 'summary-scrolled');

    await tester.tap(find.text('Yesterday').last);
    await tester.pumpAndSettle();
    await screenshot(tester, 'summary-drilldown');
  });

  testWidgets('summary monthly', (tester) async {
    usePhoneSize(tester);
    await seedSampleWeek();
    await _openApp(tester);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'summary-monthly');
  });

  testWidgets('settings', (tester) async {
    usePhoneSize(tester);
    await LocalDatabase.instance.setSetting('daily_limit', '400');
    await _openApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'settings');
  });

  testWidgets('empty state', (tester) async {
    usePhoneSize(tester);
    await _openApp(tester);
    await screenshot(tester, 'empty');
  });

  testWidgets('dark mode', (tester) async {
    usePhoneSize(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await seedSampleWeek();
    await LocalDatabase.instance.setSetting('daily_limit', '400');
    await _openApp(tester);
    await screenshot(tester, 'dark-expenses');
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'dark-summary');
  });

  testWidgets('search', (tester) async {
    usePhoneSize(tester);
    await seedSampleWeek();
    await _openApp(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'food');
    await tester.pumpAndSettle();
    await screenshot(tester, 'search');
  });

  testWidgets('small phone, large text', (tester) async {
    usePhoneSize(tester, width: 320);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await seedSampleWeek();
    await LocalDatabase.instance.setSetting('daily_limit', '400');
    await _openApp(tester);
    await screenshot(tester, 'small-expenses');
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'small-summary');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await screenshot(tester, 'small-summary-scrolled');
  });
}
