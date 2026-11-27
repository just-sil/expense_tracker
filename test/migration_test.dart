import 'package:expense_tracker/database/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

void main() {
  test('upgrades a v5 database without losing entries', () async {
    await initTestDatabase();

    // A database as v1.0.2 left it.
    final path = join(await getDatabasesPath(), 'expense_tracker.db');
    final old = await openDatabase(path, version: 5, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE expense_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw_text TEXT NOT NULL,
          screenshot_path TEXT,
          created_at TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          server_id INTEGER,
          error TEXT,
          amount REAL,
          category TEXT,
          expense_date TEXT,
          source TEXT NOT NULL DEFAULT 'manual'
        )''');
      await db.execute(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
      );
    });
    await old.insert('expense_logs', {
      'raw_text': '24 tea',
      'created_at': '2026-11-27T09:00:00',
      'sync_status': 'synced',
      'server_id': 7,
      'amount': 24.0,
      'category': 'Food',
    });
    await old.insert('settings', {'key': 'daily_limit', 'value': '300'});
    await old.close();

    final db = LocalDatabase.instance;
    final rows = await db.getExpenseLogs();
    expect(rows, hasLength(1));
    expect(rows.first['raw_text'], '24 tea');
    expect(rows.first['description'], isNull);
    expect(await db.getSetting('daily_limit'), '300');

    await db.markAsSynced(rows.first['id'] as int, 7,
        amount: 24, category: 'Food', description: 'Tea');
    expect((await db.getExpenseLogs()).first['description'], 'Tea');
  });
}
