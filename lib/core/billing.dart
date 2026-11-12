import 'dart:math' as math;

/// Rounds like PHP's round(): half away from zero, with a small pre-rounding
/// step so values such as 1.005 round to 1.01 instead of 1.00.
double roundTo(double value, [int places = 0]) {
  final factor = math.pow(10, places).toDouble();
  final scaled = double.parse((value * factor).toStringAsFixed(6));
  return scaled.round() / factor;
}

/// Bill figures returned by [Billing.totals].
class BillTotals {
  const BillTotals({
    required this.subtotal,
    required this.discountPool,
    required this.discountFood,
    required this.discount,
    required this.gstPool,
    required this.gstFood,
    required this.exact,
    required this.roundOff,
    required this.total,
    required this.netRevenue,
  });

  final double subtotal;
  final double discountPool;
  final double discountFood;
  final double discount;
  final double gstPool;
  final double gstFood;
  final double exact;
  final double roundOff;
  final double total;

  /// After discount, before GST.
  final double netRevenue;

  double get gst => roundTo(gstPool + gstFood, 2);
}

/// Pure billing maths (no Flutter or database code), so it is easy to unit test.
/// Port of app/Support/Billing.php: keep the two in step.
class Billing {
  Billing._();

  /// Seconds played: (stopped or paused or now) − started − paused seconds.
  static int elapsedSeconds({
    required int? startedAt,
    required int pausedSeconds,
    required int? pausedAt,
    required int? stoppedAt,
    required int now,
  }) {
    if (startedAt == null || startedAt == 0) return 0;
    final end = stoppedAt ?? pausedAt ?? now;
    return math.max(0, end - startedAt - pausedSeconds);
  }

  /// Minutes the customer pays for, never below the minimum.
  ///
  /// Open play (no [bookedMinutes]): played time rounded up to the billing block.
  ///
  /// Booked time: the booking is billed in full when [bookedIsMinimum] (otherwise
  /// played time, capped at the booking). Overtime of up to [graceMinutes] is free;
  /// past that, the overtime is rounded up to the block and added to the booking.
  static int billedMinutes(
    int elapsedSeconds,
    int blockMinutes,
    int minimumMinutes, {
    int? bookedMinutes,
    int graceMinutes = 0,
    bool bookedIsMinimum = true,
  }) {
    if (elapsedSeconds <= 0) return 0;
    final played = (elapsedSeconds / 60).ceil();
    int toBlock(int m) => blockMinutes > 1 ? (m / blockMinutes).ceil() * blockMinutes : m;

    final int minutes;
    final booked = bookedMinutes ?? 0;
    if (booked <= 0) {
      minutes = toBlock(played);
    } else {
      final over = played - booked;
      if (over <= 0) {
        minutes = bookedIsMinimum ? booked : math.min(toBlock(played), booked);
      } else if (over <= graceMinutes) {
        minutes = booked;
      } else {
        minutes = booked + toBlock(over);
      }
    }
    return math.max(minutes, minimumMinutes);
  }

  static double poolAmount(int billedMinutes, double ratePerHour) => roundTo(billedMinutes / 60 * ratePerHour, 2);

  /// Prices are GST-exclusive; the discount applies to pool time and items alike.
  static BillTotals totals({
    required double poolAmount,
    required double itemsSubtotal,
    required double discountPercent,
    required double gstPoolRate,
    required double gstFoodRate,
  }) {
    final pct = discountPercent.clamp(0, 100).toDouble();
    final discountPool = roundTo(poolAmount * pct / 100, 2);
    final discountFood = roundTo(itemsSubtotal * pct / 100, 2);
    final netPool = poolAmount - discountPool;
    final netFood = itemsSubtotal - discountFood;
    final gstPool = roundTo(netPool * gstPoolRate / 100, 2);
    final gstFood = roundTo(netFood * gstFoodRate / 100, 2);
    final exact = roundTo(netPool + netFood + gstPool + gstFood, 2);
    final total = roundTo(exact);

    return BillTotals(
      subtotal: roundTo(poolAmount + itemsSubtotal, 2),
      discountPool: discountPool,
      discountFood: discountFood,
      discount: roundTo(discountPool + discountFood, 2),
      gstPool: gstPool,
      gstFood: gstFood,
      exact: exact,
      roundOff: roundTo(total - exact, 2),
      total: total,
      netRevenue: roundTo(netPool + netFood, 2),
    );
  }

  /// Seconds left on a booking (negative once over time); null for open play.
  static int? remainingSeconds(int elapsedSeconds, int? bookedMinutes) =>
      (bookedMinutes == null || bookedMinutes <= 0) ? null : bookedMinutes * 60 - elapsedSeconds;

  /// `1h 24m`, `45m`, `2h`, `0m`.
  static String duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final parts = <String>[if (h > 0) '${h}h', if (m > 0 || h == 0) '${m}m'];
    return parts.join(' ');
  }
}
