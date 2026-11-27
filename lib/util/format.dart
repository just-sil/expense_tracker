/// Display helpers shared by every screen.
library;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Groups digits the Indian way: 1,23,456.
String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;

  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);

  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);

  return '${parts.join(',')},$last3';
}

/// A plain number with Indian grouping: 1240 -> "1,240",
/// 24.5 -> "24.50". [wholeOnly] rounds to rupees.
String formatNumber(double value, {bool wholeOnly = false}) {
  final negative = value < 0;
  final v = value.abs();

  final whole = wholeOnly || v == v.roundToDouble();
  final text = whole ? v.round().toString() : v.toStringAsFixed(2);

  final dot = text.indexOf('.');
  final intPart = dot == -1 ? text : text.substring(0, dot);
  final decPart = dot == -1 ? '' : text.substring(dot);

  return '${negative ? '-' : ''}${_groupIndian(intPart)}$decPart';
}

/// 1240 -> "₹1,240".
String formatMoney(double value, {bool wholeOnly = false}) {
  final text = formatNumber(value.abs(), wholeOnly: wholeOnly);
  return value < 0 ? '-₹$text' : '₹$text';
}

/// "1 expense", "3 expenses".
String plural(int count, String singular, [String? pluralForm]) =>
    '$count ${count == 1 ? singular : (pluralForm ?? '${singular}s')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d].
DateTime weekStart(DateTime d) =>
    dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// "23 Nov", or "23 Nov 2025" outside the current year.
String shortDate(DateTime d, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year == current.year ? base : '$base ${d.year}';
}

/// "Today", "Yesterday", "Mon, 23 Nov".
String dayLabel(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final day = dateOnly(d);

  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  return '${_weekdays[day.weekday - 1]}, ${shortDate(day, now: today)}';
}

/// "9:05 am".
String timeLabel(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour < 12 ? 'am' : 'pm'}';
}

final RegExp _amountPattern = RegExp(
  r'(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?',
);

final RegExp _currencyAmountPattern = RegExp(
  r'(?:₹|\brs\.?|\binr)\s*((?:\d{1,3}(?:,\d{2,3})+|\d+)(?:\.\d+)?)',
  caseSensitive: false,
);

/// Estimated amount from free text, used until the laptop
/// parses an entry. A number after ₹/Rs/INR wins (so
/// "A/c XX1234 debited Rs.500" -> 500), otherwise the first
/// number: "24 tea" -> 24.
double? amountFromText(String text) {
  final currency = _currencyAmountPattern.firstMatch(text);
  final raw = currency?.group(1) ?? _amountPattern.firstMatch(text)?.group(0);
  if (raw == null) return null;
  return double.tryParse(raw.replaceAll(',', ''));
}
