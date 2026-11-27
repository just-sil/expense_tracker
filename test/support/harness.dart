import 'dart:io';
import 'dart:ui' as ui;

import 'package:expense_tracker/database/local_database.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Uses an in-process SQLite (no isolate) so database
/// futures complete inside widget tests without runAsync.
Future<void> initTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  // Test files run in parallel processes: give each its
  // own database file.
  final dir = Directory.systemTemp.createTempSync('chillara_test_');
  await databaseFactory.setDatabasesPath(dir.path);
}

/// Empties every table so each test starts clean.
Future<void> clearDatabase() async {
  final db = await LocalDatabase.instance.database;
  await db.delete('expense_logs');
  await db.delete('settings');
}

/// Inserts an expense row. [daysAgo] and [hour] place it in time.
Future<int> seedExpense(
  String rawText, {
  int daysAgo = 0,
  int hour = 12,
  String status = 'synced',
  double? amount,
  String? category,
  String? description,
  String source = 'manual',
  String? error,
}) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysAgo));
  final at = DateTime(day.year, day.month, day.day, hour, 15);

  final db = await LocalDatabase.instance.database;
  final columns = (await db.rawQuery(
    'PRAGMA table_info(expense_logs)',
  ))
      .map((c) => c['name'])
      .toSet();

  return db.insert('expense_logs', {
    'raw_text': rawText,
    'created_at': at.toIso8601String(),
    'sync_status': status,
    'source': source,
    'amount': amount,
    'category': category,
    'expense_date': amount == null
        ? null
        : at.toIso8601String().substring(0, 10),
    'error': error,
    if (columns.contains('description')) 'description': description,
  });
}

/// A realistic week of spending.
Future<void> seedSampleWeek() async {
  await seedExpense('24 tea', hour: 9, amount: 24, category: 'Food', description: 'Tea');
  await seedExpense('auto 60 to office', hour: 10, amount: 60, category: 'Transport', description: 'Auto to office');
  await seedExpense('120 mandi lunch', hour: 14, status: 'pending');
  await seedExpense(
    '[GPay] Paid Rs.349 to Swiggy',
    hour: 20,
    status: 'failed',
    source: 'notification',
    error: 'Exception: Server error 500: model timed out',
  );
  await seedExpense('petrol 500', daysAgo: 1, hour: 8, amount: 500, category: 'Transport', description: 'Petrol');
  await seedExpense('movie tickets 380', daysAgo: 1, hour: 19, amount: 380, category: 'Entertainment', description: 'Movie tickets');
  await seedExpense('electricity bill 1240', daysAgo: 2, amount: 1240, category: 'Bills', description: 'Electricity bill');
  await seedExpense('vegetables 180', daysAgo: 3, amount: 180, category: 'Food', description: 'Vegetables');
  await seedExpense('medicine 95', daysAgo: 4, amount: 95, category: 'Health', description: 'Medicine');
  await seedExpense('shirt 799', daysAgo: 6, amount: 799, category: 'Shopping', description: 'Shirt');
}

Future<void> loadRealFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter'}'
      '/bin/cache/artifacts/material_fonts';

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Sets a phone-sized window (360x780 dp).
void usePhoneSize(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Writes build/screenshots/[name].png of the whole app.
Future<void> screenshot(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final size = tester.view.physicalSize;

  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & size,
      pixelRatio: 0.5,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screenshots/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}
