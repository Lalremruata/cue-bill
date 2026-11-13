import 'dart:math' as math;

import '../core/billing.dart';
import '../data/models.dart';

DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime endOfDay(DateTime t) => DateTime(t.year, t.month, t.day, 23, 59, 59, 999);

/// Whole calendar days between two dates (ignores time of day and DST).
int calendarDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

class Summary {
  const Summary({
    required this.collected,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.margin,
    required this.invoices,
    required this.poolHours,
    required this.gst,
    required this.discount,
  });

  final double collected;
  final double revenue;
  final double cost;
  final double profit;
  final double margin;
  final int invoices;
  final double poolHours;
  final double gst;
  final double discount;
}

class DailyRow {
  const DailyRow({
    required this.date,
    required this.invoices,
    required this.poolHours,
    required this.pool,
    required this.food,
    required this.drinks,
    required this.snacks,
    required this.dineIn,
    required this.takeaway,
    required this.revenue,
    required this.collected,
    required this.profit,
    required this.margin,
  });

  final DateTime date;
  final int invoices;
  final double poolHours;
  final double pool;
  final double food;
  final double drinks;
  final double snacks;

  /// Menu item sales after discount, before GST (pool time not included).
  final double dineIn;
  final double takeaway;
  final double revenue;
  final double collected;
  final double profit;
  final double margin;
}

class MixRow {
  const MixRow({required this.key, required this.name, required this.revenue, required this.cost});

  final String key;
  final String name;
  final double revenue;
  final double cost;

  double get profit => roundTo(revenue - cost, 2);

  double get margin => revenue > 0 ? roundTo(profit / revenue * 100, 1) : 0;
}

enum Rating { star, steady, slow, lossRisk }

extension RatingLabel on Rating {
  String get label => switch (this) {
    Rating.star => 'Star',
    Rating.steady => 'Steady',
    Rating.slow => 'Slow',
    Rating.lossRisk => 'Loss risk',
  };
}

class ItemRow {
  ItemRow({
    required this.name,
    required this.category,
    required this.type,
    required this.qty,
    required this.isPool,
    required this.revenue,
    required this.cost,
    this.listMargin,
  });

  final String name;
  final String? category;
  final String? type;

  /// Units sold, or hours for the pool table row.
  final double qty;
  final bool isPool;
  final double revenue;
  final double cost;
  final double? listMargin;
  late final double profit = roundTo(revenue - cost, 2);
  late final double margin = revenue > 0 ? roundTo(profit / revenue * 100, 1) : (listMargin ?? 0);
  late Rating rating;

  String get qtyLabel => isPool ? '${_trim1(qty)} h' : qty.toInt().toString();

  static String _trim1(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// One line of the plain item sales list: what sold and for how much.
class SalesLine {
  const SalesLine({
    required this.name,
    this.category,
    required this.qty,
    required this.amount,
    this.isPool = false,
    this.perDay = const [],
  });

  final String name;
  final String? category;

  /// Units sold, or hours for the pool table line.
  final double qty;

  /// Menu price × qty, before bill discounts and GST.
  final double amount;
  final bool isPool;

  /// [qty] for each day of the period, oldest first (see [SalesAnalytics.dates]).
  final List<double> perDay;

  String get qtyLabel => _label(qty);

  /// Quantity sold on day [i] of the period, e.g. `3` or `1.5 h`.
  String dayLabel(int i) => _label(i < perDay.length ? perDay[i] : 0);

  String _label(double v) => isPool ? '${ItemRow._trim1(v)} h' : v.toInt().toString();
}

const itemSorts = {'profit': 'Profit', 'revenue': 'Revenue', 'qty': 'Qty', 'margin': 'Margin %'};

/// Every dashboard and report number. Revenue = after discount, before GST.
/// "Collected" = what the customer paid (incl. GST). Port of SalesAnalytics.php.
class SalesAnalytics {
  SalesAnalytics({
    required DateTime from,
    required DateTime to,
    required List<Invoice> invoices,
    required this.activeMenu,
    required this.categories,
    required this.poolTables,
    this.payment,
    this.orderType,
  }) : from = startOfDay(from),
       to = endOfDay(to),
       invoices = invoices
           .where(
             (i) =>
                 !i.paidAt.isBefore(startOfDay(from)) &&
                 !i.paidAt.isAfter(endOfDay(to)) &&
                 (payment == null || i.paymentMethod == payment) &&
                 (orderType == null || i.orderType == orderType),
           )
           .toList();

  final DateTime from;
  final DateTime to;
  final String? payment;

  /// `dine_in` or `takeaway`; null = both.
  final String? orderType;
  final List<Invoice> invoices;
  final List<MenuItem> activeMenu;
  final Map<int, MenuCategory> categories;
  final int poolTables;

  int get days => calendarDaysBetween(from, to) + 1;

  /// Every day of the period, oldest first.
  List<DateTime> get dates => [for (var d = 0; d < days; d++) DateTime(from.year, from.month, from.day + d)];

  static (DateTime, DateTime) lastDays(int n, [DateTime? end]) {
    final e = endOfDay(end ?? DateTime.now());
    final s = startOfDay(DateTime(e.year, e.month, e.day - (n - 1)));
    return (s, e);
  }

  /// The same number of days just before this period.
  (DateTime, DateTime) previousPeriod() {
    final n = days;
    return (DateTime(from.year, from.month, from.day - n), endOfDay(DateTime(from.year, from.month, from.day - 1)));
  }

  Summary summary() {
    var collected = 0.0, revenue = 0.0, cost = 0.0, gst = 0.0, discount = 0.0;
    var poolMinutes = 0;
    for (final i in invoices) {
      collected += i.total;
      revenue += i.netRevenue;
      cost += i.totalCost;
      gst += i.gstPool + i.gstFood;
      discount += i.discountAmount;
      poolMinutes += i.poolPlayedMinutes;
    }
    final profit = revenue - cost;
    return Summary(
      collected: roundTo(collected, 2),
      revenue: roundTo(revenue, 2),
      cost: roundTo(cost, 2),
      profit: roundTo(profit, 2),
      margin: revenue > 0 ? roundTo(profit / revenue * 100, 1) : 0,
      invoices: invoices.length,
      poolHours: roundTo(poolMinutes / 60, 1),
      gst: roundTo(gst, 2),
      discount: roundTo(discount, 2),
    );
  }

  /// Pool table occupancy % over the period (all pool tables, opening hours 12 PM to midnight).
  /// [liveMinutes]: time on tables still playing, not yet on an invoice.
  double poolOccupancy({int openHoursPerDay = 12, double liveMinutes = 0}) {
    final tables = math.max(1, poolTables);
    final minutes = invoices.fold<int>(0, (s, i) => s + i.poolPlayedMinutes) + liveMinutes;
    return roundTo(math.min(100, minutes / (tables * days * openHoursPerDay * 60) * 100), 1);
  }

  static double _poolRevenue(Invoice i) => i.poolAmount * (1 - i.discountPercent / 100);

  /// One row per day with pool / food / drinks / snacks revenue and profit.
  List<DailyRow> daily() {
    final byDay = <DateTime, List<Invoice>>{};
    for (final i in invoices) {
      byDay.putIfAbsent(startOfDay(i.paidAt), () => []).add(i);
    }
    final rows = <DailyRow>[];
    for (var d = 0; d < days; d++) {
      final date = DateTime(from.year, from.month, from.day + d);
      final list = byDay[date] ?? const <Invoice>[];
      var revenue = 0.0, cost = 0.0, collected = 0.0, pool = 0.0, dineIn = 0.0, takeaway = 0.0;
      var poolMinutes = 0;
      final types = <String, double>{};
      for (final i in list) {
        revenue += i.netRevenue;
        cost += i.totalCost;
        collected += i.total;
        poolMinutes += i.poolPlayedMinutes;
        pool += _poolRevenue(i);
        for (final it in i.items) {
          final t = it.categoryType ?? '';
          final amount = it.amount * (1 - i.discountPercent / 100);
          types[t] = (types[t] ?? 0) + amount;
          if (i.isTakeaway) {
            takeaway += amount;
          } else {
            dineIn += amount;
          }
        }
      }
      final profit = revenue - cost;
      rows.add(
        DailyRow(
          date: date,
          invoices: list.length,
          poolHours: roundTo(poolMinutes / 60, 1),
          pool: roundTo(pool, 2),
          food: roundTo(types['food'] ?? 0, 2),
          drinks: roundTo(types['drinks'] ?? 0, 2),
          snacks: roundTo(types['snacks'] ?? 0, 2),
          dineIn: roundTo(dineIn, 2),
          takeaway: roundTo(takeaway, 2),
          revenue: roundTo(revenue, 2),
          collected: roundTo(collected, 2),
          profit: roundTo(profit, 2),
          margin: revenue > 0 ? roundTo(profit / revenue * 100, 1) : 0,
        ),
      );
    }
    return rows;
  }

  /// Revenue and profit for pool time and each menu category type.
  List<MixRow> mix() {
    var poolRevenue = 0.0, poolCost = 0.0;
    final revenue = <String, double>{};
    final cost = <String, double>{};
    for (final i in invoices) {
      poolRevenue += _poolRevenue(i);
      poolCost += i.poolCost;
      for (final it in i.items) {
        final t = it.categoryType ?? '';
        revenue[t] = (revenue[t] ?? 0) + it.amount * (1 - i.discountPercent / 100);
        cost[t] = (cost[t] ?? 0) + it.qty * it.unitCost;
      }
    }
    return [
      MixRow(key: 'pool', name: 'Pool table time', revenue: roundTo(poolRevenue, 2), cost: roundTo(poolCost, 2)),
      for (final e in categoryTypes.entries)
        MixRow(key: e.key, name: e.value, revenue: roundTo(revenue[e.key] ?? 0, 2), cost: roundTo(cost[e.key] ?? 0, 2)),
    ];
  }

  /// Item performance with a rating: Star, Steady, Slow or Loss risk.
  /// Item revenue here is the menu price × qty (before bill discounts).
  List<ItemRow> items({String? categoryType, String sort = 'profit'}) {
    final rows = <ItemRow>[];

    if (categoryType == null || categoryType == 'pool') {
      var minutes = 0, revenue = 0.0, cost = 0.0;
      for (final i in invoices) {
        minutes += i.poolBilledMinutes;
        revenue += i.poolAmount;
        cost += i.poolCost;
      }
      if (minutes > 0) {
        rows.add(
          ItemRow(
            name: 'Pool table (per hour)',
            category: 'Pool table',
            type: 'pool',
            qty: roundTo(minutes / 60, 1),
            isPool: true,
            revenue: roundTo(revenue, 2),
            cost: roundTo(cost, 2),
          ),
        );
      }
    }

    if (categoryType != 'pool') {
      final sold = <String, ({InvoiceItem first, int qty, double revenue, double cost})>{};
      for (final i in invoices) {
        for (final it in i.items) {
          if (categoryType != null && it.categoryType != categoryType) continue;
          final key = '${it.menuItemId}|${it.name}|${it.categoryName}|${it.categoryType}';
          final prev = sold[key];
          sold[key] = (
            first: prev?.first ?? it,
            qty: (prev?.qty ?? 0) + it.qty,
            revenue: (prev?.revenue ?? 0) + it.amount,
            cost: (prev?.cost ?? 0) + it.qty * it.unitCost,
          );
        }
      }
      final soldIds = <int>{};
      for (final s in sold.values) {
        if (s.first.menuItemId != null) soldIds.add(s.first.menuItemId!);
        rows.add(
          ItemRow(
            name: s.first.name,
            category: s.first.categoryName,
            type: s.first.categoryType,
            qty: s.qty.toDouble(),
            isPool: false,
            revenue: roundTo(s.revenue, 2),
            cost: roundTo(s.cost, 2),
          ),
        );
      }

      // Active items that did not sell at all in the period.
      for (final m in activeMenu) {
        if (soldIds.contains(m.id)) continue;
        final c = categories[m.categoryId];
        if (categoryType != null && c?.type != categoryType) continue;
        rows.add(
          ItemRow(
            name: m.name,
            category: c?.name,
            type: c?.type,
            qty: 0,
            isPool: false,
            revenue: 0,
            cost: 0,
            listMargin: m.marginPercent,
          ),
        );
      }
    }

    final menuRows = rows.where((r) => !r.isPool).toList();
    final avgQty = math.max(1.0, menuRows.isEmpty ? 0.0 : menuRows.fold(0.0, (s, r) => s + r.qty) / menuRows.length);

    for (final r in rows) {
      r.rating = switch (r) {
        _ when r.margin < 30 => Rating.lossRisk,
        _ when !r.isPool && r.qty < math.max(5, avgQty * 0.2) => Rating.slow,
        _ when r.margin >= 60 && (r.isPool || r.qty >= avgQty) => Rating.star,
        _ => Rating.steady,
      };
    }

    double key(ItemRow r) => switch (sort) {
      'revenue' => r.revenue,
      'qty' => r.qty,
      'margin' => r.margin,
      _ => r.profit,
    };
    rows.sort((a, b) => key(b).compareTo(key(a)));
    return rows;
  }

  /// Plain list of what sold in the period, for an end-of-day count: pool time first,
  /// then items in menu category order, most sold first. Unsold items are left out.
  List<SalesLine> sales({String? categoryType}) {
    final lines = <SalesLine>[];
    final n = days;
    int dayOf(Invoice i) => calendarDaysBetween(from, i.paidAt).clamp(0, n - 1);

    if (categoryType == null || categoryType == 'pool') {
      var minutes = 0, amount = 0.0;
      final minutesByDay = List<int>.filled(n, 0);
      for (final i in invoices) {
        minutes += i.poolBilledMinutes;
        amount += i.poolAmount;
        minutesByDay[dayOf(i)] += i.poolBilledMinutes;
      }
      if (minutes > 0) {
        lines.add(
          SalesLine(
            name: 'Pool table',
            category: 'Pool table',
            qty: roundTo(minutes / 60, 1),
            amount: roundTo(amount, 2),
            isPool: true,
            perDay: [for (final m in minutesByDay) roundTo(m / 60, 1)],
          ),
        );
      }
    }
    if (categoryType == 'pool') return lines;

    final sold = <String, ({String name, String? category, int qty, double amount, List<int> perDay})>{};
    for (final i in invoices) {
      final day = dayOf(i);
      for (final it in i.items) {
        if (categoryType != null && it.categoryType != categoryType) continue;
        final key = '${it.menuItemId}|${it.name}|${it.categoryName}';
        final prev = sold[key];
        final perDay = prev?.perDay ?? List<int>.filled(n, 0);
        perDay[day] += it.qty;
        sold[key] = (
          name: it.name,
          category: it.categoryName,
          qty: (prev?.qty ?? 0) + it.qty,
          amount: (prev?.amount ?? 0) + it.amount,
          perDay: perDay,
        );
      }
    }

    // Categories in menu order; ones no longer on the menu go last, by name.
    final order = {for (final c in categories.values) c.name: c.sort};
    final items = sold.values.where((s) => s.qty > 0).toList()
      ..sort((a, b) {
        final byOrder = (order[a.category] ?? 1 << 30).compareTo(order[b.category] ?? 1 << 30);
        if (byOrder != 0) return byOrder;
        final byCategory = (a.category ?? '').compareTo(b.category ?? '');
        if (byCategory != 0) return byCategory;
        final byQty = b.qty.compareTo(a.qty);
        return byQty != 0 ? byQty : a.name.compareTo(b.name);
      });
    for (final s in items) {
      lines.add(
        SalesLine(
          name: s.name,
          category: s.category,
          qty: s.qty.toDouble(),
          amount: roundTo(s.amount, 2),
          perDay: [for (final q in s.perDay) q.toDouble()],
        ),
      );
    }
    return lines;
  }

  /// Average pool table occupancy % by hour of day (12 PM – 11 PM).
  Map<int, double> busyHours({int fromHour = 12, int toHour = 23}) {
    final minutesByHour = List<double>.filled(24, 0);
    for (final inv in invoices) {
      final start = inv.poolStartedAt;
      if (start == null) continue;
      var cursor = start;
      final end = inv.poolEndedAt ?? start;
      while (cursor.isBefore(end)) {
        final hourStart = DateTime(cursor.year, cursor.month, cursor.day, cursor.hour);
        final nextHour = hourStart.add(const Duration(hours: 1));
        final next = nextHour.isBefore(end) ? nextHour : end;
        minutesByHour[cursor.hour] += next.difference(cursor).inSeconds / 60;
        cursor = next;
      }
    }
    final tables = math.max(1, poolTables);
    return {
      for (var h = fromHour; h <= toHour; h++)
        h: roundTo(math.min(100, minutesByHour[h] / (tables * days * 60) * 100), 1),
    };
  }
}
