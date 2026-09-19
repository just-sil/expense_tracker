import 'package:drift/drift.dart';

part 'database.g.dart';

class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();

  RealColumn get amount => real()();

  TextColumn get category => text()();

  TextColumn get description => text().nullable()();

  TextColumn get date => text()();

  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [Expenses])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  Future<int> addExpense({
    required double amount,
    required String category,
    String? description,
    required String date,
  }) {
    return into(expenses).insert(
      ExpensesCompanion.insert(
        amount: amount,
        category: category,
        description: Value(description),
        date: date,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<List<Expense>> getAllExpenses() {
    return select(expenses).get();
  }

  Future<double> getTotalExpenses() async {
    final all = await select(expenses).get();

    return all.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );
  }
}