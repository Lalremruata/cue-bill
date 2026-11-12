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

  Invoice invoice(List<InvoiceItem> items, {int poolMinutes = 0, double poolAmount = 0, String pay = 'cash'}) =>
      Invoice(
        number: 'INV-1',
        tableName: 'Table 1',
        paymentMethod: pay,
        poolBilledMinutes: poolMinutes,
        poolAmount: poolAmount,
        total: 0,
        business: business,
        paidAt: day,
        items: items,
      );

  SalesAnalytics analytics(List<Invoice> invoices, {String? payment}) => SalesAnalytics(
    from: day,
    to: day,
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
    final book = xl.Excel.decodeBytes(ExcelExport.sales(analytics(invoices).sales()));
    final rows = book['Item sales'].rows;
    expect([for (final c in rows.first) c?.value.toString()], ['Item', 'Category', 'Qty', 'Unit', 'Amount']);
    final total = [for (final c in rows.last) c?.value.toString()];
    expect(total[0], 'Total');
    expect(total[2], '11');
    expect(double.parse(total[4]!), 760);
  });

  test('Dashboard export has a daily sales sheet and an item sales sheet', () {
    final a = analytics(invoices);
    final book = xl.Excel.decodeBytes(ExcelExport.dashboard(a.daily(), a.sales()));
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
      ExcelExport.sales(a.sales(), heading: heading),
      ExcelExport.dashboard(a.daily(), a.sales(), salesHeading: heading),
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
