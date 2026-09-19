import 'package:drift_flutter/drift_flutter.dart';

import 'database.dart';

AppDatabase createDatabase() {
  return AppDatabase(
    driftDatabase(
      name: 'expense_tracker',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.dart.js'),
      ),
    ),
  );
}