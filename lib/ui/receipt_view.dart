import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/format.dart';
import '../services/receipt.dart';
import 'theme.dart';

/// White receipt paper on a grey tray: always white, even in dark mode.
/// Mirrors ReceiptPdf: keep the two in step.
class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.data, this.format = ReceiptFormat.roll80, this.compact = false});

  final ReceiptData data;
  final ReceiptFormat format;

  /// Settings preview: header, total, QR and footer only.
  final bool compact;

  static const _ink = Color(0xFF111111);
  static const _muted = Color(0xFF555555);

  @override
  Widget build(BuildContext context) {
    final a4 = format == ReceiptFormat.a4;
    final r = data;
    final b = r.business;
    final base = a4 ? 13.0 : 12.5;
    final style = TextStyle(fontSize: base, color: _ink, fontFamily: 'Inter', fontFeatures: tabular, height: 1.35);
    final muted = style.copyWith(color: _muted, fontSize: base - 1);

    Widget dashed() => const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: _Dashed());

    Widget pair(String left, String right, {TextStyle? s, FontWeight? leftWeight}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(left, style: (s ?? style).copyWith(fontWeight: leftWeight)),
          ),
          const SizedBox(width: 8),
          Text(right, style: s ?? style, textAlign: TextAlign.right),
        ],
      ),
    );

    String gstHalf(double rate) => Fmt.trim(rate / 2);
    final logo = b.logoPath != null && File(b.logoPath!).existsSync() ? File(b.logoPath!) : null;

    final header = Column(
      children: [
        if (logo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Image.file(logo, height: a4 ? 56 : 44, fit: BoxFit.contain),
          ),
        Text(
          b.name,
          textAlign: TextAlign.center,
          style: style.copyWith(fontSize: a4 ? 20 : 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        if (b.address != null) Text(b.address!, textAlign: TextAlign.center, style: muted),
        if (b.cityLine.isNotEmpty) Text(b.cityLine, textAlign: TextAlign.center, style: muted),
        if (b.phone != null) Text('Ph: ${b.phone}', textAlign: TextAlign.center, style: muted),
        if (b.gstin != null) Text('GSTIN: ${b.gstin}', textAlign: TextAlign.center, style: muted),
        if (b.fssai != null) Text('FSSAI: ${b.fssai}', textAlign: TextAlign.center, style: muted),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('TAX INVOICE', style: style.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            if (r.draft && !r.sample) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: _muted),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('PREVIEW', style: muted.copyWith(fontSize: 9.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ],
    );

    final total = Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _ink, width: 1.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'TOTAL',
              style: style.copyWith(fontWeight: FontWeight.w700, fontSize: base + 1),
            ),
          ),
          Text(
            Fmt.inr(r.total),
            style: style.copyWith(fontWeight: FontWeight.w700, fontSize: 24, fontFamily: CbText.heading),
          ),
        ],
      ),
    );

    final qr = r.upiUri == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              children: [
                Semantics(
                  label: 'UPI QR code to pay ${Fmt.inr(r.total)}',
                  child: QrImageView(
                    data: r.upiUri!,
                    size: a4 ? 140 : 124,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Scan to pay ${Fmt.inr(r.total)} with any UPI app',
                  textAlign: TextAlign.center,
                  style: style.copyWith(fontWeight: FontWeight.w600, fontSize: base - 0.5),
                ),
                if (r.upiId != null) Text(r.upiId!, style: muted.copyWith(fontSize: base - 2)),
              ],
            ),
          );

    final footer = b.footer == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(b.footer!, textAlign: TextAlign.center, style: muted),
          );

    final th = muted.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6);

    final children = compact
        ? <Widget>[header, dashed(), pair(r.number, 'Sample bill', s: muted), total, ?qr, ?footer]
        : <Widget>[
            header,
            dashed(),
            pair('Invoice: ${r.number}', Fmt.invoiceDate(r.date)),
            pair('Table: ${r.table}', 'Paid by: ${r.payment}'),
            if (r.customerLine != null) pair('Customer: ${r.customerLine}', ''),
            dashed(),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(5),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.6),
                3: FlexColumnWidth(2.1),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFDDDDDD))),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('ITEM', style: th),
                    ),
                    Text('QTY', style: th, textAlign: TextAlign.right),
                    Text('RATE', style: th, textAlign: TextAlign.right),
                    Text('AMT', style: th, textAlign: TextAlign.right),
                  ],
                ),
                for (final line in r.lines)
                  TableRow(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(line.name, style: style),
                            if (line.note != null) Text(line.note!, style: muted.copyWith(fontSize: base - 2.5)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(line.qty, style: style, textAlign: TextAlign.right),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(Fmt.trim(line.rate), style: style, textAlign: TextAlign.right),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(Fmt.amount(line.amount), style: style, textAlign: TextAlign.right),
                      ),
                    ],
                  ),
              ],
            ),
            if (r.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('No items yet', style: muted, textAlign: TextAlign.center),
              ),
            dashed(),
            pair('Subtotal', Fmt.amount(r.subtotal)),
            if (r.discount > 0) pair('Discount (${Fmt.trim(r.discountPercent)}%)', '-${Fmt.amount(r.discount)}'),
            if (r.gstPool > 0)
              pair(
                'CGST ${gstHalf(r.gstPoolRate)}% + SGST ${gstHalf(r.gstPoolRate)}% (pool table)',
                Fmt.amount(r.gstPool),
                s: muted,
              ),
            if (r.gstFood > 0)
              pair(
                'CGST ${gstHalf(r.gstFoodRate)}% + SGST ${gstHalf(r.gstFoodRate)}% (food & drinks)',
                Fmt.amount(r.gstFood),
                s: muted,
              ),
            if (r.roundOff.abs() > 0) pair('Round off', Fmt.amount(r.roundOff), s: muted),
            total,
            if (r.cashReceived != null && r.cashReceived! > 0)
              pair(
                'Cash received ${Fmt.inr(r.cashReceived!)}',
                'Change ${Fmt.inr((r.cashReceived! - r.total).clamp(0, double.infinity))}',
                s: muted.copyWith(fontSize: base - 1.5),
              ),
            ?qr,
            ?footer,
          ];

    return Container(
      width: a4 ? 520 : 340,
      padding: EdgeInsets.symmetric(horizontal: a4 ? 36 : 20, vertical: a4 ? 32 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: DefaultTextStyle(
        style: style,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

/// Grey tray that holds the receipt paper.
class ReceiptTray extends StatelessWidget {
  const ReceiptTray({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: context.cb.tray, borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      alignment: Alignment.topCenter,
      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: child),
    );
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const dash = 4.0, gap = 3.0;
        final count = (c.maxWidth / (dash + gap)).floor();
        return Row(
          children: List.generate(
            count,
            (_) => Container(
              width: dash,
              height: 1,
              margin: const EdgeInsets.only(right: gap),
              color: const Color(0xFF999999),
            ),
          ),
        );
      },
    );
  }
}
