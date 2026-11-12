import '../core/upi.dart';
import '../data/models.dart';
import 'checkout.dart';

/// 80 mm thermal roll or A4 tax invoice.
enum ReceiptFormat { roll80, a4 }

extension ReceiptFormatLabel on ReceiptFormat {
  String get label => this == ReceiptFormat.a4 ? 'A4 tax invoice' : '80 mm receipt';
}

class ReceiptLine {
  const ReceiptLine({required this.name, this.note, required this.qty, required this.rate, required this.amount});

  final String name;
  final String? note;
  final String qty;
  final double rate;
  final double amount;
}

/// Everything a receipt shows. One shape for the checkout preview, reprints, print and PDF.
class ReceiptData {
  const ReceiptData({
    required this.business,
    required this.number,
    required this.date,
    required this.table,
    this.customer,
    this.phone,
    required this.payment,
    required this.lines,
    required this.subtotal,
    required this.discountPercent,
    required this.discount,
    required this.gstPool,
    required this.gstFood,
    required this.gstPoolRate,
    required this.gstFoodRate,
    required this.roundOff,
    required this.total,
    this.cashReceived,
    this.upiUri,
    this.upiId,
    this.draft = false,
    this.sample = false,
  });

  final BusinessSnapshot business;
  final String number;
  final DateTime date;
  final String table;
  final String? customer;
  final String? phone;
  final String payment;
  final List<ReceiptLine> lines;
  final double subtotal;
  final double discountPercent;
  final double discount;
  final double gstPool;
  final double gstFood;
  final double gstPoolRate;
  final double gstFoodRate;
  final double roundOff;
  final double total;
  final double? cashReceived;

  /// `upi://pay?...` for the QR code; null when no QR is printed.
  final String? upiUri;
  final String? upiId;
  final bool draft;
  final bool sample;

  String? get customerLine {
    final parts = [
      if (customer != null && customer!.trim().isNotEmpty) customer!.trim(),
      if (phone != null && phone!.trim().isNotEmpty) phone!.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory ReceiptData.fromInvoice(Invoice inv) {
    final b = inv.business;
    final lines = <ReceiptLine>[
      if (inv.poolBilledMinutes > 0)
        Checkout.poolLine(
          startedAt: inv.poolStartedAt,
          endedAt: inv.poolEndedAt,
          playedMinutes: inv.poolPlayedMinutes,
          billedMinutes: inv.poolBilledMinutes,
          bookedMinutes: inv.poolBookedMinutes,
          rate: inv.poolRate,
          amount: inv.poolAmount,
        ),
      for (final i in inv.items) ReceiptLine(name: i.name, qty: '${i.qty}', rate: i.unitPrice, amount: i.amount),
    ];
    final showQr =
        b.showUpiQr &&
        Upi.isValidUpiId(b.upiId) &&
        (inv.paymentMethod == 'upi' || inv.paymentMethod == 'split') &&
        inv.total > 0;
    return ReceiptData(
      business: b,
      number: inv.number,
      date: inv.paidAt,
      table: inv.tableName,
      customer: inv.customerName,
      phone: inv.customerPhone,
      payment: inv.paymentLabel,
      lines: lines,
      subtotal: inv.poolAmount + inv.itemsSubtotal,
      discountPercent: inv.discountPercent,
      discount: inv.discountAmount,
      gstPool: inv.gstPool,
      gstFood: inv.gstFood,
      gstPoolRate: inv.gstPoolRate,
      gstFoodRate: inv.gstFoodRate,
      roundOff: inv.roundOff,
      total: inv.total,
      cashReceived: inv.cashReceived,
      upiUri: showQr
          ? Upi.uri(upiId: b.upiId!, payeeName: b.upiPayeeName, amount: inv.total, note: 'Bill ${inv.number}')
          : null,
      upiId: b.upiId,
    );
  }
}
