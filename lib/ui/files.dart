import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/receipt.dart';
import '../services/receipt_pdf.dart';
import 'widgets.dart';

/// Save, print and share helpers shared by every screen.
class Files {
  Files._();

  /// Asks where to save and writes the file. Returns false if the user cancelled.
  static Future<bool> save(
    BuildContext context, {
    required List<int> bytes,
    required String fileName,
    required String extension,
    String? done,
  }) async {
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save $fileName',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: Uint8List.fromList(bytes),
      );
      if (path == null) return false;
      if (context.mounted) toast(context, done ?? 'Saved $fileName');
      return true;
    } catch (e) {
      if (context.mounted) toast(context, 'Could not save the file: $e', error: true);
      return false;
    }
  }

  static Future<void> printReceipt(BuildContext context, ReceiptData receipt, ReceiptFormat format) async {
    try {
      await Printing.layoutPdf(
        name: receipt.number,
        format: ReceiptPdf.pageFormat(format),
        onLayout: (_) => ReceiptPdf.build(receipt, format),
      );
    } catch (e) {
      if (context.mounted) toast(context, 'Could not print: $e', error: true);
    }
  }

  static Future<void> saveReceiptPdf(BuildContext context, ReceiptData receipt, ReceiptFormat format) async {
    final bytes = await ReceiptPdf.build(receipt, format);
    if (!context.mounted) return;
    await save(context, bytes: bytes, fileName: '${receipt.number}.pdf', extension: 'pdf');
  }

  static Future<void> printPdf(BuildContext context, Uint8List bytes, String name) async {
    try {
      await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
    } catch (e) {
      if (context.mounted) toast(context, 'Could not print: $e', error: true);
    }
  }
}
