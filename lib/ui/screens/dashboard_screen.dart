import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/billing.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/analytics.dart';
import '../../services/excel_export.dart';
import '../files.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'invoices_screen.dart';

class _DashData {
  _DashData(this.current, this.previous, this.recent);

  final SalesAnalytics current;
  final SalesAnalytics previous;
  final List<Invoice> recent;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _days = 7;
  Future<_DashData>? _future;
  (int, int)? _loadedFor;

  Future<_DashData> _load(AppStore store) async {
    final (from, to) = SalesAnalytics.lastDays(_days);
    final current = await store.analytics(from, to);
    final (pf, pt) = current.previousPeriod();
    final previous = await store.analytics(pf, pt);
    final recent = await store.recentInvoices(limit: 5);
    return _DashData(current, previous, recent);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final key = (_days, store.revision);
    if (_loadedFor != key) {
      _loadedFor = key;
      _future = _load(store);
    }

    final periodLabel = _days == 1 ? 'yesterday' : 'previous $_days days';

    return FutureBuilder<_DashData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        return PageBody(
          children: [
            PageHeader(
              title: 'Dashboard',
              subtitle: '${Fmt.longDate(DateTime.now())} · comparing with $periodLabel',
              actions: [
                Segmented<int>(
                  options: const {1: 'Today', 7: '7 days', 30: '30 days', 90: '90 days'},
                  value: _days,
                  onChanged: (d) => setState(() => _days = d),
                ),
                OutlinedButton.icon(
                  onPressed: data == null
                      ? null
                      : () => Files.save(
                          context,
                          bytes: ExcelExport.dashboard(
                            data.current.daily(),
                            data.current.sales(),
                            data.current.dates,
                            salesHeading: ExcelExport.salesHeading(
                              shop: store.settings.name,
                              from: data.current.from,
                              to: data.current.to,
                            ),
                          ),
                          fileName:
                              'cuebill-sales-${Fmt.isoDate(data.current.from)}-to-${Fmt.isoDate(data.current.to)}.xlsx',
                          extension: 'xlsx',
                        ),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Export Excel'),
                ),
                FilledButton.icon(
                  onPressed: () => context.read<Nav>().go(Section.pos),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New order'),
                ),
              ],
            ),
            if (data == null)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _Kpis(data: data, periodLabel: periodLabel),
              const SizedBox(height: 16),
              _TwoUp(
                ratio: (3, 2),
                left: _RevenueCard(rows: data.current.daily()),
                right: _ProfitMixCard(mix: data.current.mix()),
              ),
              const SizedBox(height: 16),
              _ItemCards(items: data.current.items()),
              const SizedBox(height: 16),
              _TwoUp(
                ratio: (1, 1),
                left: _BusyHoursCard(hours: data.current.busyHours(), days: _days),
                right: _RecentInvoicesCard(invoices: data.recent),
              ),
              if (store.invoiceCount == 0) ...[
                const SizedBox(height: 16),
                CbCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'No sales yet. Complete a sale on Tables & Orders, or load sample sales in Settings → Data & backup to try the dashboard.',
                          style: CbText.muted(context, 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => context.read<Nav>().go(Section.settings),
                        child: const Text('Open settings'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// Two cards side by side on wide screens, stacked on narrow ones.
class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.left, required this.right, required this.ratio});

  final Widget left;
  final Widget right;
  final (int, int) ratio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 16), right],
          );
        }
        // No IntrinsicHeight here: the cards contain LayoutBuilders, which cannot report intrinsic sizes.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: ratio.$1, child: left),
            const SizedBox(width: 16),
            Expanded(flex: ratio.$2, child: right),
          ],
        );
      },
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.data, required this.periodLabel});

  final _DashData data;
  final String periodLabel;

  Widget? _pct(double now, double before) {
    if (before <= 0) return null;
    final change = (now - before) / before * 100;
    return DeltaPill(text: '${change.abs().toStringAsFixed(1)}%', up: change >= 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = data.current.summary();
    final p = data.previous.summary();
    final marginDelta = s.margin - p.margin;
    return ResponsiveGrid(
      minWidth: 230,
      maxColumns: 4,
      children: [
        KpiTile(
          label: 'Sales',
          value: Fmt.inr(s.revenue),
          delta: _pct(s.revenue, p.revenue),
          note: p.revenue > 0 ? 'vs $periodLabel' : 'ex GST · ${s.invoices} invoices',
        ),
        KpiTile(
          label: 'Gross profit',
          value: Fmt.inr(s.profit),
          delta: _pct(s.profit, p.profit),
          note: 'after item costs',
        ),
        KpiTile(
          label: 'Profit margin',
          value: Fmt.percent(s.margin),
          delta: p.revenue > 0
              ? DeltaPill(text: '${marginDelta.abs().toStringAsFixed(1)} pts', up: marginDelta >= 0)
              : null,
          note: 'of sales',
        ),
        // Paid hours plus tables playing now, so an occupied table never shows 0 h.
        Ticking(
          builder: (context, now) {
            final store = context.read<AppStore>();
            final liveMinutes = store.livePoolSeconds(now) / 60;
            final hours = roundTo(s.poolHours + liveMinutes / 60, 1);
            final playing = store.poolTablesPlaying;
            final occupancy = Fmt.trim(data.current.poolOccupancy(liveMinutes: liveMinutes), 0);
            return KpiTile(
              label: 'Pool table hours',
              value: '${Fmt.trim(hours, 1)} h',
              delta: _pct(hours, p.poolHours),
              note: playing > 0
                  ? '$playing ${playing == 1 ? 'table' : 'tables'} playing now · $occupancy% occupancy'
                  : '$occupancy% occupancy',
            );
          },
        ),
      ],
    );
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.rows});

  final List<DailyRow> rows;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final maxTotal = rows.fold<double>(0, (m, r) => math.max(m, r.pool + r.food + r.drinks + r.snacks));
    const chartHeight = 230.0;
    final labelEvery = (rows.length / 14).ceil().clamp(1, 99);

    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            'Revenue by day',
            trailing: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: const [
                LegendItem(label: 'Pool table', color: SeriesColors.pool),
                LegendItem(label: 'Food', color: SeriesColors.food),
                LegendItem(label: 'Drinks', color: SeriesColors.drinks),
                LegendItem(label: 'Snacks', color: SeriesColors.snacks),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: chartHeight + 24,
            child: maxTotal <= 0
                ? Center(child: Text('No sales in this period.', style: CbText.muted(context, 14)))
                : LayoutBuilder(
                    builder: (context, c) {
                      final slot = c.maxWidth / rows.length;
                      final barWidth = (slot * 0.62).clamp(3.0, 36.0);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < rows.length; i++)
                            SizedBox(
                              width: slot,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Tooltip(
                                    message:
                                        '${Fmt.date(rows[i].date)}\n'
                                        'Pool ${Fmt.inr(rows[i].pool)} · Food ${Fmt.inr(rows[i].food)}\n'
                                        'Drinks ${Fmt.inr(rows[i].drinks)} · Snacks ${Fmt.inr(rows[i].snacks)}',
                                    child: _StackedBar(
                                      row: rows[i],
                                      max: maxTotal,
                                      height: chartHeight,
                                      width: barWidth,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 18,
                                    child: i % labelEvery == 0 || i == rows.length - 1
                                        ? Text('${rows[i].date.day}', style: TextStyle(fontSize: 11.5, color: cb.muted))
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.row, required this.max, required this.height, required this.width});

  final DailyRow row;
  final double max;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Bottom to top: pool, food, drinks, snacks.
    final parts = [
      (row.snacks, SeriesColors.snacks),
      (row.drinks, SeriesColors.drinks),
      (row.food, SeriesColors.food),
      (row.pool, SeriesColors.pool),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (v, color) in parts)
          if (v > 0)
            Container(
              width: width,
              height: math.max(1, v / max * (height - 4)),
              margin: const EdgeInsets.only(top: 1),
              color: color,
            ),
      ],
    );
  }
}

class _ProfitMixCard extends StatelessWidget {
  const _ProfitMixCard({required this.mix});

  final List<MixRow> mix;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final shown = mix.where((m) => m.revenue > 0).toList();
    final totalProfit = shown.fold<double>(0, (s, m) => s + math.max(0, m.profit));
    final best = shown.isEmpty ? null : shown.reduce((a, b) => a.margin >= b.margin ? a : b);

    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Where profit comes from'),
          if (shown.isEmpty || totalProfit <= 0)
            Text('No sales in this period.', style: CbText.muted(context, 14))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final m in shown)
                      if (m.profit > 0)
                        Expanded(
                          flex: math.max(1, (m.profit / totalProfit * 1000).round()),
                          child: Container(color: SeriesColors.forKey(m.key), margin: const EdgeInsets.only(right: 2)),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (final m in shown)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cb.line)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: SeriesColors.forKey(m.key),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Revenue ${Fmt.inr(m.revenue)}', style: CbText.muted(context)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        NumText(Fmt.inr(m.profit), bold: true),
                        Text('${Fmt.trim(m.margin, 0)}% margin', style: CbText.muted(context)),
                      ],
                    ),
                  ],
                ),
              ),
            if (best != null) ...[
              const SizedBox(height: 12),
              Text(
                best.key == 'pool'
                    ? 'Pool table time has the highest margin: no ingredient cost, only electricity and cloth wear.'
                    : '${best.name} has the highest margin at ${Fmt.trim(best.margin, 0)}%.',
                style: CbText.muted(context, 13.5).copyWith(height: 1.45),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ItemCards extends StatelessWidget {
  const _ItemCards({required this.items});

  final List<ItemRow> items;

  @override
  Widget build(BuildContext context) {
    final best = items.where((r) => r.qty > 0).take(5).toList();
    final attention = items.where((r) => r.rating == Rating.lossRisk || r.rating == Rating.slow).toList()
      ..sort((a, b) => a.margin.compareTo(b.margin));

    final bestCard = CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            'Best sellers',
            bottom: 8,
            trailing: TextButton(
              onPressed: () => context.read<Nav>().go(Section.reports),
              child: const Text('See all'),
            ),
          ),
          CbTable(
            minWidth: 420,
            columns: const [
              Col('Item', flex: 5),
              Col('Qty', flex: 2, right: true),
              Col('Profit', flex: 3, right: true),
              Col('Margin', flex: 2, right: true),
            ],
            empty: 'No sales in this period.',
            rows: [
              for (final r in best)
                [
                  Text(r.name, overflow: TextOverflow.ellipsis),
                  NumText(r.qtyLabel),
                  NumText(Fmt.inr(r.profit)),
                  NumText('${Fmt.trim(r.margin, 0)}%', bold: true, color: toneColor(context, marginTone(r.margin))),
                ],
            ],
          ),
        ],
      ),
    );

    final attentionCard = CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            'Needs attention',
            bottom: 8,
            trailing: Text('Low sales or thin margin', style: CbText.muted(context)),
          ),
          CbTable(
            minWidth: 420,
            columns: const [Col('Item', flex: 5), Col('Issue', flex: 4), Col('Margin', flex: 2, right: true)],
            empty: 'Nothing to fix. Every item sells and earns.',
            rows: [
              for (final r in attention.take(5))
                [
                  Text(r.name, overflow: TextOverflow.ellipsis),
                  r.rating == Rating.lossRisk
                      ? const CbBadge('Thin margin', tone: Tone.red)
                      : CbBadge(r.qty == 0 ? 'Not sold' : 'Only ${r.qty.toInt()} sold', tone: Tone.amber),
                  NumText('${Fmt.trim(r.margin, 0)}%', bold: true, color: toneColor(context, marginTone(r.margin))),
                ],
            ],
          ),
        ],
      ),
    );

    return _TwoUp(ratio: (1, 1), left: bestCard, right: attentionCard);
  }
}

class _BusyHoursCard extends StatelessWidget {
  const _BusyHoursCard({required this.hours, required this.days});

  final Map<int, double> hours;
  final int days;

  static String _h(int h) => h == 12 ? '12p' : (h > 12 ? '${h - 12}p' : '${h}a');

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    const height = 150.0;
    final firstBusy = hours.entries.where((e) => e.value >= 40).map((e) => e.key).firstOrNull;
    final anyData = hours.values.any((v) => v > 0);

    String hint;
    if (!anyData) {
      hint = 'No pool table time in this period.';
    } else if (firstBusy != null && firstBusy >= 14) {
      final t = firstBusy > 12 ? '${firstBusy - 12} PM' : '$firstBusy PM';
      hint = 'Quiet before $t. Consider a happy-hour table rate to fill afternoons.';
    } else if (firstBusy == null) {
      hint = 'Tables are under 40% busy all day. A happy-hour rate may bring more players in.';
    } else {
      hint = 'Tables are busy from early afternoon.';
    }

    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            'Pool table busy hours',
            trailing: Text(
              days == 1 ? 'occupancy, today' : 'avg. occupancy, last $days days',
              style: CbText.muted(context),
            ),
          ),
          SizedBox(
            height: height + 26,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in hours.entries)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Tooltip(
                            message: '${_h(e.key)}: ${Fmt.trim(e.value, 0)}% busy',
                            child: Container(
                              height: math.max(4, e.value / 100 * height),
                              decoration: BoxDecoration(
                                color: SeriesColors.occupancy(e.value),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_h(e.key), style: TextStyle(fontSize: 11.5, color: cb.muted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: const [
              LegendItem(label: '75%+', color: Color(0xFF0E6B4A)),
              LegendItem(label: '40–74%', color: Color(0xFF5FA383)),
              LegendItem(label: 'under 40%', color: Color(0xFFC4DCCF)),
            ],
          ),
          const SizedBox(height: 10),
          Text(hint, style: CbText.muted(context, 13.5)),
        ],
      ),
    );
  }
}

class _RecentInvoicesCard extends StatelessWidget {
  const _RecentInvoicesCard({required this.invoices});

  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) {
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            'Recent invoices',
            bottom: 8,
            trailing: TextButton(
              onPressed: () => context.read<Nav>().go(Section.invoices),
              child: const Text('Open invoices'),
            ),
          ),
          CbTable(
            minWidth: 440,
            rowHeight: 58,
            columns: const [
              Col('Invoice', flex: 3),
              Col('Table', flex: 3),
              Col('Paid by', flex: 2),
              Col('Amount', flex: 2, right: true),
            ],
            empty: 'No invoices yet.',
            onTapRow: (i) => showReceiptDialog(context, invoices[i]),
            rows: [
              for (final inv in invoices)
                [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NumText(inv.number, size: 13.5),
                      Text(Fmt.time(inv.paidAt), style: CbText.muted(context, 12)),
                    ],
                  ),
                  Text(inv.tableName, overflow: TextOverflow.ellipsis),
                  Text(inv.paymentLabel),
                  NumText(Fmt.inr(inv.total), bold: true),
                ],
            ],
          ),
        ],
      ),
    );
  }
}
