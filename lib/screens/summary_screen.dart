import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/local_database.dart';

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

  /// Daily spending limit; null when not set.
  double? dailyLimit;

  static const String _limitKey = 'daily_limit';

  @override
  void initState() {
    super.initState();
    _loadLimit();
  }

  Future<void> _loadLimit() async {
    final value =
        await LocalDatabase.instance.getSetting(_limitKey);

    if (!mounted) return;

    setState(() {
      dailyLimit =
          value == null ? null : double.tryParse(value);
    });
  }

  Future<void> _editLimit() async {
    final controller = TextEditingController(
      text: dailyLimit == null ? '' : _money(dailyLimit!),
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily limit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'[0-9.]'),
            ),
          ],
          decoration: const InputDecoration(
            hintText: 'e.g. 300',
            helperText:
                'Unspent money rolls over to the next '
                'day. Resets every Monday.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          if (dailyLimit != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, ''),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text.trim(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Not disposed here: the dialog's closing animation
    // still renders the TextField. It is garbage-collected.

    if (result == null) return; // cancelled

    final parsed = double.tryParse(result);
    final newLimit =
        parsed != null && parsed > 0 ? parsed : null;

    if (result.isNotEmpty && newLimit == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an amount above 0'),
        ),
      );
      return;
    }

    await LocalDatabase.instance.setSetting(
      _limitKey,
      newLimit?.toString(),
    );

    if (!mounted) return;
    setState(() => dailyLimit = newLimit);
  }

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
        _buildLimitCard(entries),

        const SizedBox(height: 16),

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

  // --------------------------------------------------
  // DAILY LIMIT
  // --------------------------------------------------

  Widget _buildLimitCard(List<_Entry> entries) {
    final theme = Theme.of(context);
    final limit = dailyLimit;

    if (limit == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Set a daily limit'),
          subtitle: const Text(
            'See how much you can spend each day',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editLimit,
        ),
      );
    }

    final today = _dateOnly(DateTime.now());
    final weekStart = _weekStart(today);

    // Monday = 1 ... Sunday = 7
    final daysSoFar = today.weekday;
    final daysLeft = 8 - daysSoFar; // including today

    double spentBeforeToday = 0;
    double spentToday = 0;

    for (final e in entries) {
      if (e.day.isBefore(weekStart) ||
          e.day.isAfter(today)) {
        continue;
      }

      if (e.day == today) {
        spentToday += e.amount;
      } else {
        spentBeforeToday += e.amount;
      }
    }

    final spentWeek = spentBeforeToday + spentToday;
    final weekBudget = limit * 7;

    // Allowance for today, carrying over Mon..yesterday.
    final canSpendToday = limit * daysSoFar - spentWeek;
    final weekRemaining = weekBudget - spentWeek;

    // Even split of what's left over the remaining days.
    final perDayRest = (weekBudget - spentBeforeToday) /
        daysLeft;

    final over = canSpendToday < 0;
    final hasEstimates = entries.any(
      (e) =>
          e.estimated &&
          !e.day.isBefore(weekStart) &&
          !e.day.isAfter(today),
    );

    final colors = theme.colorScheme;

    return Card(
      color: over
          ? colors.errorContainer
          : colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    over
                        ? 'Over today\'s allowance by'
                        : 'You can spend today',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit daily limit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _editLimit,
                ),
              ],
            ),
            Text(
              _money(canSpendToday.abs()),
              style: theme.textTheme.displaySmall
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Limit ${_money(limit)}/day · '
              'spent ${_money(spentToday)} today',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'This week: ${_money(spentWeek)} '
                    'of ${_money(weekBudget)}',
                  ),
                ),
                Text(
                  weekRemaining >= 0
                      ? '${_money(weekRemaining)} left'
                      : '${_money(-weekRemaining)} over',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (spentWeek / weekBudget)
                    .clamp(0.0, 1.0),
                minHeight: 8,
                color: over ? colors.error : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              daysLeft == 1
                  ? 'Last day of the week · resets tonight'
                  : perDayRest >= 0
                      ? 'About ${_money(perDayRest)}/day '
                          'for the $daysLeft days left '
                          '(incl. today)'
                      : 'Weekly budget already used up',
              style: theme.textTheme.bodySmall,
            ),
            if (hasEstimates) ...[
              const SizedBox(height: 4),
              Text(
                'Includes unsynced amounts read from '
                'your notes.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
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
