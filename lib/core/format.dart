import 'package:intl/intl.dart';

/// Money, number and time formatting. Every amount on screen goes through [inr].
class Fmt {
  Fmt._();

  static String _group(String whole) {
    // Indian digit grouping: 1,23,45,678
    if (whole.length <= 3) return whole;
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    return '${groups.join(',')},$last3';
  }

  static String _number(double amount, int decimals) {
    final fixed = amount.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final grouped = _group(parts[0]);
    return parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  }

  /// `₹1,48,620` or, with decimals, `₹12,34,567.50`.
  static String inr(num amount, [int decimals = 0]) {
    final value = amount.toDouble();
    final negative = value < 0 && double.parse(value.abs().toStringAsFixed(decimals)) > 0;
    return '${negative ? '-' : ''}₹${_number(value, decimals)}';
  }

  /// Whole numbers with Indian grouping: `1,184`.
  static String count(int n) => '${n < 0 ? '-' : ''}${_group(n.abs().toString())}';

  /// Receipt line amounts: `1,240.00` (no symbol, two decimals).
  static String amount(num value) {
    final v = value.toDouble();
    final negative = v < 0 && v.abs() >= 0.005;
    return '${negative ? '-' : ''}${_number(v, 2)}';
  }

  /// `1.5`, `2`, `12.25`: trailing zeros removed.
  static String trim(num value, [int decimals = 2]) {
    var s = value.toDouble().toStringAsFixed(decimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  static String percent(num value, [int decimals = 1]) => '${trim(value, decimals)}%';

  /// Live timer: `01:24:10`.
  static String timer(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
  }

  /// `9:42 PM`
  static String time(DateTime t) => DateFormat('h:mm a').format(t);

  /// `06-11-2026 9:42 PM` (invoices)
  static String invoiceDate(DateTime t) => DateFormat('dd-MM-yyyy h:mm a').format(t);

  /// `06 Nov` (tables)
  static String shortDate(DateTime t) => DateFormat('dd MMM').format(t);

  /// `06 Nov 2026`
  static String date(DateTime t) => DateFormat('dd MMM yyyy').format(t);

  /// `01 Nov 2026 – 10 Nov 2026`, or just `10 Nov 2026` for a single day.
  static String dateRange(DateTime from, DateTime to) =>
      date(from) == date(to) ? date(from) : '${date(from)} – ${date(to)}';

  /// `Friday, 6 November 2026`
  static String longDate(DateTime t) => DateFormat('EEEE, d MMMM yyyy').format(t);

  /// `2026-11-06`
  static String isoDate(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

  /// `12:00` (24 h, stored) to `12:00 PM`.
  static String clock(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    final t = DateTime(2000, 1, 1, int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
    return time(t);
  }

  /// "Saved today, 10:42 AM", "Saved 05 Nov, 9:10 PM".
  static String relativeDay(DateTime t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    final when = diff == 0 ? 'today' : (diff == 1 ? 'yesterday' : shortDate(t));
    return '$when, ${time(t)}';
  }
}
