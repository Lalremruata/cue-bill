import 'package:excel/excel.dart' as xl;

import '../core/billing.dart';
import '../core/format.dart';
import '../data/models.dart';
import 'analytics.dart';

/// Sheet name, heading lines, column headers, rows.
typedef _Sheet = (String, List<String>, List<String>, List<List<Object?>>);

/// .xlsx exports for the Reports tabs. Numbers are written as numbers so they add up in Excel.
class ExcelExport {
  ExcelExport._();

  static xl.CellValue _cell(Object? v) => switch (v) {
    null => xl.TextCellValue(''),
    int i => xl.IntCellValue(i),
    double d => xl.DoubleCellValue(double.parse(d.toStringAsFixed(2))),
    _ => xl.TextCellValue(v.toString()),
  };

  static List<int> _book(String sheetName, List<String> headers, List<List<Object?>> rows) =>
      _workbook([(sheetName, const <String>[], headers, rows)]);

  /// One .xlsx with a sheet per entry, in order. [heading] lines go above the table, then a blank row.
  static List<int> _workbook(List<_Sheet> sheets) {
    final book = xl.Excel.createExcel();
    final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
    for (var i = 0; i < sheets.length; i++) {
      final (name, heading, headers, rows) = sheets[i];
      if (i == 0) book.rename(defaultSheet, name);
      final sheet = book[name];
      for (var h = 0; h < heading.length; h++) {
        sheet.appendRow([xl.TextCellValue(heading[h])]);
        if (h == 0) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = xl.CellStyle(
            bold: true,
            fontSize: 14,
          );
        }
      }
      if (heading.isNotEmpty) sheet.appendRow([xl.TextCellValue('')]);
      sheet.appendRow(headers.map(xl.TextCellValue.new).toList());
      for (final r in rows) {
        sheet.appendRow(r.map(_cell).toList());
      }
      for (var c = 0; c < headers.length; c++) {
        sheet.setColumnWidth(c, c == 0 ? 28 : 14);
      }
    }
    return book.encode()!;
  }

  /// Heading for the item sales sheet: report name and period, then shop and any filters.
  static List<String> salesHeading({
    required String shop,
    required DateTime from,
    required DateTime to,
    List<String> filters = const [],
  }) => [
    'Item sales · ${Fmt.dateRange(from, to)}',
    [shop, ...filters].join(' · '),
  ];

  /// Dashboard export: daily sales and item sales for the period, one sheet each.
  static List<int> dashboard(
    List<DailyRow> daily,
    List<SalesLine> sales,
    List<DateTime> dates, {
    List<String> salesHeading = const [],
  }) => _workbook([_dailySheet(daily), _salesSheet(sales, dates, salesHeading)]);

  static List<int> items(List<ItemRow> rows, DateTime from, DateTime to) => _book(
    'Item performance',
    ['Item', 'Category', 'Qty', 'Unit', 'Revenue', 'Cost', 'Profit', 'Margin %', 'Rating'],
    [
      for (final r in rows)
        [
          r.name,
          r.category ?? '',
          r.isPool ? r.qty : r.qty.toInt(),
          r.isPool ? 'h' : '',
          r.revenue,
          r.cost,
          r.profit,
          r.margin,
          r.rating.label,
        ],
    ],
  );

  /// Item sales with a quantity column per date, then total qty and amount, and a total row.
  /// Amounts are menu price, before discounts and GST.
  static List<int> sales(List<SalesLine> lines, List<DateTime> dates, {List<String> heading = const []}) =>
      _workbook([_salesSheet(lines, dates, heading)]);

  static _Sheet _salesSheet(List<SalesLine> lines, List<DateTime> dates, List<String> heading) {
    Object qty(SalesLine l, double v) => l.isPool ? v : v.toInt();
    double day(SalesLine l, int d) => d < l.perDay.length ? l.perDay[d] : 0;
    final items = lines.where((l) => !l.isPool);
    return (
      'Item sales',
      heading,
      ['Item', 'Category', 'Unit', for (final d in dates) Fmt.isoDate(d), 'Total', 'Amount'],
      [
        for (final l in lines)
          [
            l.name,
            l.category ?? '',
            l.isPool ? 'h' : '',
            for (var d = 0; d < dates.length; d++) qty(l, day(l, d)),
            qty(l, l.qty),
            l.amount,
          ],
        [
          'Total',
          '',
          'items',
          for (var d = 0; d < dates.length; d++) items.fold<int>(0, (s, l) => s + day(l, d).toInt()),
          items.fold<int>(0, (s, l) => s + l.qty.toInt()),
          roundTo(lines.fold(0.0, (s, l) => s + l.amount), 2),
        ],
      ],
    );
  }

  static List<int> daily(List<DailyRow> rows) => _workbook([_dailySheet(rows)]);

  static _Sheet _dailySheet(List<DailyRow> rows) => (
    'Daily sales',
    const <String>[],
    [
      'Date',
      'Invoices',
      'Pool hours',
      'Pool',
      'Food',
      'Drinks',
      'Snacks',
      'Dine-in',
      'Takeaway',
      'Revenue (ex GST)',
      'Collected (incl GST)',
      'Profit',
      'Margin %',
    ],
    [
      for (final r in rows)
        [
          Fmt.isoDate(r.date),
          r.invoices,
          r.poolHours,
          r.pool,
          r.food,
          r.drinks,
          r.snacks,
          r.dineIn,
          r.takeaway,
          r.revenue,
          r.collected,
          r.profit,
          r.margin,
        ],
    ],
  );

  static List<int> invoices(List<Invoice> rows) => _book(
    'Invoices',
    [
      'Invoice',
      'Date',
      'Time',
      'Table',
      'Order type',
      'Customer',
      'Phone',
      'Paid by',
      'Pool minutes billed',
      'Pool amount',
      'Items',
      'Discount %',
      'Discount',
      'GST pool',
      'GST food',
      'Round off',
      'Total',
      'Revenue (ex GST)',
      'Cost',
      'Profit',
    ],
    [
      for (final i in rows)
        [
          i.number,
          Fmt.isoDate(i.paidAt),
          Fmt.time(i.paidAt),
          i.tableName,
          i.orderTypeLabel,
          i.customerName,
          i.customerPhone,
          i.paymentLabel,
          i.poolBilledMinutes,
          i.poolAmount,
          i.itemsSubtotal,
          i.discountPercent,
          i.discountAmount,
          i.gstPool,
          i.gstFood,
          i.roundOff,
          i.total,
          i.netRevenue,
          i.totalCost,
          i.profit,
        ],
    ],
  );
}
