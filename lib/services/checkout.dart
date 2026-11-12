import '../core/billing.dart';
import '../core/format.dart';
import '../core/upi.dart';
import '../data/models.dart';
import 'receipt.dart';

/// Every figure for a bill, worked out without saving anything.
class BillCalc {
  BillCalc({
    required this.isPool,
    required this.poolStartedAt,
    required this.poolEndedAt,
    required this.playedMinutes,
    required this.billedMinutes,
    this.bookedMinutes,
    required this.rate,
    required this.poolAmount,
    required this.poolCost,
    required this.items,
    required this.itemsSubtotal,
    required this.itemsCost,
    required this.discountPercent,
    required this.totals,
  });

  final bool isPool;
  final DateTime? poolStartedAt;
  final DateTime? poolEndedAt;
  final int playedMinutes;
  final int billedMinutes;

  /// Booked pool time; null = open play.
  final int? bookedMinutes;
  final double rate;
  final double poolAmount;
  final double poolCost;
  final List<InvoiceItem> items;
  final double itemsSubtotal;
  final double itemsCost;
  final double discountPercent;
  final BillTotals totals;

  bool get isEmpty => billedMinutes == 0 && items.isEmpty;
}

/// Options chosen on the checkout screen.
class CheckoutOptions {
  const CheckoutOptions({
    this.paymentMethod = 'upi',
    this.discountPercent = 0,
    this.customerName,
    this.customerPhone,
    this.cashReceived,
  });

  final String paymentMethod;
  final double discountPercent;
  final String? customerName;
  final String? customerPhone;
  final double? cashReceived;
}

/// Port of CheckoutService::calculate() and preview().
class Checkout {
  Checkout._();

  static BillCalc calculate({
    required BusinessSettings settings,
    required RestaurantTable table,
    required TableSession session,
    required Map<int, MenuItem> menu,
    required Map<int, MenuCategory> categories,
    double discountPercent = 0,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final isPool = table.isPool && session.timerStartedAt != null;
    final playedSeconds = isPool ? session.elapsedSeconds(at) : 0;
    final booked = isPool && session.isBooked ? session.bookedMinutes : null;
    final billedMinutes = isPool
        ? Billing.billedMinutes(
            playedSeconds,
            settings.billingBlockMinutes,
            settings.minimumMinutes,
            bookedMinutes: booked,
            graceMinutes: settings.overtimeGraceMinutes,
            bookedIsMinimum: settings.bookedIsMinimum,
          )
        : 0;
    final rate = (session.hourlyRate != null && session.hourlyRate! > 0)
        ? session.hourlyRate!
        : settings.poolRateFor(table, session.timerStartedAt ?? at);
    final poolAmount = Billing.poolAmount(billedMinutes, rate);
    final poolCost = roundTo(playedSeconds / 3600 * settings.poolCostPerHour, 2);

    final items = <InvoiceItem>[];
    for (final line in session.items) {
      final m = menu[line.menuItemId];
      if (m == null) continue;
      final c = categories[m.categoryId];
      items.add(
        InvoiceItem(
          menuItemId: m.id,
          name: m.name,
          categoryName: c?.name,
          categoryType: c?.type,
          qty: line.qty,
          unitPrice: m.price,
          unitCost: m.costPrice,
          amount: roundTo(line.qty * m.price, 2),
        ),
      );
    }
    final itemsSubtotal = roundTo(items.fold(0.0, (s, i) => s + i.amount), 2);
    final itemsCost = roundTo(items.fold(0.0, (s, i) => s + i.qty * i.unitCost), 2);

    return BillCalc(
      isPool: isPool,
      poolStartedAt: session.timerStartedAt,
      poolEndedAt: isPool ? (session.timerStoppedAt ?? session.timerPausedAt ?? at) : null,
      playedMinutes: (playedSeconds / 60).ceil(),
      billedMinutes: billedMinutes,
      bookedMinutes: booked,
      rate: rate,
      poolAmount: poolAmount,
      poolCost: poolCost,
      items: items,
      itemsSubtotal: itemsSubtotal,
      itemsCost: itemsCost,
      discountPercent: discountPercent,
      totals: Billing.totals(
        poolAmount: poolAmount,
        itemsSubtotal: itemsSubtotal,
        discountPercent: discountPercent,
        gstPoolRate: settings.gstPoolRate,
        gstFoodRate: settings.gstFoodRate,
      ),
    );
  }

  static ReceiptLine poolLine({
    required DateTime? startedAt,
    required DateTime? endedAt,
    required int playedMinutes,
    required int billedMinutes,
    int? bookedMinutes,
    required double rate,
    required double amount,
  }) {
    final from = startedAt == null ? '' : Fmt.time(startedAt);
    final to = endedAt == null ? '' : Fmt.time(endedAt);
    final booked = (bookedMinutes ?? 0) > 0 ? 'booked ${Billing.duration(bookedMinutes!)}, ' : '';
    return ReceiptLine(
      name: 'Pool table time',
      note: '$from – $to · ${booked}played ${Billing.duration(playedMinutes)}, billed ${Billing.duration(billedMinutes)}',
      qty: '${Fmt.trim(billedMinutes / 60)} h',
      rate: rate,
      amount: amount,
    );
  }

  /// Draft receipt for the checkout preview (same shape as [ReceiptData.fromInvoice]).
  static ReceiptData preview({
    required BusinessSettings settings,
    required BillCalc calc,
    required String tableName,
    required CheckoutOptions options,
    DateTime? now,
  }) {
    final business = settings.snapshot();
    final number = settings.invoiceNumber();
    final total = calc.totals.total;
    final lines = <ReceiptLine>[
      if (calc.billedMinutes > 0)
        poolLine(
          startedAt: calc.poolStartedAt,
          endedAt: calc.poolEndedAt,
          playedMinutes: calc.playedMinutes,
          billedMinutes: calc.billedMinutes,
          bookedMinutes: calc.bookedMinutes,
          rate: calc.rate,
          amount: calc.poolAmount,
        ),
      for (final i in calc.items) ReceiptLine(name: i.name, qty: '${i.qty}', rate: i.unitPrice, amount: i.amount),
    ];
    final showQr =
        business.showUpiQr &&
        Upi.isValidUpiId(business.upiId) &&
        (options.paymentMethod == 'upi' || options.paymentMethod == 'split') &&
        total > 0;

    return ReceiptData(
      business: business,
      number: number,
      date: now ?? DateTime.now(),
      table: tableName,
      customer: options.customerName,
      phone: options.customerPhone,
      payment: paymentMethods[options.paymentMethod] ?? options.paymentMethod,
      lines: lines,
      subtotal: calc.totals.subtotal,
      discountPercent: calc.discountPercent,
      discount: calc.totals.discount,
      gstPool: calc.totals.gstPool,
      gstFood: calc.totals.gstFood,
      gstPoolRate: settings.gstPoolRate,
      gstFoodRate: settings.gstFoodRate,
      roundOff: calc.totals.roundOff,
      total: total,
      cashReceived: options.cashReceived,
      upiUri: showQr
          ? Upi.uri(upiId: business.upiId!, payeeName: business.upiPayeeName, amount: total, note: 'Bill $number')
          : null,
      upiId: business.upiId,
      draft: true,
    );
  }

  /// Receipt for the Business settings preview: a sample pool + food bill.
  static ReceiptData sample(BusinessSettings settings) {
    const billed = 90;
    final rate = settings.poolRatePerHour;
    final pool = Billing.poolAmount(billed, rate);
    const items = 530.0;
    final t = Billing.totals(
      poolAmount: pool,
      itemsSubtotal: items,
      discountPercent: 0,
      gstPoolRate: settings.gstPoolRate,
      gstFoodRate: settings.gstFoodRate,
    );
    final business = settings.snapshot();
    final number = settings.invoiceNumber();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 20, 34);
    return ReceiptData(
      business: business,
      number: number,
      date: DateTime(now.year, now.month, now.day, 21, 58),
      table: 'Pool Table 1',
      payment: 'UPI',
      lines: [
        poolLine(
          startedAt: start,
          endedAt: start.add(const Duration(minutes: 84)),
          playedMinutes: 84,
          billedMinutes: billed,
          rate: rate,
          amount: pool,
        ),
        const ReceiptLine(name: 'Chicken momo (8 pc)', qty: '2', rate: 120, amount: 240),
        const ReceiptLine(name: 'Cold coffee', qty: '2', rate: 100, amount: 200),
        const ReceiptLine(name: 'French fries', qty: '1', rate: 90, amount: 90),
      ],
      subtotal: t.subtotal,
      discountPercent: 0,
      discount: 0,
      gstPool: t.gstPool,
      gstFood: t.gstFood,
      gstPoolRate: settings.gstPoolRate,
      gstFoodRate: settings.gstFoodRate,
      roundOff: t.roundOff,
      total: t.total,
      upiUri: business.showUpiQr && Upi.isValidUpiId(business.upiId)
          ? Upi.uri(upiId: business.upiId!, payeeName: business.upiPayeeName, amount: t.total, note: 'Bill $number')
          : null,
      upiId: business.upiId,
      draft: true,
      sample: true,
    );
  }
}
