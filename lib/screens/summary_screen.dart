import 'package:flutter/material.dart';

import '../database/local_database.dart';
import '../models/expense_entry.dart';
import '../state/app_settings.dart';
import '../util/categories.dart';
import '../util/format.dart';
import '../widgets/expense_tile.dart';

/// Daily / weekly / monthly totals computed entirely on the
/// phone. Unsynced entries count with the amount estimated
/// from their text.
class SummaryScreen extends StatefulWidget {
  final List<ExpenseEntry> entries;

  /// Opens an expense's details (edit / delete).
  final void Function(ExpenseEntry entry) onEntryTap;

  const SummaryScreen({
    super.key,
    required this.entries,
    required this.onEntryTap,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

enum _Period { daily, weekly, monthly }

/// Which days the daily history lists.
enum _DayRange { last7, thisWeek, weekdays }

/// One row of the history: a day, week or month.
class _Bucket {
  final DateTime start;
  final DateTime end; // exclusive
  final List<ExpenseEntry> entries;

  _Bucket(this.start, this.end, this.entries);

  double get total => entries.fold(0, (s, e) => s + (e.amount ?? 0));

  bool get hasEstimates => entries.any((e) => e.isEstimated);
}

class _SummaryScreenState extends State<SummaryScreen> {
  _Period period = _Period.daily;
  _DayRange dayRange = _DayRange.last7;

  static const String _dayRangeKey = 'day_range';
  static const int _dayCount = 7;
  static const int _weekCount = 8;
  static const int _monthCount = 6;

  @override
  void initState() {
    super.initState();
    _loadDayRange();
  }

  Future<void> _loadDayRange() async {
    final value = await LocalDatabase.instance.getSetting(_dayRangeKey);
    if (!mounted) return;
    setState(() {
      dayRange = _DayRange.values.firstWhere(
        (r) => r.name == value,
        orElse: () => _DayRange.last7,
      );
    });
  }

  void _setDayRange(_DayRange range) {
    setState(() => dayRange = range);
    LocalDatabase.instance.setSetting(_dayRangeKey, range.name);
  }

  /// Entries that have an amount (parsed or estimated).
  List<ExpenseEntry> get _counted =>
      widget.entries.where((e) => e.amount != null).toList();

  // --------------------------------------------------
  // BUCKETS
  // --------------------------------------------------

  List<DateTime> _starts(DateTime now) {
    final today = dateOnly(now);
    switch (period) {
      case _Period.daily:
        switch (dayRange) {
          case _DayRange.last7:
            return List.generate(
              _dayCount,
              (i) => today.subtract(Duration(days: i)),
            );
          case _DayRange.thisWeek:
          case _DayRange.weekdays:
            final n = dayRange == _DayRange.thisWeek ? 7 : 5;
            return List.generate(
              n,
              (i) => weekStart(now).add(Duration(days: i)),
            ).where((d) => !d.isAfter(today)).toList().reversed.toList();
        }
      case _Period.weekly:
        return List.generate(
          _weekCount,
          (i) => weekStart(now).subtract(Duration(days: 7 * i)),
        );
      case _Period.monthly:
        return List.generate(
          _monthCount,
          (i) => DateTime(now.year, now.month - i),
        );
    }
  }

  DateTime _endOf(DateTime start) => switch (period) {
        _Period.daily => start.add(const Duration(days: 1)),
        _Period.weekly => start.add(const Duration(days: 7)),
        _Period.monthly => DateTime(start.year, start.month + 1),
      };

  /// Newest first.
  List<_Bucket> _buckets(List<ExpenseEntry> entries) {
    return _starts(DateTime.now()).map((start) {
      final end = _endOf(start);
      return _Bucket(
        start,
        end,
        entries
            .where((e) => !e.day.isBefore(start) && e.day.isBefore(end))
            .toList()
          ..sort((a, b) => b.spentAt.compareTo(a.spentAt)),
      );
    }).toList();
  }

  _Bucket _currentBucket(List<ExpenseEntry> entries) {
    final now = DateTime.now();
    final start = switch (period) {
      _Period.daily => dateOnly(now),
      _Period.weekly => weekStart(now),
      _Period.monthly => DateTime(now.year, now.month),
    };
    final end = _endOf(start);
    return _Bucket(
      start,
      end,
      entries
          .where((e) => !e.day.isBefore(start) && e.day.isBefore(end))
          .toList(),
    );
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  String _bucketLabel(_Bucket b, int index) {
    switch (period) {
      case _Period.daily:
        return dayLabel(b.start);
      case _Period.weekly:
        if (index == 0) return 'This week';
        if (index == 1) return 'Last week';
        return '${shortDate(b.start)} – '
            '${shortDate(b.end.subtract(const Duration(days: 1)))}';
      case _Period.monthly:
        if (index == 0) return 'This month';
        final now = DateTime.now();
        final name = _monthNames[b.start.month - 1];
        return b.start.year == now.year ? name : '$name ${b.start.year}';
    }
  }

  String get _unit => switch (period) {
        _Period.daily => 'day',
        _Period.weekly => 'week',
        _Period.monthly => 'month',
      };

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final entries = _counted;
    final buckets = _buckets(entries);
    final current = _currentBucket(entries);

    // Average only over periods since the first expense, so
    // a new user's empty past doesn't drag it down.
    final first = entries.isEmpty
        ? null
        : entries.map((e) => e.day).reduce((a, b) => a.isBefore(b) ? a : b);
    final active = first == null
        ? <_Bucket>[]
        : buckets.where((b) => b.end.isAfter(first)).toList();
    final average = active.isEmpty
        ? 0.0
        : active.fold<double>(0, (s, b) => s + b.total) / active.length;

    return ValueListenableBuilder<double?>(
      valueListenable: AppSettings.instance.dailyLimit,
      builder: (context, limit, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLimitCard(entries, limit),
          const SizedBox(height: 16),
          SegmentedButton<_Period>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Period.daily, label: Text('Daily')),
              ButtonSegment(value: _Period.weekly, label: Text('Weekly')),
              ButtonSegment(value: _Period.monthly, label: Text('Monthly')),
            ],
            selected: {period},
            onSelectionChanged: (s) => setState(() => period = s.first),
          ),
          const SizedBox(height: 16),
          _buildTotalCard(current, average),
          if (current.entries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCategoryCard(current),
          ],
          const SizedBox(height: 24),
          Text(
            switch (period) {
              _Period.weekly => 'Last $_weekCount weeks',
              _Period.monthly => 'Last $_monthCount months',
              _Period.daily => switch (dayRange) {
                  _DayRange.last7 => 'Last $_dayCount days',
                  _DayRange.thisWeek => 'This week, Monday to Sunday',
                  _DayRange.weekdays => 'This week, Monday to Friday',
                },
            },
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (period == _Period.daily) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_DayRange>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  ButtonSegment(value: _DayRange.last7, label: _fit('7 days')),
                  ButtonSegment(value: _DayRange.thisWeek, label: _fit('Mon–Sun')),
                  ButtonSegment(value: _DayRange.weekdays, label: _fit('Mon–Fri')),
                ],
                selected: {dayRange},
                onSelectionChanged: (s) => _setDayRange(s.first),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildHistory(buckets, limit),
        ],
      ),
    );
  }

  /// Segment label that shrinks instead of wrapping on
  /// narrow screens or with large text.
  static Widget _fit(String text) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
      );

  // --------------------------------------------------
  // DAILY LIMIT
  // --------------------------------------------------

  Widget _buildLimitCard(List<ExpenseEntry> entries, double? limit) {
    final theme = Theme.of(context);

    if (limit == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Set a daily limit'),
          subtitle: const Text('See how much you can spend each day'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => AppSettings.instance.editDailyLimit(context),
        ),
      );
    }

    final today = dateOnly(DateTime.now());
    final start = weekStart(today);

    // Monday = 1 ... Sunday = 7
    final daysLeft = 8 - today.weekday; // including today

    double spentBeforeToday = 0;
    double spentToday = 0;
    var hasEstimates = false;

    for (final e in entries) {
      if (e.day.isBefore(start) || e.day.isAfter(today)) continue;
      if (e.isEstimated) hasEstimates = true;
      if (e.day == today) {
        spentToday += e.amount!;
      } else {
        spentBeforeToday += e.amount!;
      }
    }

    final spentWeek = spentBeforeToday + spentToday;
    final weekBudget = limit * 7;
    final weekRemaining = weekBudget - spentWeek;

    // Even split of what's left (as of this morning) over
    // the remaining days, including today.
    final perDayRest = (weekBudget - spentBeforeToday) / daysLeft;

    // Today's allowance is that average minus what's
    // already been spent today.
    final canSpendToday = perDayRest - spentToday;

    final over = canSpendToday < 0;
    final colors = theme.colorScheme;
    final onCard =
        over ? colors.onErrorContainer : colors.onSecondaryContainer;

    final String footnote;
    if (weekRemaining <= 0) {
      footnote = 'Weekly budget used up · resets Monday';
    } else if (daysLeft == 1) {
      footnote = 'Last day of the week · resets tonight';
    } else {
      final tomorrowOn =
          (weekRemaining / (daysLeft - 1)).clamp(0, double.infinity);
      footnote = over
          ? 'Tomorrow onwards: about ${formatMoney(tomorrowOn.toDouble(), wholeOnly: true)}/day'
          : 'About ${formatMoney(perDayRest, wholeOnly: true)}/day '
              'for the $daysLeft days left (incl. today)';
    }

    return Card(
      margin: EdgeInsets.zero,
      color: over ? colors.errorContainer : colors.secondaryContainer,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: onCard),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      over ? 'Over today\'s allowance by' : 'You can spend today',
                      style: theme.textTheme.titleMedium?.copyWith(color: onCard),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit daily limit',
                    icon: Icon(Icons.edit_outlined, color: onCard),
                    onPressed: () => AppSettings.instance.editDailyLimit(context),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMoney(canSpendToday.abs(), wholeOnly: true),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: onCard,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Spent ${formatMoney(spentToday)} today · '
                      'limit ${formatMoney(limit)}/day',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'This week ${formatMoney(spentWeek, wholeOnly: true)} '
                            'of ${formatMoney(weekBudget, wholeOnly: true)}',
                          ),
                        ),
                        Text(
                          weekRemaining >= 0
                              ? '${formatMoney(weekRemaining, wholeOnly: true)} left'
                              : '${formatMoney(-weekRemaining, wholeOnly: true)} over',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (spentWeek / weekBudget).clamp(0.0, 1.0),
                        minHeight: 8,
                        color: weekRemaining < 0 ? colors.error : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      footnote,
                      style: theme.textTheme.bodySmall?.copyWith(color: onCard),
                    ),
                    if (hasEstimates) ...[
                      const SizedBox(height: 4),
                      Text(
                        '~ Includes unsynced amounts read from your notes',
                        style: theme.textTheme.bodySmall?.copyWith(color: onCard),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // CURRENT PERIOD
  // --------------------------------------------------

  Widget _buildTotalCard(_Bucket current, double average) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: current.entries.isEmpty
            ? null
            : () => _showBucket(current, 'Spent this $_unit'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (period) {
                  _Period.daily => 'Spent today',
                  _Period.weekly => 'Spent this week',
                  _Period.monthly => 'Spent this month',
                },
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: 4),
              Text(
                '${current.hasEstimates ? '~' : ''}${formatMoney(current.total)}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${plural(current.entries.length, 'expense')} · '
                'avg ${formatMoney(average, wholeOnly: true)} per $_unit',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
              if (current.hasEstimates) ...[
                const SizedBox(height: 8),
                Text(
                  '~ Includes unsynced amounts read from your notes. '
                  'Sync for exact figures.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onPrimaryContainer),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(_Bucket current) {
    final byCategory = <String, List<ExpenseEntry>>{};
    for (final e in current.entries) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }

    double sum(List<ExpenseEntry> l) => l.fold(0, (s, e) => s + e.amount!);

    final sorted = byCategory.entries.toList()
      ..sort((a, b) => sum(b.value).compareTo(sum(a.value)));

    final total = current.total;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'By category',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            for (final c in sorted)
              _barRow(
                leading: CategoryAvatar(category: c.key, radius: 16),
                label: c.key,
                value: sum(c.value),
                fraction: total == 0 ? 0 : sum(c.value) / total,
                color: categoryStyle(c.key).color,
                trailingNote: total == 0
                    ? null
                    : '${(sum(c.value) / total * 100).round()}%',
                onTap: () => _showBucket(
                  _Bucket(current.start, current.end, c.value),
                  c.key,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // HISTORY
  // --------------------------------------------------

  Widget _buildHistory(List<_Bucket> buckets, double? limit) {
    final colors = Theme.of(context).colorScheme;
    final max = buckets.fold<double>(0, (m, b) => b.total > m ? b.total : m);

    // A day (or week) over the limit gets a red bar.
    final cap = limit == null
        ? null
        : switch (period) {
            _Period.daily => limit,
            _Period.weekly => limit * 7,
            _Period.monthly => null,
          };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < buckets.length; i++)
              _barRow(
                label: _bucketLabel(buckets[i], i),
                value: buckets[i].total,
                estimated: buckets[i].hasEstimates,
                fraction: max == 0 ? 0 : buckets[i].total / max,
                color: cap != null && buckets[i].total > cap
                    ? colors.error
                    : null,
                onTap: buckets[i].entries.isEmpty
                    ? null
                    : () => _showBucket(
                          buckets[i],
                          _bucketLabel(buckets[i], i),
                        ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _barRow({
    Widget? leading,
    required String label,
    required double value,
    required double fraction,
    bool estimated = false,
    Color? color,
    String? trailingNote,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label)),
                      if (trailingNote != null) ...[
                        Text(
                          trailingNote,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${estimated ? '~' : ''}${formatMoney(value)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      color: color,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sheet listing the expenses behind a row.
  void _showBucket(_Bucket bucket, String title) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                    Text(
                      '${bucket.hasEstimates ? '~' : ''}${formatMoney(bucket.total)}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: bucket.entries.length,
                  itemBuilder: (context, i) {
                    final e = bucket.entries[i];
                    return ExpenseTile(
                      entry: e,
                      showDate: period != _Period.daily,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onEntryTap(e);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
