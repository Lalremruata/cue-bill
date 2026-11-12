import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/checkout.dart';
import '../../services/receipt.dart';
import '../files.dart';
import '../receipt_view.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.tableId});

  final int tableId;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _payment = 'upi';
  double _discount = 0;
  final _customDiscount = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _cash = TextEditingController();
  ReceiptFormat _format = ReceiptFormat.roll80;
  Invoice? _invoice;
  bool _saving = false;

  @override
  void dispose() {
    _customDiscount.dispose();
    _name.dispose();
    _phone.dispose();
    _cash.dispose();
    super.dispose();
  }

  double? get _cashReceived => double.tryParse(_cash.text.trim());

  CheckoutOptions get _options => CheckoutOptions(
    paymentMethod: _payment,
    discountPercent: _discount,
    customerName: _name.text,
    customerPhone: _phone.text,
    cashReceived: _payment == 'cash' ? _cashReceived : null,
  );

  Future<void> _complete(RestaurantTable table, double total) async {
    final cash = _cashReceived;
    if (_payment == 'cash' && cash != null && cash < total) {
      toast(context, 'Cash received is less than the total.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final invoice = await context.read<AppStore>().completeSale(table, _options);
      if (!mounted) return;
      setState(() => _invoice = invoice);
      toast(context, '${invoice.number} saved');
    } on CueBillException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final nav = context.read<Nav>();
    final table = store.tableById(widget.tableId);
    final invoice = _invoice;

    final back = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
        onPressed: nav.closeCheckout,
        icon: const Icon(Icons.arrow_back, size: 16),
        label: Text(invoice != null ? 'Back to tables' : 'Back to ${table?.name ?? 'tables'}'),
      ),
    );

    if (invoice == null && (table == null || store.sessionFor(table) == null)) {
      return PageBody(
        children: [
          PageHeader(title: 'Checkout', above: back),
          CbCard(child: Text('This table has no open order.', style: CbText.muted(context, 14))),
        ],
      );
    }

    late final ReceiptData receipt;
    double total;
    if (invoice != null) {
      receipt = ReceiptData.fromInvoice(invoice);
      total = invoice.total;
    } else {
      final calc = store.calcFor(table!, discountPercent: _discount)!;
      receipt = Checkout.preview(settings: store.settings, calc: calc, tableName: table.name, options: _options);
      total = calc.totals.total;
    }

    final actions = invoice == null
        ? [
            FilledButton(
              onPressed: _saving ? null : () => _complete(table!, total),
              child: Text(_saving ? 'Saving…' : 'Complete sale'),
            ),
          ]
        : <Widget>[];

    final left = invoice == null ? _form(context, total) : _done(context, invoice, receipt);
    final right = ReceiptTray(
      child: ReceiptView(data: receipt, format: _format),
    );

    return PageBody(
      children: [
        PageHeader(title: 'Checkout', above: back, actions: actions),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 980) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: 24),
                  Expanded(flex: 6, child: right),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 20), right],
            );
          },
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.cb.ink),
    ),
  );

  Widget _form(BuildContext context, double total) {
    final cb = context.cb;
    final presets = [0.0, 5.0, 10.0, 15.0];
    final cash = _cashReceived;

    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('Payment method'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4.4,
            children: [
              for (final e in paymentMethods.entries)
                PayButton(label: e.value, selected: _payment == e.key, onTap: () => setState(() => _payment = e.key)),
            ],
          ),
          const SizedBox(height: 22),
          _section('Discount'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in presets)
                CbChip(
                  label: p == 0 ? 'None' : '${p.toInt()}%',
                  selected: _discount == p && _customDiscount.text.isEmpty,
                  onTap: () => setState(() {
                    _discount = p;
                    _customDiscount.clear();
                  }),
                ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _customDiscount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(hintText: 'Custom', suffixText: '%'),
                  onChanged: (v) => setState(() => _discount = (double.tryParse(v) ?? 0).clamp(0, 100).toDouble()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          FieldRow(
            breakpoint: 400,
            children: [
              FieldLabel(
                'Customer name (optional)',
                child: TextField(controller: _name, onChanged: (_) => setState(() {})),
              ),
              FieldLabel(
                'Phone (optional)',
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (_payment == 'cash') ...[
            const SizedBox(height: 16),
            FieldLabel(
              'Cash received',
              helper: cash == null
                  ? null
                  : Text(
                      cash >= total ? 'Change to return: ${Fmt.inr(cash - total)}' : '${Fmt.inr(total - cash)} short',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cash >= total ? cb.greenText : cb.red,
                      ),
                    ),
              child: TextField(
                controller: _cash,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(prefixText: '₹ '),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _section('Invoice format'),
          Align(
            alignment: Alignment.centerLeft,
            child: Segmented<ReceiptFormat>(
              options: {for (final f in ReceiptFormat.values) f: f.label},
              value: _format,
              onChanged: (f) => setState(() => _format = f),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '80 mm prints on a thermal receipt printer. A4 is for customers who need a full GST tax invoice.',
            style: CbText.muted(context, 13.5).copyWith(height: 1.45),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: cb.soft,
              border: Border.all(color: cb.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Name, address, GSTIN and UPI ID come from Business settings.',
                    style: CbText.muted(context, 13.5),
                  ),
                ),
                TextButton(onPressed: () => context.read<Nav>().go(Section.settings), child: const Text('Edit')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: cb.dark, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Amount due',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                      ),
                    ),
                    Text(paymentMethods[_payment]!, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(Fmt.inr(total), style: CbText.big(context, size: 36, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : () => _complete(context.read<AppStore>().tableById(widget.tableId)!, total),
            child: Text(_saving ? 'Saving…' : 'Complete sale · ${Fmt.inr(total)}'),
          ),
        ],
      ),
    );
  }

  Widget _done(BuildContext context, Invoice invoice, ReceiptData receipt) {
    final cb = context.cb;
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: cb.greenSoft, shape: BoxShape.circle),
                child: Icon(Icons.check, color: cb.greenText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${invoice.number} saved', style: CbText.cardTitle(context)),
                    Text(
                      '${Fmt.inr(invoice.total)} · ${invoice.paymentLabel} · ${invoice.tableName} is free again.',
                      style: CbText.muted(context, 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => Files.printReceipt(context, receipt, ReceiptFormat.roll80),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print 80 mm'),
              ),
              OutlinedButton.icon(
                onPressed: () => Files.printReceipt(context, receipt, ReceiptFormat.a4),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print A4'),
              ),
              OutlinedButton.icon(
                onPressed: () => Files.saveReceiptPdf(context, receipt, _format),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Save as PDF'),
              ),
              OutlinedButton(onPressed: context.read<Nav>().closeCheckout, child: const Text('Back to tables')),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Segmented<ReceiptFormat>(
              options: {for (final f in ReceiptFormat.values) f: f.label},
              value: _format,
              onChanged: (f) => setState(() => _format = f),
            ),
          ),
        ],
      ),
    );
  }
}
