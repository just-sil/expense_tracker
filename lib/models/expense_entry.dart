import '../util/categories.dart';
import '../util/format.dart';

/// Read-only view over an `expense_logs` row.
///
/// Synced entries use what the laptop parsed. Unsynced ones
/// fall back to an amount estimated from the text and the
/// time they were saved.
class ExpenseEntry {
  final Map<String, dynamic> row;

  ExpenseEntry(this.row);

  int get id => row['id'] as int;

  String get rawText => (row['raw_text'] as String?) ?? '';

  String? get screenshotPath => row['screenshot_path'] as String?;

  String get status => (row['sync_status'] as String?) ?? 'pending';

  bool get isSynced => status == 'synced';
  bool get isFailed => status == 'failed';
  bool get isPending => !isSynced;

  bool get fromNotification => row['source'] == 'notification';

  String? get error => row['error'] as String?;

  /// Laptop's short description, e.g. "Tea".
  String? get description {
    final d = (row['description'] as String?)?.trim();
    return d == null || d.isEmpty ? null : d;
  }

  double? get parsedAmount => (row['amount'] as num?)?.toDouble();

  /// Parsed amount, or a guess from the text.
  double? get amount => parsedAmount ?? amountFromText(rawText);

  /// True when [amount] is only a guess from the text.
  bool get isEstimated => parsedAmount == null;

  String get category => isEstimated
      ? notSyncedCategory
      : ((row['category'] as String?) ?? 'Other');

  DateTime get createdAt =>
      DateTime.tryParse((row['created_at'] as String?) ?? '') ??
      DateTime.now();

  /// When the money was spent: the parsed date (with the save
  /// time of day, for ordering) or the save time.
  DateTime get spentAt {
    final parsed = DateTime.tryParse((row['expense_date'] as String?) ?? '');
    if (parsed == null) return createdAt;
    final c = createdAt;
    return DateTime(parsed.year, parsed.month, parsed.day, c.hour, c.minute, c.second);
  }

  DateTime get day => dateOnly(spentAt);

  static final RegExp _appPrefix = RegExp(r'^\[([^\]]{1,40})\]\s*');

  /// App that posted a notification entry ("GPay"), taken
  /// from the "[GPay] ..." prefix the listener adds.
  String? get sourceApp => fromNotification
      ? _appPrefix.firstMatch(rawText)?.group(1)
      : null;

  /// Raw text without the "[App] " prefix.
  String get textWithoutApp => rawText.replaceFirst(_appPrefix, '');

  /// Best one-line title.
  String get title {
    if (description != null) return description!;
    if (rawText.isNotEmpty) return textWithoutApp;
    return 'Screenshot expense';
  }

  /// Friendly reason a sync failed.
  String get friendlyError {
    final e = (error ?? '').replaceFirst('Exception: ', '');
    if (e.isEmpty) return 'The laptop couldn\'t read this entry.';
    if (e.contains('timed out') || e.contains('Timeout')) {
      return 'The laptop took too long to read this entry. It will be retried on the next sync.';
    }
    if (e.contains('raw_text is required')) {
      return 'Nothing to read: add what it was for and the amount, like "120 lunch".';
    }
    if (e.contains('amount')) {
      return 'No amount found. Edit it to include a number, like "120 lunch".';
    }
    return e;
  }

  static List<ExpenseEntry> fromRows(List<Map<String, dynamic>> rows) =>
      rows.map(ExpenseEntry.new).toList();
}
