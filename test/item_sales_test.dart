import 'package:cue_bill/data/models.dart';
import 'package:cue_bill/services/analytics.dart';
import 'package:cue_bill/services/excel_export.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 10, 18);
  const business = BusinessSnapshot(name: 'Test');

  InvoiceItem item(int id, String name, String category, String type, int qty, double price) => InvoiceItem(
    menuItemId: id,
    name: name,
    categoryName: category,
    categoryType: type,
    qty: qty,
    unitPrice: price,
    unitCost: price / 2,
    amount: qty * price,
  );

  Invoice invoice(
    List<InvoiceItem> items, {
    int poolMinutes = 0,
    double poolAmount = 0,
    String pay = 'cash',
    DateTime? at,
  }) => Invoice(
    number: 'INV-1',
    tableName: 'Table 1',
    paymentMethod: pay,
    poolBilledMinutes: poolMinutes,
    poolAmount: poolAmount,
    total: 0,
    business: business,
    paidAt: at ?? day,
    items: items,
  );

  SalesAnalytics analytics(List<Invoice> invoices, {String? payment, DateTime? from, DateTime? to}) => SalesAnalytics(
    from: from ?? day,
    to: to ?? day,
    invoices: invoices,
    activeMenu: [MenuItem(id: 9, categoryId: 2, name: 'Never sold', price: 50)],
    categories: {
      1: MenuCategory(id: 1, name: 'Drinks', type: 'drinks', sort: 2),
      2: MenuCategory(id: 2, name: 'Snacks', type: 'snacks', sort: 1),
    },
    poolTables: 1,
    payment: payment,
  );

  final invoices = [
    invoice(
      [item(1, 'Coke', 'Drinks', 'drinks', 2, 40), item(2, 'Fries', 'Snacks', 'snacks', 1, 80)],
      poolMinutes: 90,
      poolAmount: 300,
    ),
    invoice([item(1, 'Coke', 'Drinks', 'drinks', 3, 40), item(3, 'Water', 'Drinks', 'drinks', 4, 20)], pay: 'upi'),
    invoice([item(4, 'Old item', 'Removed category', 'food', 1, 100)]),
  ];

  test('pool first, then categories in menu order, most sold first; unsold items left out', () {
    final lines = analytics(invoices).sales();
    expect([for (final l in lines) l.name], ['Pool table', 'Fries', 'Coke', 'Water', 'Old item']);
    expect([for (final l in lines) l.qtyLabel], ['1.5 h', '1', '5', '4', '1']);
    expect([for (final l in lines) l.amount], [300, 80, 200, 80, 100]);
  });

  test('category and payment filters', () {
    expect([for (final l in analytics(invoices).sales(categoryType: 'drinks')) l.name], ['Coke', 'Water']);
    expect([for (final l in analytics(invoices).sales(categoryType: 'pool')) l.name], ['Pool table']);
    final upi = analytics(invoices, payment: 'upi').sales();
    expect([for (final l in upi) '${l.name} ${l.qtyLabel}'], ['Water 4', 'Coke 3']);
  });

  test('nothing sold gives an empty list', () {
    expect(analytics([]).sales(), isEmpty);
  });

  test('Excel export ends with a total row', () {
    final a = analytics(invoices);
    final book = xl.Excel.decodeBytes(ExcelExport.sales(a.sales(), a.dates));
    final rows = book['Item sales'].rows;
    expect(
      [for (final c in rows.first) c?.value.toString()],
      ['Item', 'Category', 'Unit', '2026-11-10', 'Total', 'Amount'],
    );
    final total = [for (final c in rows.last) c?.value.toString()];
    expect(total[0], 'Total');
    expect(total[3], '11');
    expect(total[4], '11');
    expect(double.parse(total[5]!), 760);
  });

  test('item sales has a quantity for each day of the period', () {
    final day1 = DateTime(2026, 11, 8, 20);
    final day3 = DateTime(2026, 11, 10, 13);
    final a = analytics(
      [
        invoice([item(1, 'Coke', 'Drinks', 'drinks', 2, 40)], poolMinutes: 90, poolAmount: 300, at: day1),
        invoice([item(1, 'Coke', 'Drinks', 'drinks', 3, 40), item(3, 'Water', 'Drinks', 'drinks', 1, 20)], at: day3),
        invoice([], poolMinutes: 60, poolAmount: 200, at: day3),
      ],
      from: day1,
      to: day3,
    );
    expect(a.dates, [DateTime(2026, 11, 8), DateTime(2026, 11, 9), DateTime(2026, 11, 10)]);

    final lines = {for (final l in a.sales()) l.name: l};
    expect(lines['Pool table']!.perDay, [1.5, 0, 1]);
    expect([for (var d = 0; d < 3; d++) lines['Pool table']!.dayLabel(d)], ['1.5 h', '0 h', '1 h']);
    expect(lines['Coke']!.perDay, [2, 0, 3]);
    expect(lines['Coke']!.qty, 5);
    expect(lines['Water']!.perDay, [0, 0, 1]);

    final rows = xl.Excel.decodeBytes(ExcelExport.sales(a.sales(), a.dates))['Item sales'].rows;
    List<String?> row(int r) => [for (final c in rows[r]) c?.value.toString()];
    expect(row(0), ['Item', 'Category', 'Unit', '2026-11-08', '2026-11-09', '2026-11-10', 'Total', 'Amount']);
    expect(row(1).sublist(0, 7), ['Pool table', 'Pool table', 'h', '1.5', '0', '1', '2.5']);
    expect(row(2).sublist(0, 7), ['Coke', 'Drinks', '', '2', '0', '3', '5']);
    expect(row(rows.length - 1).sublist(0, 7), ['Total', '', 'items', '2', '0', '4', '6']);
  });

  test('Dashboard export has a daily sales sheet and an item sales sheet', () {
    final a = analytics(invoices);
    final book = xl.Excel.decodeBytes(ExcelExport.dashboard(a.daily(), a.sales(), a.dates));
    expect(book.tables.keys, containsAll(['Daily sales', 'Item sales']));
    expect(book.tables.length, 2);
    expect(book['Item sales'].rows[1].first?.value.toString(), 'Pool table');
    expect(book['Item sales'].rows.last.first?.value.toString(), 'Total');
    expect(book['Daily sales'].rows.first.first?.value.toString(), 'Date');
  });

  test('Excel item sales sheet starts with the period, shop and filters', () {
    final heading = ExcelExport.salesHeading(
      shop: 'Cue Corner',
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 10, 23, 59),
      filters: ['Drinks only', 'UPI only'],
    );
    expect(heading, ['Item sales · 01 Nov 2026 – 10 Nov 2026', 'Cue Corner · Drinks only · UPI only']);
    expect(ExcelExport.salesHeading(shop: 'Cue Corner', from: day, to: day).first, 'Item sales · 10 Nov 2026');

    final a = analytics(invoices);
    for (final bytes in [
      ExcelExport.sales(a.sales(), a.dates, heading: heading),
      ExcelExport.dashboard(a.daily(), a.sales(), a.dates, salesHeading: heading),
    ]) {
      final rows = xl.Excel.decodeBytes(bytes)['Item sales'].rows;
      String? cell(int r) => rows[r].first?.value.toString();
      expect(cell(0), 'Item sales · 01 Nov 2026 – 10 Nov 2026');
      expect(cell(1), 'Cue Corner · Drinks only · UPI only');
      expect(rows[2].every((c) => c == null || c.value.toString().isEmpty), isTrue);
      expect(cell(3), 'Item');
      expect(cell(4), 'Pool table');
      expect(cell(rows.length - 1), 'Total');
    }
  });
}
