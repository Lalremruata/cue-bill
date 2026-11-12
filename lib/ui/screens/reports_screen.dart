import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/analytics.dart';
import '../../services/excel_export.dart';
import '../../services/receipt_pdf.dart';
import '../files.dart';
import '../theme.dart';
import '../widgets.dart';
import 'invoices_screen.dart';

enum _Tab { sales, items, daily, invoices }

extension on _Tab {
  String get label => switch (this) {
    _Tab.sales => 'Item sales',
    _Tab.items => 'Item performance',
    _Tab.daily => 'Daily sales',
    _Tab.invoices => 'Invoices',
  };
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _from;
  late DateTime _to;
  int? _quick = 30;
  String? _payment;
  _Tab _tab = _Tab.sales;
  String? _type;
  String _sort = 'profit';
  Future<SalesAnalytics>? _future;
  Object? _loadedFor;

  @override
  void initState() {
    super.initState();
    final range = SalesAnalytics.lastDays(30);
    _from = range.$1;
    _to = range.$2;
  }

  void _setQuick(int days) => setState(() {
    _quick = days;
    final range = SalesAnalytics.lastDays(days);
    _from = range.$1;
    _to = range.$2;
  });

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _quick = null;
      if (from) {
        _from = startOfDay(picked);
        if (_from.isAfter(_to)) _to = endOfDay(picked);
      } else {
        _to = endOfDay(picked);
        if (_to.isBefore(_from)) _from = startOfDay(picked);
      }
    });
  }

  static const _types = {null: 'All', 'pool': 'Pool table', 'food': 'Food', 'snacks': 'Snacks', 'drinks': 'Drinks'};

  String get _rangeLabel =>
      '${Fmt.dateRange(_from, _to)}'
      '${_payment == null ? '' : ' · ${paymentMethods[_payment]} only'}';

  /// Filters that narrow the item sales list, e.g. `Drinks only`, `UPI only`.
  List<String> get _salesFilters => [
    if (_type != null) '${_types[_type]} only',
    if (_payment != null) '${paymentMethods[_payment]} only',
  ];

  String get _fileStem => 'cuebill-${_tab.name}-${Fmt.isoDate(_from)}-to-${Fmt.isoDate(_to)}';

  Future<void> _exportExcel(SalesAnalytics a) async {
    final bytes = switch (_tab) {
      _Tab.sales => ExcelExport.sales(
        a.sales(categoryType: _type),
        heading: ExcelExport.salesHeading(
          shop: context.read<AppStore>().settings.name,
          from: _from,
          to: _to,
          filters: _salesFilters,
        ),
      ),
      _Tab.items => ExcelExport.items(a.items(categoryType: _type, sort: _sort), _from, _to),
      _Tab.daily => ExcelExport.daily(a.daily().reversed.toList()),
      _Tab.invoices => ExcelExport.invoices(a.invoices),
    };
    await Files.save(context, bytes: bytes, fileName: '$_fileStem.xlsx', extension: 'xlsx');
  }

  Future<void> _printPdf(SalesAnalytics a) async {
    final s = a.summary();
    final sales = a.sales(categoryType: _type);
    final kpis = _tab == _Tab.sales
        ? [
            ('Items sold', Fmt.count(_itemsSold(sales))),
            if (sales.any((l) => l.isPool)) ('Pool time', sales.firstWhere((l) => l.isPool).qtyLabel),
            ('Amount', Fmt.inr(_salesTotal(sales))),
            ('Invoices', '${s.invoices}'),
          ]
        : [
            ('Collected (incl. GST)', Fmt.inr(s.collected)),
            ('Revenue (ex GST)', Fmt.inr(s.revenue)),
            ('Cost', Fmt.inr(s.cost)),
            ('Gross profit', Fmt.inr(s.profit)),
            ('Margin', Fmt.percent(s.margin)),
            ('Invoices', '${s.invoices}'),
          ];
    final (headers, rows, right) = switch (_tab) {
      _Tab.sales => (
        ['Item', 'Category', 'Qty', 'Amount'],
        [
          for (final l in sales) [l.name, l.category ?? '', l.qtyLabel, Fmt.inr(l.amount)],
          if (sales.isNotEmpty) ['Total', '', '${_itemsSold(sales)} items', Fmt.inr(_salesTotal(sales))],
        ],
        {2, 3},
      ),
      _Tab.items => (
        ['Item', 'Category', 'Qty', 'Revenue', 'Cost', 'Profit', 'Margin', 'Rating'],
        [
          for (final r in a.items(categoryType: _type, sort: _sort))
            [
              r.name,
              r.category ?? '',
              r.qtyLabel,
              Fmt.inr(r.revenue),
              Fmt.inr(r.cost),
              Fmt.inr(r.profit),
              Fmt.percent(r.margin, 0),
              r.rating.label,
            ],
        ],
        {2, 3, 4, 5, 6},
      ),
      _Tab.daily => (
        ['Date', 'Invoices', 'Pool h', 'Pool', 'Food', 'Drinks', 'Snacks', 'Collected', 'Profit', 'Margin'],
        [
          for (final r in a.daily().reversed)
            [
              Fmt.date(r.date),
              '${r.invoices}',
              Fmt.trim(r.poolHours, 1),
              Fmt.inr(r.pool),
              Fmt.inr(r.food),
              Fmt.inr(r.drinks),
              Fmt.inr(r.snacks),
              Fmt.inr(r.collected),
              Fmt.inr(r.profit),
              Fmt.percent(r.margin, 0),
            ],
        ],
        {1, 2, 3, 4, 5, 6, 7, 8, 9},
      ),
      _Tab.invoices => (
        ['Invoice', 'Date & time', 'Table', 'Paid by', 'Amount'],
        [
          for (final i in a.invoices)
            [i.number, Fmt.invoiceDate(i.paidAt), i.tableName, i.paymentLabel, Fmt.inr(i.total)],
        ],
        {4},
      ),
    };
    final bytes = await ReportPdf.build(
      title: 'Sales report · ${_tab.label}${_tab == _Tab.sales && _type != null ? ' · ${_types[_type]} only' : ''}',
      subtitle: '${context.read<AppStore>().settings.name} · $_rangeLabel',
      kpis: kpis,
      headers: headers,
      rows: rows,
      rightAligned: right,
    );
    if (mounted) await Files.printPdf(context, bytes, _fileStem);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final key = (_from, _to, _payment, store.revision);
    if (_loadedFor != key) {
      _loadedFor = key;
      _future = store.analytics(_from, _to, payment: _payment);
    }

    return FutureBuilder<SalesAnalytics>(
      future: _future,
      builder: (context, snap) {
        final a = snap.data;
        return PageBody(
          children: [
            PageHeader(
              title: 'Sales reports',
              subtitle: 'Find what sells, what earns, and what to fix.',
              actions: [
                OutlinedButton.icon(
                  onPressed: a == null ? null : () => _printPdf(a),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print / Save PDF'),
                ),
                FilledButton.icon(
                  onPressed: a == null ? null : () => _exportExcel(a),
                  icon: const Icon(Icons.grid_on_outlined, size: 18),
                  label: const Text('Export to Excel'),
                ),
              ],
            ),
            _filters(context),
            const SizedBox(height: 16),
            if (a == null)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _kpis(a.summary()),
              const SizedBox(height: 16),
              _tabs(context, a),
            ],
          ],
        );
      },
    );
  }

  Widget _filters(BuildContext context) {
    final cb = context.cb;
    Widget dateButton(String label, DateTime value, bool from) => FieldLabel(
      label,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(160, 46),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, fontFamily: 'Inter'),
        ),
        onPressed: () => _pickDate(from),
        icon: Icon(Icons.calendar_today_outlined, size: 16, color: cb.muted),
        label: Text(Fmt.date(value)),
      ),
    );

    return CbCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          dateButton('From', _from, true),
          dateButton('To', _to, false),
          FieldLabel(
            'Payment',
            child: SizedBox(
              width: 170,
              child: DropdownButtonFormField<String?>(
                value: _payment,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All methods')),
                  for (final e in paymentMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _payment = v),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (d, label) in [(1, 'Today'), (7, '7 days'), (30, '30 days'), (90, '90 days')])
                CbChip(label: label, selected: _quick == d, onTap: () => _setQuick(d)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpis(Summary s) => ResponsiveGrid(
    minWidth: 170,
    maxColumns: 6,
    children: [
      KpiTile(label: 'Collected (incl. GST)', value: Fmt.inr(s.collected), valueSize: 24),
      KpiTile(label: 'Revenue (ex GST)', value: Fmt.inr(s.revenue), valueSize: 24),
      KpiTile(label: 'Cost', value: Fmt.inr(s.cost), valueSize: 24),
      KpiTile(label: 'Gross profit', value: Fmt.inr(s.profit), valueSize: 24),
      KpiTile(label: 'Margin', value: Fmt.percent(s.margin), valueSize: 24),
      KpiTile(label: 'Invoices', value: Fmt.count(s.invoices), valueSize: 24),
    ],
  );

  Widget _tabs(BuildContext context, SalesAnalytics a) {
    final cb = context.cb;
    return CbCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cb.line)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in _Tab.values)
                    Semantics(
                      selected: t == _tab,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => _tab = t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: t == _tab ? cb.green : Colors.transparent, width: 2.5),
                            ),
                          ),
                          child: Text(
                            t.label,
                            style: TextStyle(fontWeight: FontWeight.w600, color: t == _tab ? cb.greenText : cb.muted),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: switch (_tab) {
              _Tab.sales => _salesTab(context, a),
              _Tab.items => _itemsTab(context, a),
              _Tab.daily => _dailyTab(context, a),
              _Tab.invoices => InvoiceTable(invoices: a.invoices, empty: 'No invoices in this period.'),
            },
          ),
        ],
      ),
    );
  }

  static int _itemsSold(List<SalesLine> lines) => lines.where((l) => !l.isPool).fold(0, (s, l) => s + l.qty.toInt());

  static double _salesTotal(List<SalesLine> lines) => lines.fold(0.0, (s, l) => s + l.amount);

  Widget _typeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in _types.entries)
          CbChip(label: e.value, selected: _type == e.key, onTap: () => setState(() => _type = e.key)),
      ],
    );
  }

  Widget _salesTab(BuildContext context, SalesAnalytics a) {
    final lines = a.sales(categoryType: _type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _typeChips(),
        const SizedBox(height: 12),
        Text(
          [Fmt.dateRange(_from, _to), ..._salesFilters].join(' · '),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: context.cb.ink),
        ),
        const SizedBox(height: 2),
        Text('Amounts are at menu price, before bill discounts and GST.', style: CbText.muted(context)),
        const SizedBox(height: 12),
        CbTable(
          minWidth: 560,
          rowHeight: 44,
          empty: 'Nothing sold in this period.',
          columns: const [
            Col('Item', flex: 5),
            Col('Category', flex: 3),
            Col('Qty', flex: 2, right: true),
            Col('Amount', flex: 3, right: true),
          ],
          rows: [
            for (final l in lines)
              [
                Text(l.name, overflow: TextOverflow.ellipsis),
                Text(l.category ?? '', style: CbText.muted(context, 14)),
                NumText(l.qtyLabel),
                NumText(Fmt.inr(l.amount)),
              ],
            if (lines.isNotEmpty)
              [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(),
                NumText('${_itemsSold(lines)} items', bold: true),
                NumText(Fmt.inr(_salesTotal(lines)), bold: true),
              ],
          ],
        ),
      ],
    );
  }

  Widget _itemsTab(BuildContext context, SalesAnalytics a) {
    final rows = a.items(categoryType: _type, sort: _sort);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _typeChips(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Rating:', style: CbText.label(context)),
                const CbBadge('Star', tone: Tone.green),
                Text('high sales, margin ≥ 60%', style: CbText.muted(context)),
                const SizedBox(width: 4),
                const CbBadge('Steady'),
                Text('OK on both', style: CbText.muted(context)),
                const SizedBox(width: 4),
                const CbBadge('Slow', tone: Tone.amber),
                Text('few sold', style: CbText.muted(context)),
                const SizedBox(width: 4),
                const CbBadge('Loss risk', tone: Tone.red),
                Text('margin under 30%', style: CbText.muted(context)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sort by', style: CbText.muted(context)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    value: _sort,
                    isExpanded: true,
                    items: [for (final e in itemSorts.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _sort = v ?? 'profit'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        CbTable(
          minWidth: 900,
          empty: 'No items.',
          columns: const [
            Col('Item', flex: 5),
            Col('Category', flex: 3),
            Col('Qty', flex: 2, right: true),
            Col('Revenue', flex: 3, right: true),
            Col('Cost', flex: 3, right: true),
            Col('Profit', flex: 3, right: true),
            Col('Margin', flex: 4),
            Col('Rating', flex: 2),
          ],
          rows: [
            for (final r in rows)
              [
                Text(r.name, overflow: TextOverflow.ellipsis),
                Text(r.category ?? '', style: CbText.muted(context, 14)),
                NumText(r.qtyLabel),
                NumText(Fmt.inr(r.revenue)),
                NumText(Fmt.inr(r.cost), color: context.cb.muted),
                NumText(Fmt.inr(r.profit), bold: true),
                Row(
                  children: [
                    Expanded(child: MarginBar(r.margin, width: double.infinity)),
                    const SizedBox(width: 10),
                    SizedBox(width: 40, child: NumText(Fmt.percent(r.margin, 0), size: 13)),
                  ],
                ),
                CbBadge(r.rating.label, tone: ratingTone(r.rating)),
              ],
          ],
        ),
      ],
    );
  }

  Widget _dailyTab(BuildContext context, SalesAnalytics a) {
    final rows = a.daily().reversed.toList();
    return CbTable(
      minWidth: 1000,
      empty: 'No days in range.',
      columns: const [
        Col('Date', flex: 3),
        Col('Invoices', flex: 2, right: true),
        Col('Pool h', flex: 2, right: true),
        Col('Pool', flex: 3, right: true),
        Col('Food', flex: 3, right: true),
        Col('Drinks', flex: 3, right: true),
        Col('Snacks', flex: 3, right: true),
        Col('Collected', flex: 3, right: true),
        Col('Profit', flex: 3, right: true),
        Col('Margin', flex: 2, right: true),
      ],
      rows: [
        for (final r in rows)
          [
            Text('${Fmt.shortDate(r.date)}, ${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][r.date.weekday - 1]}'),
            NumText('${r.invoices}'),
            NumText(Fmt.trim(r.poolHours, 1)),
            NumText(Fmt.inr(r.pool)),
            NumText(Fmt.inr(r.food)),
            NumText(Fmt.inr(r.drinks)),
            NumText(Fmt.inr(r.snacks)),
            NumText(Fmt.inr(r.collected)),
            NumText(Fmt.inr(r.profit), bold: true),
            NumText(Fmt.percent(r.margin, 0), color: toneColor(context, marginTone(r.margin))),
          ],
      ],
    );
  }
}
