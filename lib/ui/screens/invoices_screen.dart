import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/excel_export.dart';
import '../../services/receipt.dart';
import '../files.dart';
import '../receipt_view.dart';
import '../theme.dart';
import '../widgets.dart';

/// Reprint an invoice: receipt preview with Print 80 mm, Print A4 and Save as PDF.
Future<void> showReceiptDialog(BuildContext context, Invoice invoice) {
  return showDialog(
    context: context,
    builder: (_) => _ReceiptDialog(invoice: invoice),
  );
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({required this.invoice});

  final Invoice invoice;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  ReceiptFormat _format = ReceiptFormat.roll80;

  @override
  Widget build(BuildContext context) {
    final receipt = ReceiptData.fromInvoice(widget.invoice);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height - 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.invoice.number, style: CbText.cardTitle(context))),
                  Segmented<ReceiptFormat>(
                    options: const {ReceiptFormat.roll80: '80 mm', ReceiptFormat.a4: 'A4'},
                    value: _format,
                    onChanged: (f) => setState(() => _format = f),
                  ),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ReceiptTray(
                  child: ReceiptView(data: receipt, format: _format),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Files.saveReceiptPdf(context, receipt, _format),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Save as PDF'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Files.printReceipt(context, receipt, _format),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(_format == ReceiptFormat.a4 ? 'Print A4' : 'Print 80 mm'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every sale, newest first. Invoices are GST records and cannot be edited or deleted.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  static const _page = 50;
  final List<Invoice> _rows = [];
  String _search = '';
  bool _loading = false;
  bool _done = false;
  int? _revision;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    _rows.clear();
    _done = false;
    await _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    final store = context.read<AppStore>();
    final next = await store.recentInvoices(limit: _page, offset: _rows.length, search: _search);
    if (!mounted) return;
    setState(() {
      _rows.addAll(next);
      _done = next.length < _page;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (_revision != store.revision) {
      _revision = store.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }

    return PageBody(
      children: [
        PageHeader(
          title: 'Invoices',
          subtitle:
              '${store.invoiceCount} saved on this device. Invoices are GST records, so they cannot be edited or deleted.',
          actions: [
            OutlinedButton.icon(
              onPressed: _rows.isEmpty
                  ? null
                  : () => Files.save(
                      context,
                      bytes: ExcelExport.invoices(_rows),
                      fileName: 'cuebill-invoices-${Fmt.isoDate(DateTime.now())}.xlsx',
                      extension: 'xlsx',
                    ),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Export shown to Excel'),
            ),
          ],
        ),
        CbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search number, table, customer or phone',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      _search = v;
                      _reload();
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              InvoiceTable(invoices: _rows, empty: _loading ? 'Loading…' : 'No invoices found.'),
              if (!_done && _rows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: _loading ? null : _more,
                      child: Text(_loading ? 'Loading…' : 'Load more'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Number, date and time, table, paid by, amount, with Receipt, A4 and PDF actions.
class InvoiceTable extends StatelessWidget {
  const InvoiceTable({super.key, required this.invoices, this.empty = 'No invoices.'});

  final List<Invoice> invoices;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return CbTable(
      minWidth: 860,
      rowHeight: 56,
      empty: empty,
      onTapRow: (i) => showReceiptDialog(context, invoices[i]),
      columns: const [
        Col('Invoice', flex: 3),
        Col('Date & time', flex: 3),
        Col('Table', flex: 3),
        Col('Customer', flex: 3),
        Col('Paid by', flex: 2),
        Col('Amount', flex: 2, right: true),
        Col('', width: 176, right: true),
      ],
      rows: [
        for (final inv in invoices)
          [
            NumText(inv.number, bold: true, size: 13.5),
            NumText('${Fmt.shortDate(inv.paidAt)}, ${Fmt.time(inv.paidAt)}', size: 13.5),
            Text(inv.tableName, overflow: TextOverflow.ellipsis),
            Text(
              inv.customerName ?? '–',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: inv.customerName == null ? cb.muted : cb.ink),
            ),
            Text(inv.paymentLabel),
            NumText(Fmt.inr(inv.total), bold: true),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Print 80 mm receipt',
                  onPressed: () => Files.printReceipt(context, ReceiptData.fromInvoice(inv), ReceiptFormat.roll80),
                  icon: const Icon(Icons.receipt_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Print A4 invoice',
                  onPressed: () => Files.printReceipt(context, ReceiptData.fromInvoice(inv), ReceiptFormat.a4),
                  icon: const Icon(Icons.description_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Save as PDF',
                  onPressed: () => Files.saveReceiptPdf(context, ReceiptData.fromInvoice(inv), ReceiptFormat.a4),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                ),
              ],
            ),
          ],
      ],
    );
  }
}
