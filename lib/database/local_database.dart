import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._internal();

  static Database? _database;

  LocalDatabase._internal();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();

    final path = join(
      databasePath,
      'expense_tracker.db',
    );

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE expense_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            raw_text TEXT NOT NULL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            server_id INTEGER,
            error TEXT
          )
        ''');
      },
    );
  }

  Future<int> addExpenseLog(String rawText) async {
    final db = await database;

    return db.insert(
      'expense_logs',
      {
        'raw_text': rawText,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'pending',
      },
    );
  }

  Future<List<Map<String, dynamic>>> getExpenseLogs() async {
    final db = await database;

    return db.query(
      'expense_logs',
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingLogs() async {
    final db = await database;

    return db.query(
      'expense_logs',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markAsSynced(
    int id,
    int serverId,
  ) async {
    final db = await database;

    await db.update(
      'expense_logs',
      {
        'sync_status': 'synced',
        'server_id': serverId,
        'error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAsFailed(
    int id,
    String error,
  ) async {
    final db = await database;

    await db.update(
      'expense_logs',
      {
        'sync_status': 'failed',
        'error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}