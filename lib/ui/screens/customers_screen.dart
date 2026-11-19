import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'invoices_screen.dart';

/// Regular customers: name, phone and the discount filled in when they are picked at checkout.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _search = '';
  Map<int, CustomerStats> _stats = {};
  int? _revision;

  Future<void> _loadStats() async {
    final stats = await context.read<AppStore>().customerStatsAll();
    if (mounted) setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    if (_revision != store.revision) {
      _revision = store.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
    }

    final q = _search.trim();
    final list = q.isEmpty ? store.customers : store.searchCustomers(q, limit: 1 << 30);

    return PageBody(
      children: [
        PageHeader(
          title: 'Regular customers',
          subtitle: 'Pick a regular at checkout to fill in their name, phone and discount.',
          actions: [
            FilledButton.icon(
              onPressed: () => showCustomerDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add customer'),
            ),
          ],
        ),
        CbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 360,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search name or phone',
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CbTable(
                minWidth: 760,
                empty: store.customers.isEmpty
                    ? 'No regulars yet. Add one here, or tap "Save as regular" at checkout.'
                    : 'No customers found.',
                onTapRow: (i) => showCustomerDialog(context, customer: list[i]),
                columns: const [
                  Col('Name', flex: 4),
                  Col('Phone', flex: 3),
                  Col('Discount', flex: 2, right: true),
                  Col('Visits', flex: 2, right: true),
                  Col('Spent', flex: 3, right: true),
                  Col('Last visit', flex: 3, right: true),
                ],
                rows: [
                  for (final c in list)
                    [
                      Text(
                        c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      NumText(c.phone ?? '–', color: c.phone == null ? cb.muted : null),
                      c.discountPercent > 0
                          ? CbBadge('${Fmt.trim(c.discountPercent)}% off', tone: Tone.green)
                          : Text('–', style: TextStyle(color: cb.muted)),
                      NumText(Fmt.count(_stats[c.id]?.visits ?? 0)),
                      NumText(Fmt.inr(_stats[c.id]?.spend ?? 0), bold: true),
                      NumText(
                        _stats[c.id]?.lastVisit == null ? '–' : Fmt.date(_stats[c.id]!.lastVisit!),
                        color: _stats[c.id]?.lastVisit == null ? cb.muted : null,
                      ),
                    ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Add or edit a regular. Returns the saved customer, or null if cancelled or deleted.
Future<Customer?> showCustomerDialog(BuildContext context, {Customer? customer, String? name, String? phone}) {
  return showDialog<Customer>(
    context: context,
    builder: (_) => _CustomerDialog(customer: customer, name: name, phone: phone),
  );
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.customer, this.name, this.phone});

  final Customer? customer;
  final String? name;
  final String? phone;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name ?? widget.name);
  late final _phone = TextEditingController(text: widget.customer?.phone ?? widget.phone);
  late final _discount = TextEditingController(
    text: widget.customer == null || widget.customer!.discountPercent == 0
        ? ''
        : Fmt.trim(widget.customer!.discountPercent),
  );
  late final _notes = TextEditingController(text: widget.customer?.notes);
  Future<List<Invoice>>? _invoices;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) _invoices = context.read<AppStore>().customerInvoices(widget.customer!, limit: 20);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _discount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final store = context.read<AppStore>();
    final c = widget.customer ?? Customer(name: '');
    final before = c.toRow();
    c
      ..name = _name.text
      ..phone = _phone.text
      ..discountPercent = double.tryParse(_discount.text) ?? 0
      ..notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    try {
      final saved = await store.saveCustomer(c);
      if (mounted) Navigator.pop(context, saved);
    } on CueBillException catch (e) {
      // Put the in-memory record back as it was, so a failed save changes nothing.
      if (widget.customer != null) {
        final old = Customer.fromRow(before);
        c
          ..name = old.name
          ..phone = old.phone
          ..discountPercent = old.discountPercent
          ..notes = old.notes;
      }
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.customer != null;
    final store = context.read<AppStore>();
    return AlertDialog(
      title: Text(editing ? widget.customer!.name : 'Add customer', style: CbText.cardTitle(context)),
      content: SizedBox(
        width: editing ? 640 : 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldRow(
                  breakpoint: 360,
                  children: [
                    FieldLabel(
                      'Name',
                      child: TextFormField(
                        controller: _name,
                        autofocus: !editing && (widget.name ?? '').isEmpty,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                      ),
                    ),
                    FieldLabel(
                      'Phone',
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FieldLabel(
                  'Regular discount',
                  helper: Text(
                    'Filled in at checkout. You can still change it on the bill.',
                    style: CbText.muted(context, 12.5),
                  ),
                  child: SizedBox(
                    width: 140,
                    child: TextFormField(
                      controller: _discount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      decoration: const InputDecoration(hintText: '0', suffixText: '%'),
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) > 100 ? 'Up to 100%' : null,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FieldLabel('Notes (optional)', child: TextFormField(controller: _notes, maxLines: 2, minLines: 1)),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: context.cb.red, fontWeight: FontWeight.w600),
                  ),
                ],
                if (_invoices != null) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Recent bills',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.cb.ink),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<List<Invoice>>(
                    future: _invoices,
                    builder: (context, snap) => InvoiceTable(
                      invoices: snap.data ?? const [],
                      empty: snap.hasData ? 'No bills yet.' : 'Loading…',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.cb.red),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Delete ${widget.customer!.name}?',
                message: 'They are removed from the list of regulars. Their past invoices are kept.',
                confirm: 'Delete',
                danger: true,
              );
              if (!ok || !context.mounted) return;
              await store.deleteCustomer(widget.customer!);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
