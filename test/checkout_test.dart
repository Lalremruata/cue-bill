import 'dart:io';
import 'dart:typed_data';

import 'package:cue_bill/data/database.dart';
import 'package:cue_bill/data/models.dart';
import 'package:cue_bill/data/store.dart';
import 'package:cue_bill/services/analytics.dart';
import 'package:cue_bill/services/checkout.dart';
import 'package:cue_bill/services/excel_export.dart';
import 'package:cue_bill/services/receipt.dart';
import 'package:cue_bill/services/receipt_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late AppStore store;

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cuebill_test');
    store = await AppStore.open(dbPath: '${dir.path}/test.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test('seeds menu, tables and settings on first run', () {
    expect(store.menu.length, 16);
    expect(store.activeTables.first.name, 'Pool Table 1');
    expect(store.activeTables.last.name, 'Takeaway');
    expect(store.settings.invoiceFooter, 'Thank you! Come back for another frame.');
  });

  test('a pool table bill matches the design example (₹911)', () async {
    final table = store.activeTables.first;
    final session = await store.ensureSession(table);
    final menu = {for (final m in store.menu) m.name: m};
    await store.addItem(table, menu['Chicken momo (8 pc)']!, 2);
    await store.addItem(table, menu['Cold coffee']!, 2);
    await store.addItem(table, menu['French fries']!);

    // Played 1h 24m at ₹200/hr → billed 1h 30m = ₹300.
    final start = DateTime(2026, 11, 6, 20, 34);
    session
      ..timerStartedAt = start
      ..hourlyRate = 200
      ..timerStoppedAt = start.add(const Duration(minutes: 84));

    final calc = store.calcFor(table)!;
    expect(calc.billedMinutes, 90);
    expect(calc.poolAmount, 300);
    expect(calc.itemsSubtotal, 530);
    expect(calc.totals.total, 911);

    store.settings.upiId = 'example@upi';
    final preview = Checkout.preview(
      settings: store.settings,
      calc: calc,
      tableName: table.name,
      options: const CheckoutOptions(paymentMethod: 'upi'),
    );
    expect(preview.lines.first.qty, '1.5 h');
    expect(preview.lines.first.note, '8:34 PM – 9:58 PM · played 1h 24m, billed 1h 30m');
    expect(preview.upiUri, contains('am=911.00'));
  });

  test('completing a sale saves the invoice, closes the table and bumps the number', () async {
    final table = store.activeTables.firstWhere((t) => t.name == 'Table 1');
    await store.addItem(table, store.menu.first, 3);
    final before = store.settings.nextInvoiceNumber;

    final invoice = await store.completeSale(table, const CheckoutOptions(paymentMethod: 'cash', discountPercent: 10));
    expect(invoice.number, 'INV-${before.toString().padLeft(5, '0')}');
    expect(store.sessionFor(table), isNull);
    expect(store.settings.nextInvoiceNumber, before + 1);
    expect(invoice.items.single.qty, 3);
    expect(invoice.discountPercent, 10);

    final saved = await store.recentInvoices();
    expect(saved.single.number, invoice.number);
    expect(saved.single.items.length, 1);

    // Nothing to bill → refused.
    await store.ensureSession(table);
    expect(() => store.completeSale(table, const CheckoutOptions()), throwsA(isA<CueBillException>()));

    // Receipt PDFs build for both formats.
    final receipt = ReceiptData.fromInvoice(saved.single);
    expect((await ReceiptPdf.build(receipt, ReceiptFormat.roll80)).length, greaterThan(1000));
    expect((await ReceiptPdf.build(receipt, ReceiptFormat.a4)).length, greaterThan(1000));
  });

  test('sample sales feed the dashboard and reports', () async {
    final created = await store.loadSampleSales();
    expect(created, greaterThan(400));
    final (from, to) = SalesAnalytics.lastDays(7);
    final a = await store.analytics(from, to);
    final s = a.summary();
    expect(s.invoices, greaterThan(50));
    expect(s.revenue, greaterThan(0));
    expect(a.daily().length, 7);
    expect(a.mix().first.key, 'pool');
    final items = a.items();
    expect(items.any((r) => r.isPool), isTrue);
    expect(items.map((r) => r.rating).toSet(), isNotEmpty);
    expect(a.busyHours().length, 12);

    expect(ExcelExport.items(items, from, to).length, greaterThan(1000));
    expect(ExcelExport.daily(a.daily()).length, greaterThan(1000));
    expect(ExcelExport.invoices(a.invoices).length, greaterThan(1000));
  });

  test('backup and restore round trip', () async {
    await store.addItem(store.activeTables[2], store.menu.first);
    await store.completeSale(store.activeTables[2], const CheckoutOptions());
    final bytes = await store.backupBytes();
    await store.loadSampleSales();
    expect(store.invoiceCount, greaterThan(1));
    await store.restore(bytes);
    expect(store.invoiceCount, 1);
    expect(() => store.restore(Uint8List.fromList(List<int>.filled(200, 7))), throwsA(isA<CueBillException>()));
  });

  test('a booked table: countdown, extend, adjust with reason, and the invoice keeps the booking', () async {
    final table = store.activeTables.first;
    await store.startTimer(table, bookedMinutes: 60);
    final s = store.sessionFor(table)!;
    expect(s.bookedMinutes, 60);
    expect(s.events.single.type, 'start');

    // Pretend 66 minutes have been played: 6 over, past the 5 free minutes.
    s.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 66));
    expect(s.bookingState(5), BookingState.over);
    expect(store.calcFor(table)!.billedMinutes, 75);

    await store.extendBooking(table, 30);
    expect(s.bookedMinutes, 90);
    expect(s.bookingState(5), BookingState.ok);
    expect(store.calcFor(table)!.billedMinutes, 90);
    expect(s.bookingState(30), BookingState.warning);

    // Cutting played time or the booking needs a reason; adding time does not.
    expect(
      () => store.adjustTimer(table, bookedMinutes: 90, playedDeltaMinutes: -10),
      throwsA(isA<CueBillException>()),
    );
    expect(() => store.adjustTimer(table, bookedMinutes: 60), throwsA(isA<CueBillException>()));
    await store.adjustTimer(table, bookedMinutes: 120);
    expect(s.bookedMinutes, 120);
    await store.adjustTimer(table, bookedMinutes: 120, playedDeltaMinutes: -10, reason: 'Started late');
    expect((s.elapsedSeconds() / 60).round(), 56);
    expect(s.events.last.note, 'Started late');
    expect(
      () => store.adjustTimer(table, bookedMinutes: 120, playedDeltaMinutes: -500, reason: 'x'),
      throwsA(isA<CueBillException>()),
    );

    await store.stopTimer(table);
    expect(s.bookingState(5), BookingState.none);
    final invoice = await store.completeSale(table, const CheckoutOptions(paymentMethod: 'cash'));
    expect(invoice.poolBookedMinutes, 120);
    expect(invoice.poolBilledMinutes, 120);
    final saved = (await store.recentInvoices()).single;
    expect(saved.poolBookedMinutes, 120);
    expect(ReceiptData.fromInvoice(saved).lines.first.note, contains('booked 2h, played 5'));

    // History survives a reload of an open table.
    final t2 = store.activeTables[1];
    await store.startTimer(t2);
    await store.pauseTimer(t2);
    await store.reload();
    expect(store.sessionFor(t2)!.events.map((e) => e.type), ['start', 'pause']);
    expect(store.sessionFor(t2)!.isBooked, isFalse);
  });

  test('dashboard pool hours count tables still playing, and only once after checkout', () async {
    final (from, to) = SalesAnalytics.lastDays(1);
    final pool = store.activeTables.where((t) => t.isPool).toList();
    expect(store.livePoolSeconds(), 0);
    expect(store.poolTablesPlaying, 0);

    await store.startTimer(pool[0]);
    store.sessionFor(pool[0])!.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 45));
    await store.startTimer(pool[1]);
    store.sessionFor(pool[1])!.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 30));
    await store.pauseTimer(pool[1]);

    // Not paid yet: the invoices show nothing, the live time shows both tables.
    expect((await store.analytics(from, to)).summary().poolHours, 0);
    expect((store.livePoolSeconds() / 60).round(), 75);
    expect(store.poolTablesPlaying, 1); // the paused one is not playing
    final occupancy = (await store.analytics(from, to)).poolOccupancy(liveMinutes: 75);
    expect(occupancy, greaterThan(0));

    // Paid: the time moves onto the invoice and leaves the live count.
    await store.stopTimer(pool[0]);
    await store.completeSale(pool[0], const CheckoutOptions(paymentMethod: 'cash'));
    expect((await store.analytics(from, to)).summary().poolHours, 0.8);
    expect((store.livePoolSeconds() / 60).round(), 30);
  });

  test('open play turns into a booking when time is added', () async {
    final table = store.activeTables.first;
    await store.startTimer(table, bookedMinutes: 0);
    final s = store.sessionFor(table)!;
    expect(s.bookedMinutes, isNull);
    s.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 50));
    await store.extendBooking(table, 30); // 50 played → 60 in blocks, + 30
    expect(s.bookedMinutes, 90);
  });

  test('typing a quantity sets it, and 0 removes the line', () async {
    final table = store.activeTables[2];
    await store.addItem(table, store.menu.first);
    await store.setQty(table, store.menu.first.id!, 12);
    expect(store.sessionFor(table)!.items.single.qty, 12);
    expect(store.lastTouched?.menuItemId, store.menu.first.id);
    await store.setQty(table, store.menu.first.id!, 0);
    expect(store.sessionFor(table)!.items, isEmpty);
  });

  test('a version 1 database is upgraded', () async {
    final path = '${dir.path}/v1.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE table_sessions (id INTEGER PRIMARY KEY, restaurant_table_id INTEGER)');
          await db.execute('CREATE TABLE invoices (id INTEGER PRIMARY KEY, number TEXT)');
        },
      ),
    );
    await old.close();
    final db = await AppDatabase.open(path, databaseFactoryFfi);
    Future<Set<Object?>> cols(String t) async =>
        (await db.rawQuery('PRAGMA table_info($t)')).map((r) => r['name']).toSet();
    expect(await cols('table_sessions'), contains('booked_minutes'));
    expect(await cols('invoices'), contains('pool_booked_minutes'));
    expect(await cols('session_events'), containsAll(['type', 'minutes', 'note', 'at']));
    await db.close();
  });

  test('pool rate uses happy hour, then the table rate, then the default', () {
    final s = BusinessSettings(happyHourEnabled: true, happyHourRate: 150, poolRatePerHour: 200);
    final t = RestaurantTable(name: 'P', type: 'pool', hourlyRate: 250);
    expect(s.poolRateFor(t, DateTime(2026, 1, 1, 13)), 150);
    expect(s.poolRateFor(t, DateTime(2026, 1, 1, 16)), 250);
    expect(s.poolRateFor(RestaurantTable(name: 'Q', type: 'pool'), DateTime(2026, 1, 1, 18)), 200);
  });
}
