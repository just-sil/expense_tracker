import 'package:expense_tracker/database/local_database.dart';
import 'package:expense_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Future<void> _openApp(WidgetTester tester) async {
  await tester.pumpWidget(const ExpenseApp());
  await tester.pumpAndSettle();
}

Future<int> _rowCount() async {
  final db = await LocalDatabase.instance.database;
  return (await db.query('expense_logs')).length;
}

void main() {
  setUpAll(initTestDatabase);
  setUp(clearDatabase);

  testWidgets('save an expense, then undo it', (tester) async {
    usePhoneSize(tester);
    await _openApp(tester);
    expect(find.text('No expenses yet'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '24 tea');
    await tester.pump();
    expect(find.textContaining('₹24 · category and date'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(await _rowCount(), 1);
    expect(find.text('24 tea'), findsWidgets);
    expect(find.text('~₹24'), findsNWidgets(2)); // row + day total
    expect(find.text('Saved ₹24'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await _rowCount(), 0);
    expect(find.text('No expenses yet'), findsOneWidget);
  });

  testWidgets('warns when there is no amount', (tester) async {
    usePhoneSize(tester);
    await _openApp(tester);
    await tester.enterText(find.byType(TextField), 'lunch');
    await tester.pump();
    expect(find.textContaining('Add an amount'), findsOneWidget);
  });

  testWidgets('empty input does not save', (tester) async {
    usePhoneSize(tester);
    await _openApp(tester);
    await tester.tap(find.byTooltip('Save'));
    await tester.pump();
    expect(find.text('Type an expense, like 24 tea'), findsOneWidget);
    expect(await _rowCount(), 0);
  });

  testWidgets('swipe to delete, then undo', (tester) async {
    usePhoneSize(tester);
    await seedExpense('petrol 500', amount: 500, category: 'Transport', description: 'Petrol');
    await _openApp(tester);

    await tester.drag(find.text('Petrol'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Petrol'), findsNothing);
    expect(await _rowCount(), 0);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Petrol'), findsOneWidget);
    expect(await _rowCount(), 1);
  });

  testWidgets('delete from the details sheet', (tester) async {
    usePhoneSize(tester);
    await seedExpense('shirt 799', amount: 799, category: 'Shopping', description: 'Shirt');
    await _openApp(tester);

    await tester.tap(find.text('Shirt'));
    await tester.pumpAndSettle();
    expect(find.text('Shopping'), findsWidgets);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await _rowCount(), 0);
  });

  testWidgets('quick-add chip logs a frequent entry again', (tester) async {
    usePhoneSize(tester);
    await seedExpense('24 tea', daysAgo: 1, amount: 24, category: 'Food', description: 'Tea');
    await seedExpense('24 tea', daysAgo: 2, amount: 24, category: 'Food', description: 'Tea');
    await _openApp(tester);

    await tester.tap(find.widgetWithText(ActionChip, '24 tea'));
    await tester.pumpAndSettle();
    expect(await _rowCount(), 3);
    expect(find.text('Saved ₹24'), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    usePhoneSize(tester);
    await seedSampleWeek();
    await _openApp(tester);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'transport');
    await tester.pumpAndSettle();

    expect(find.text('2 matches · ₹560'), findsOneWidget);
    expect(find.text('Petrol'), findsOneWidget);
    expect(find.text('Tea'), findsNothing);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsOneWidget);
  });

  testWidgets('monthly average ignores months before the first expense',
      (tester) async {
    usePhoneSize(tester);
    await seedExpense('shirt 799', amount: 799, category: 'Shopping', description: 'Shirt');
    await _openApp(tester);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('1 expense · avg ₹799 per month'), findsOneWidget);
  });

  testWidgets('daily limit set from settings shows on summary', (tester) async {
    usePhoneSize(tester);
    await _openApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily limit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '300');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('₹300 a day · ₹2,100 a week'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.text('You can spend today'), findsOneWidget);
  });
}
