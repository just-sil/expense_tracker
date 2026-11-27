import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static final LocalDatabase instance =
      LocalDatabase._internal();

  static Database? _database;

  LocalDatabase._internal();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database =
        await _initDatabase();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath =
        await getDatabasesPath();

    final path = join(
      databasePath,
      'expense_tracker.db',
    );

    return openDatabase(
      path,

      version: 6,

      onCreate:
          (db, version) async {
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
            source TEXT NOT NULL DEFAULT 'manual',
            description TEXT
          )
        ''');

        await _createSettingsTable(db);
      },

      onUpgrade:
          (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE expense_logs '
            'ADD COLUMN screenshot_path TEXT',
          );
        }

        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE expense_logs '
            'ADD COLUMN amount REAL',
          );
          await db.execute(
            'ALTER TABLE expense_logs '
            'ADD COLUMN category TEXT',
          );
          await db.execute(
            'ALTER TABLE expense_logs '
            'ADD COLUMN expense_date TEXT',
          );
        }

        if (oldVersion < 4) {
          await _createSettingsTable(db);
        }

        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE expense_logs '
            "ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
          );
        }

        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE expense_logs '
            'ADD COLUMN description TEXT',
          );
        }
      },
    );
  }

  Future<void> _createSettingsTable(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  // --------------------------------------------------
  // SETTINGS
  // --------------------------------------------------

  Future<String?> getSetting(String key) async {
    final db = await database;

    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );

    return rows.isEmpty
        ? null
        : rows.first['value'] as String?;
  }

  Future<void> setSetting(
    String key,
    String? value,
  ) async {
    final db = await database;

    if (value == null) {
      await db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      return;
    }

    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --------------------------------------------------
  // ADD
  // --------------------------------------------------

  Future<int> addExpenseLog({
    required String rawText,
    String? screenshotPath,
    DateTime? createdAt,
    String source = 'manual',
  }) async {
    final db =
        await database;

    return db.insert(
      'expense_logs',

      {
        'raw_text': rawText,
        'screenshot_path':
            screenshotPath,
        'created_at':
            (createdAt ?? DateTime.now())
                .toIso8601String(),
        'sync_status':
            'pending',
        'source': source,
      },
    );
  }

  // --------------------------------------------------
  // GET ALL
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>>
      getExpenseLogs() async {
    final db =
        await database;

    return db.query(
      'expense_logs',
      orderBy:
          'created_at DESC',
    );
  }

  // --------------------------------------------------
  // GET PENDING
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>>
      getPendingLogs() async {
    final db =
        await database;

    return db.query(
      'expense_logs',

      // Failed entries are retried on every sync.
      where:
          'sync_status IN (?, ?)',

      whereArgs: [
        'pending',
        'failed',
      ],

      orderBy:
          'created_at ASC',
    );
  }

  // --------------------------------------------------
  // MARK SYNCED
  // --------------------------------------------------

  Future<void> markAsSynced(
    int id,
    int serverId, {
    double? amount,
    String? category,
    String? expenseDate,
    String? description,
  }) async {
    final db =
        await database;

    await db.update(
      'expense_logs',

      {
        'sync_status':
            'synced',
        'server_id':
            serverId,
        'error':
            null,
        'amount':
            amount,
        'category':
            category,
        'expense_date':
            expenseDate,
        'description':
            description,
      },

      where:
          'id = ?',

      whereArgs: [
        id,
      ],
    );
  }

  // --------------------------------------------------
  // MARK FAILED
  // --------------------------------------------------

  Future<void> markAsFailed(
    int id,
    String error,
  ) async {
    final db =
        await database;

    await db.update(
      'expense_logs',

      {
        'sync_status':
            'failed',
        'error':
            error,
      },

      where:
          'id = ?',

      whereArgs: [
        id,
      ],
    );
  }

  // --------------------------------------------------
  // REWRITE
  // --------------------------------------------------

  /// Replaces an entry's text and queues it to be parsed
  /// again on the next sync. server_id is kept so the
  /// server updates its existing row.
  Future<void> rewriteExpense(
    int id,
    String rawText,
  ) async {
    final db = await database;

    await db.update(
      'expense_logs',
      {
        'raw_text': rawText,
        'sync_status': 'pending',
        'amount': null,
        'category': null,
        'expense_date': null,
        'description': null,
        'error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --------------------------------------------------
  // RESTORE (undo delete)
  // --------------------------------------------------

  /// Puts back a row exactly as it was, same id included.
  Future<void> restoreExpense(
    Map<String, dynamic> row,
  ) async {
    final db = await database;

    await db.insert(
      'expense_logs',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --------------------------------------------------
  // DELETE
  // --------------------------------------------------

  Future<void> deleteExpense(
    int id,
  ) async {
    final db =
        await database;

    await db.delete(
      'expense_logs',

      where:
          'id = ?',

      whereArgs: [
        id,
      ],
    );
  }
}