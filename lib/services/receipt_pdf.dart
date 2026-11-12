import 'dart:io';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import 'receipt.dart';

/// Bundled fonts for PDFs (Inter has the ₹ glyph; the built-in PDF fonts do not).
class PdfFonts {
  PdfFonts._();

  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> theme() async {
    if (_theme != null) return _theme!;
    Future<pw.Font> load(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
    _theme = pw.ThemeData.withFont(
      base: await load('Inter-Regular'),
      bold: await load('Inter-Bold'),
      italic: await load('Inter-Regular'),
      boldItalic: await load('Inter-Bold'),
    );
    return _theme!;
  }
}

/// The receipt as a PDF, for printing (80 mm roll or A4) and "Save as PDF".
/// Mirrors the on-screen ReceiptView: keep the two in step.
class ReceiptPdf {
  ReceiptPdf._();

  static PdfPageFormat pageFormat(ReceiptFormat format) => format == ReceiptFormat.a4
      ? PdfPageFormat.a4.copyWith(
          marginLeft: 20 * PdfPageFormat.mm,
          marginRight: 20 * PdfPageFormat.mm,
          marginTop: 16 * PdfPageFormat.mm,
          marginBottom: 16 * PdfPageFormat.mm,
        )
      : PdfPageFormat.roll80.copyWith(
          marginLeft: 4 * PdfPageFormat.mm,
          marginRight: 4 * PdfPageFormat.mm,
          marginTop: 4 * PdfPageFormat.mm,
          marginBottom: 6 * PdfPageFormat.mm,
        );

  static Future<Uint8List> build(ReceiptData r, ReceiptFormat format) async {
    final theme = await PdfFonts.theme();
    final a4 = format == ReceiptFormat.a4;
    final base = a4 ? 10.0 : 8.0;
    final small = base - 1.5;
    final muted = PdfColor.fromInt(0xFF444444);
    final b = r.business;

    pw.MemoryImage? logo;
    if (b.logoPath != null) {
      final f = File(b.logoPath!);
      if (await f.exists()) logo = pw.MemoryImage(await f.readAsBytes());
    }

    pw.Widget dashed({double top = 6, double bottom = 6}) => pw.Container(
      margin: pw.EdgeInsets.only(top: top, bottom: bottom),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.6, style: pw.BorderStyle.dashed)),
      ),
    );

    pw.Widget pair(String left, String right, {pw.TextStyle? style}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(left, style: style)),
          pw.SizedBox(width: 6),
          pw.Text(right, style: style, textAlign: pw.TextAlign.right),
        ],
      ),
    );

    final mutedStyle = pw.TextStyle(color: muted, fontSize: small);
    final header = <pw.Widget>[
      if (logo != null)
        pw.Container(height: a4 ? 56 : 40, margin: const pw.EdgeInsets.only(bottom: 4), child: pw.Image(logo)),
      pw.Text(
        b.name,
        style: pw.TextStyle(fontSize: base + (a4 ? 6 : 4), fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
      if (b.address != null) pw.Text(b.address!, style: mutedStyle, textAlign: pw.TextAlign.center),
      if (b.cityLine.isNotEmpty) pw.Text(b.cityLine, style: mutedStyle, textAlign: pw.TextAlign.center),
      if (b.phone != null) pw.Text('Ph: ${b.phone}', style: mutedStyle, textAlign: pw.TextAlign.center),
      if (b.gstin != null) pw.Text('GSTIN: ${b.gstin}', style: mutedStyle, textAlign: pw.TextAlign.center),
      if (b.fssai != null) pw.Text('FSSAI: ${b.fssai}', style: mutedStyle, textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 6),
      pw.Text(
        r.draft ? 'TAX INVOICE  (PREVIEW)' : 'TAX INVOICE',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, letterSpacing: 1.2, fontSize: base + 1),
      ),
    ];

    final tableHeader = pw.TextStyle(fontSize: small, fontWeight: pw.FontWeight.bold, color: muted);
    final itemRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.4))),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text('ITEM', style: tableHeader),
          ),
          pw.Text('QTY', style: tableHeader, textAlign: pw.TextAlign.right),
          pw.Text('RATE', style: tableHeader, textAlign: pw.TextAlign.right),
          pw.Text('AMT', style: tableHeader, textAlign: pw.TextAlign.right),
        ],
      ),
      for (final line in r.lines)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(line.name),
                  if (line.note != null)
                    pw.Text(
                      line.note!,
                      style: pw.TextStyle(fontSize: small - 0.5, color: muted),
                    ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(line.qty, textAlign: pw.TextAlign.right),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(Fmt.trim(line.rate), textAlign: pw.TextAlign.right),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(Fmt.amount(line.amount), textAlign: pw.TextAlign.right),
            ),
          ],
        ),
    ];

    String gstHalf(double rate) => Fmt.trim(rate / 2);
    final content = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Column(children: header),
        dashed(top: 8),
        pair('Invoice: ${r.number}', Fmt.invoiceDate(r.date)),
        pair('Table: ${r.table}', 'Paid by: ${r.payment}'),
        if (r.customerLine != null) pair('Customer: ${r.customerLine}', ''),
        dashed(),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.6),
            3: const pw.FlexColumnWidth(2),
          },
          children: itemRows,
        ),
        dashed(),
        pair('Subtotal', Fmt.amount(r.subtotal)),
        if (r.discount > 0) pair('Discount (${Fmt.trim(r.discountPercent)}%)', '-${Fmt.amount(r.discount)}'),
        if (r.gstPool > 0)
          pair(
            'CGST ${gstHalf(r.gstPoolRate)}% + SGST ${gstHalf(r.gstPoolRate)}% (pool table)',
            Fmt.amount(r.gstPool),
            style: pw.TextStyle(color: muted),
          ),
        if (r.gstFood > 0)
          pair(
            'CGST ${gstHalf(r.gstFoodRate)}% + SGST ${gstHalf(r.gstFoodRate)}% (food & drinks)',
            Fmt.amount(r.gstFood),
            style: pw.TextStyle(color: muted),
          ),
        if (r.roundOff.abs() > 0) pair('Round off', Fmt.amount(r.roundOff), style: pw.TextStyle(color: muted)),
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 4),
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.9))),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: base + 1),
                ),
              ),
              pw.Text(
                Fmt.inr(r.total),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: base + (a4 ? 6 : 5)),
              ),
            ],
          ),
        ),
        if (r.cashReceived != null && r.cashReceived! > 0)
          pair(
            'Cash received ${Fmt.inr(r.cashReceived!)}',
            'Change ${Fmt.inr((r.cashReceived! - r.total).clamp(0, double.infinity))}',
            style: pw.TextStyle(fontSize: small, color: muted),
          ),
        if (r.upiUri != null) ...[
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: r.upiUri!,
              width: a4 ? 120 : 100,
              height: a4 ? 120 : 100,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Scan to pay ${Fmt.inr(r.total)} with any UPI app',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
          if (r.upiId != null) pw.Text(r.upiId!, style: mutedStyle, textAlign: pw.TextAlign.center),
        ],
        if (b.footer != null) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            b.footer!,
            style: pw.TextStyle(color: muted),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ],
    );

    final doc = pw.Document(title: r.number, author: b.name, theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat(format),
        theme: theme.copyWith(defaultTextStyle: theme.defaultTextStyle.copyWith(fontSize: base)),
        build: (_) => a4
            ? pw.Align(
                alignment: pw.Alignment.topCenter,
                child: pw.SizedBox(width: 420, child: content),
              )
            : content,
      ),
    );
    return doc.save();
  }
}

/// A plain tabular report (Reports → Print / Save PDF).
class ReportPdf {
  ReportPdf._();

  static Future<Uint8List> build({
    required String title,
    required String subtitle,
    required List<(String, String)> kpis,
    required List<String> headers,
    required List<List<String>> rows,
    Set<int> rightAligned = const {},
  }) async {
    final theme = await PdfFonts.theme();
    final doc = pw.Document(title: title, theme: theme);
    final muted = PdfColor.fromInt(0xFF56625B);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape.copyWith(
          marginLeft: 14 * PdfPageFormat.mm,
          marginRight: 14 * PdfPageFormat.mm,
          marginTop: 12 * PdfPageFormat.mm,
          marginBottom: 12 * PdfPageFormat.mm,
        ),
        theme: theme.copyWith(defaultTextStyle: theme.defaultTextStyle.copyWith(fontSize: 9)),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(color: muted, fontSize: 8)),
        ),
        build: (ctx) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(subtitle, style: pw.TextStyle(color: muted)),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              for (final (label, value) in kpis)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(label, style: pw.TextStyle(color: muted, fontSize: 8)),
                    pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            border: null,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: muted),
            headerDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.3, color: PdfColor.fromInt(0xFFE1E5E0))),
            ),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            headerAlignments: {for (final i in rightAligned) i: pw.Alignment.centerRight},
            cellAlignments: {for (final i in rightAligned) i: pw.Alignment.centerRight},
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return doc.save();
  }
}
