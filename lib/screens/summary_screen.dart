import 'package:flutter/material.dart';

/// One expense reduced to what the summary needs.
class _Entry {
  final DateTime day;
  final double amount;
  final String category;
  final bool estimated;

  _Entry({
    required this.day,
    required this.amount,
    required this.category,
    required this.estimated,
  });
}

/// Daily / weekly totals computed entirely on the phone.
///
/// Synced entries use the amount, category and date the
/// server parsed. Unsynced entries fall back to the first
/// number found in the raw text and the date it was saved.
class SummaryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> logs;

  const SummaryScreen({
    super.key,
    required this.logs,
  });

  @override
  State<SummaryScreen> createState() =>
      _SummaryScreenState();
}

enum _Period { daily, weekly }

class _SummaryScreenState
    extends State<SummaryScreen> {
  _Period period = _Period.daily;

  static const int _dayCount = 7;
  static const int _weekCount = 8;

  // --------------------------------------------------
  // PARSING
  // --------------------------------------------------

  static final RegExp _amountPattern = RegExp(
    r'(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?',
  );

  static double? _amountFromText(String text) {
    final match = _amountPattern.firstMatch(text);

    if (match == null) return null;

    return double.tryParse(
      match.group(0)!.replaceAll(',', ''),
    );
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  /// Monday of the week containing [d].
  static DateTime _weekStart(DateTime d) =>
      _dateOnly(d).subtract(
        Duration(days: d.weekday - 1),
      );

  List<_Entry> _entries() {
    final entries = <_Entry>[];

    for (final log in widget.logs) {
      final storedAmount =
          (log['amount'] as num?)?.toDouble();

      final amount = storedAmount ??
          _amountFromText(
            (log['raw_text'] as String?) ?? '',
          );

      if (amount == null) continue;

      final dateText =
          (log['expense_date'] as String?) ??
              (log['created_at'] as String?);

      final date = dateText == null
          ? null
          : DateTime.tryParse(dateText);

      if (date == null) continue;

      entries.add(
        _Entry(
          day: _dateOnly(date),
          amount: amount,
          category:
              (log['category'] as String?) ??
                  'Uncategorised',
          estimated: storedAmount == null,
        ),
      );
    }

    return entries;
  }

  // --------------------------------------------------
  // BUCKETS
  // --------------------------------------------------

  /// Returns (bucketStart, total) pairs, newest first.
  List<MapEntry<DateTime, double>> _buckets(
    List<_Entry> entries,
  ) {
    final now = DateTime.now();

    final starts = period == _Period.daily
        ? List.generate(
            _dayCount,
            (i) => _dateOnly(now)
                .subtract(Duration(days: i)),
          )
        : List.generate(
            _weekCount,
            (i) => _weekStart(now)
                .subtract(Duration(days: 7 * i)),
          );

    final totals = {
      for (final s in starts) s: 0.0,
    };

    for (final e in entries) {
      final key = period == _Period.daily
          ? e.day
          : _weekStart(e.day);

      if (totals.containsKey(key)) {
        totals[key] = totals[key]! + e.amount;
      }
    }

    return starts
        .map((s) => MapEntry(s, totals[s]!))
        .toList();
  }

  List<_Entry> _currentPeriodEntries(
    List<_Entry> entries,
  ) {
    final now = DateTime.now();

    if (period == _Period.daily) {
      final today = _dateOnly(now);
      return entries
          .where((e) => e.day == today)
          .toList();
    }

    final week = _weekStart(now);
    return entries
        .where((e) => _weekStart(e.day) == week)
        .toList();
  }

  // --------------------------------------------------
  // FORMATTING
  // --------------------------------------------------

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  static String _money(double v) =>
      v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(2);

  static String _shortDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]}';

  String _bucketLabel(DateTime start, int index) {
    if (period == _Period.daily) {
      if (index == 0) return 'Today';
      if (index == 1) return 'Yesterday';
      return '${_weekdays[start.weekday - 1]}, '
          '${_shortDate(start)}';
    }

    if (index == 0) return 'This week';
    if (index == 1) return 'Last week';

    final end = start.add(const Duration(days: 6));
    return '${_shortDate(start)} – ${_shortDate(end)}';
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final buckets = _buckets(entries);
    final current = _currentPeriodEntries(entries);

    final currentTotal = current.fold<double>(
      0,
      (sum, e) => sum + e.amount,
    );

    final average = buckets.isEmpty
        ? 0.0
        : buckets.fold<double>(
              0,
              (sum, b) => sum + b.value,
            ) /
            buckets.length;

    final hasEstimates =
        current.any((e) => e.estimated);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<_Period>(
          segments: const [
            ButtonSegment(
              value: _Period.daily,
              label: Text('Daily'),
              icon: Icon(Icons.today),
            ),
            ButtonSegment(
              value: _Period.weekly,
              label: Text('Weekly'),
              icon: Icon(Icons.date_range),
            ),
          ],
          selected: {period},
          onSelectionChanged: (s) {
            setState(() => period = s.first);
          },
        ),

        const SizedBox(height: 16),

        _buildTotalCard(
          currentTotal,
          average,
          current.length,
          hasEstimates,
        ),

        const SizedBox(height: 16),

        _buildCategoryCard(current),

        const SizedBox(height: 24),

        Text(
          period == _Period.daily
              ? 'Last $_dayCount days'
              : 'Last $_weekCount weeks',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        _buildHistory(buckets),
      ],
    );
  }

  Widget _buildTotalCard(
    double total,
    double average,
    int count,
    bool hasEstimates,
  ) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              period == _Period.daily
                  ? 'Spent today'
                  : 'Spent this week',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _money(total),
              style: theme.textTheme.displaySmall
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$count expense(s) · '
              'avg ${_money(average)} per '
              '${period == _Period.daily ? 'day' : 'week'}',
            ),
            if (hasEstimates) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Includes unsynced amounts read '
                      'from your notes. Sync for exact '
                      'figures.',
                      style:
                          theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(List<_Entry> current) {
    if (current.isEmpty) {
      return const SizedBox.shrink();
    }

    final byCategory = <String, double>{};
    for (final e in current) {
      byCategory[e.category] =
          (byCategory[e.category] ?? 0) + e.amount;
    }

    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = sorted.fold<double>(
      0,
      (sum, e) => sum + e.value,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'By category',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            for (final c in sorted)
              _barRow(
                c.key,
                c.value,
                total == 0 ? 0 : c.value / total,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(
    List<MapEntry<DateTime, double>> buckets,
  ) {
    final max = buckets.fold<double>(
      0,
      (m, b) => b.value > m ? b.value : m,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < buckets.length; i++)
              _barRow(
                _bucketLabel(buckets[i].key, i),
                buckets[i].value,
                max == 0 ? 0 : buckets[i].value / max,
              ),
          ],
        ),
      ),
    );
  }

  Widget _barRow(
    String label,
    double value,
    double fraction,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                _money(value),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
