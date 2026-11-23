import 'dart:io';

import 'package:cue_bill/data/models.dart';
import 'package:cue_bill/data/store.dart';
import 'package:cue_bill/main.dart';
import 'package:cue_bill/ui/alert_sounds.dart';
import 'package:cue_bill/ui/shell.dart';
import 'package:cue_bill/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renders every screen at counter-PC and phone sizes, in light and dark, and fails on any layout error.
/// Records alert sounds instead of playing them: tests have no audio plugin.
class FakeSounds extends AlertSounds {
  final played = <AlertTone>[];

  @override
  Future<void> play(AlertTone tone) async => played.add(tone);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppStore store;
  late FakeSounds sounds;

  setUp(() => AlertSounds.instance = sounds = FakeSounds());

  setUpAll(() async {
    sqfliteFfiInit();
    for (final (family, files) in [
      ('Inter', ['Inter-Regular', 'Inter-Medium', 'Inter-SemiBold', 'Inter-Bold']),
      ('SpaceGrotesk', ['SpaceGrotesk-SemiBold', 'SpaceGrotesk-Bold']),
    ]) {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(rootBundle.load('assets/fonts/$f.ttf'));
      }
      await loader.load();
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a chime sounds before booked time runs out, and an alarm when it is up', (tester) async {
    late RestaurantTable pool;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('cuebill_sounds');
      store = await AppStore.open(dbPath: '${dir.path}/s.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
      pool = store.activeTables.firstWhere((t) => t.isPool);
      await store.startTimer(pool, bookedMinutes: 60);
    });
    await tester.pumpWidget(CueBillApp(store: store));
    await settle(tester);
    final s = store.sessionFor(pool)!;
    void tick() => Clock.now.value = DateTime.now();

    // Plenty of time left: quiet.
    tick();
    await tester.pump();
    expect(sounds.played, isEmpty);

    // Within the warning (5 minutes by default): one chime, not repeated.
    s.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 57));
    tick();
    await tester.pump();
    tick();
    await tester.pump();
    expect(sounds.played, [AlertTone.warning]);

    // Time up: the alarm, and the game pauses at the booked hour.
    s.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 61));
    tick();
    await tester.pump();
    expect(sounds.played, [AlertTone.warning, AlertTone.timeUp]);
    expect(s.timerState, TimerState.paused);
    expect(s.elapsedSeconds(), 60 * 60);
    expect(find.textContaining('The game is paused'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
  });

  for (final size in const [Size(1440, 1000), Size(390, 844)]) {
    testWidgets('all screens render at ${size.width.toInt()} px', (tester) async {
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('cuebill_ui');
        store = await AppStore.open(dbPath: '${dir.path}/ui.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
        await store.loadSampleSales();
        await store.saveTable(RestaurantTable(name: 'Pool Table 2', type: 'pool', sort: 1));
        // An open pool table with a running timer and items, and a dining table with items.
        final pool = store.activeTables.first;
        await store.startTimer(pool);
        await store.addItem(pool, store.menu.first, 2);
        await store.addItem(store.activeTables[3], store.menu[3]);
        await store.addItem(await store.newTakeaway(), store.menu[4]);
        // A long order: every menu item, so the order lines must scroll.
        for (final m in store.menu.skip(1)) {
          await store.addItem(pool, m);
        }
        // Pool Table 2: booked for an hour, 70 minutes ago, so it is over time.
        final booked = store.activeTables[1];
        await store.startTimer(booked, bookedMinutes: 60);
        store.sessionFor(booked)!.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 70));
        // A third, free pool table for the walk-in dialog, with a booking later on.
        final third = RestaurantTable(name: 'Pool Table 3', type: 'pool', sort: 2);
        await store.saveTable(third);
        await store.saveBooking(
          Booking(
            tableId: third.id!,
            customerName: 'Priya with a long name',
            customerPhone: '9876500000',
            note: 'Paid ₹100 advance',
            startAt: DateTime.now().add(const Duration(hours: 3)),
            minutes: 60,
          ),
        );
        // Regulars for the Customers page.
        await store.saveCustomer(Customer(name: 'Lalpeka', phone: '+91 98765 43210', discountPercent: 10));
        await store.saveCustomer(
          Customer(name: 'Mama Zote with a rather long name for the table', notes: 'Likes table 2'),
        );
      });

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CueBillApp(store: store));
      await settle(tester);
      final ctx = tester.element(find.byType(AppShell));
      final nav = ctx.read<Nav>();
      final theme = ctx.read<ThemeController>();

      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        theme.value = mode;
        for (final s in Section.values) {
          nav.go(s);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: '${s.name} ${mode.name}');
        }
        // Pool table selected, then its checkout.
        nav.go(Section.pos);
        nav.selectTable(store.activeTables.first.id);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'pos selected');
        nav.openCheckout(store.activeTables.first.id!);
        await settle(tester);
        expect(find.text('Checkout'), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'checkout');
        nav.closeCheckout();
        await settle(tester);
      }

      // A regular's dialog, with their recent bills.
      nav.go(Section.customers);
      await settle(tester);
      expect(find.text('10% off'), findsOneWidget);
      await tester.tap(find.text('Lalpeka'));
      await settle(tester);
      expect(find.text('Recent bills'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'customer dialog');
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      // Over-time table: flagged in the strip; the adjust dialog shows its history.
      nav.go(Section.pos);
      nav.selectTable(store.activeTables[1].id);
      await settle(tester);
      expect(find.textContaining('time up'), findsWidgets);
      final phone = size.width < 1080;
      if (phone) {
        await tester.tap(find.text('Order'));
        await settle(tester);
      }
      expect(find.text('over time'), findsOneWidget);
      expect(find.text('+1 hour'), findsOneWidget);
      await tester.tap(find.text('Adjust'));
      await settle(tester);
      expect(find.text('Game history'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'adjust dialog');
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await tester.tap(find.text('+1 hour'));
      await settle(tester);
      expect(store.sessionFor(store.activeTables[1])!.bookedMinutes, 120);
      if (phone) {
        Navigator.of(tester.element(find.text('+1 hour'))).pop();
        await settle(tester);
      }

      // Long order on Pool Table 1: totals and checkout stay on screen.
      nav.selectTable(store.activeTables.first.id);
      await settle(tester);
      if (phone) {
        await tester.tap(find.text('Order'));
        await settle(tester);
      }
      expect(find.text('End & checkout').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'long order');
      if (phone) {
        Navigator.of(tester.element(find.text('End & checkout'))).pop();
        await settle(tester);
      }

      // Free pool table: a walk-in with the customer's name and hours.
      final third = store.activeTables.firstWhere((t) => t.name == 'Pool Table 3');
      nav.selectTable(third.id);
      await settle(tester);
      await tester.tap(find.text('Walk-in').last);
      await settle(tester);
      expect(find.text('How long?'), findsOneWidget);
      final nameField = find.descendant(
        of: find.widgetWithText(FieldLabel, 'Customer name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Ravi');
      await settle(tester);
      await tester.tap(find.text('1h 30m'));
      await settle(tester);
      await tester.tap(find.text('Start now').last);
      await settle(tester);
      expect(store.sessionFor(third)!.bookedMinutes, 90);
      expect(store.sessionFor(third)!.customerName, 'Ravi');
      expect(tester.takeException(), isNull, reason: 'walk-in dialog');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
    });

    testWidgets('bookings page at ${size.width.toInt()} px: free slots, start a booking, checkout knows who', (
      tester,
    ) async {
      late RestaurantTable pool;
      final tomorrow = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('cuebill_bookings_ui');
        store = await AppStore.open(dbPath: '${dir.path}/b.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
        pool = store.activeTables.firstWhere((t) => t.isPool);
        for (final (name, hour) in [('Ravi', 10), ('Mama', 14)]) {
          await store.saveBooking(
            Booking(
              tableId: pool.id!,
              customerName: name,
              startAt: tomorrow.add(Duration(hours: hour)),
              minutes: 60,
            ),
          );
        }
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CueBillApp(store: store));
      await settle(tester);
      final nav = tester.element(find.byType(AppShell)).read<Nav>();
      nav.go(Section.bookings);
      await settle(tester);
      expect(find.text('Nothing booked'), findsOneWidget);
      await tester.tap(find.byTooltip('Next day'));
      await settle(tester);
      expect(find.text('2 bookings · 2h booked'), findsOneWidget);
      expect(find.textContaining('Free 11:00 AM – 2:00 PM'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'bookings page');

      // The pool table shows who is next.
      nav.go(Section.pos);
      await settle(tester);
      expect(find.textContaining('Next Ravi'), findsWidgets);
      nav.go(Section.bookings);
      await settle(tester);
      await tester.tap(find.byTooltip('Next day'));
      await settle(tester);

      // Ravi arrives early: start, confirm, and the table opens for him.
      await tester.tap(find.text('Start').first);
      await settle(tester);
      await tester.tap(find.text('Start now'));
      await settle(tester);
      expect(nav.section, Section.pos);
      final s = store.sessionFor(pool)!;
      expect(s.customerName, 'Ravi');
      expect(s.bookedMinutes, 60);
      expect(tester.takeException(), isNull, reason: 'booking started');

      // Checkout already has his name.
      s.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 50));
      nav.openCheckout(pool.id!);
      await settle(tester);
      final nameField = find.descendant(
        of: find.widgetWithText(FieldLabel, 'Customer name (optional)'),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(nameField).controller!.text, 'Ravi');
      expect(tester.takeException(), isNull, reason: 'checkout prefilled');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
    });

    testWidgets('checkout at ${size.width.toInt()} px: picking a regular fills in their discount', (tester) async {
      late Customer regular;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('cuebill_regular');
        store = await AppStore.open(dbPath: '${dir.path}/r.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
        regular = await store.saveCustomer(Customer(name: 'Lalpeka', phone: '98765 43210', discountPercent: 10));
        await store.addItem(store.activeTables[2], store.menu.first, 2);
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CueBillApp(store: store));
      await settle(tester);
      final nav = tester.element(find.byType(AppShell)).read<Nav>();
      nav.openCheckout(store.activeTables[2].id!);
      await settle(tester);

      final phoneField = find.widgetWithText(FieldLabel, 'Phone (optional)');
      await tester.ensureVisible(phoneField);
      await tester.enterText(find.descendant(of: phoneField, matching: find.byType(TextField)), '98765');
      await settle(tester);
      expect(find.textContaining('Lalpeka  9876543210'), findsOneWidget);
      await tester.tap(find.textContaining('Lalpeka  9876543210'));
      await settle(tester);
      expect(find.textContaining('Regular customer · 10% off'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'regular picked');

      final complete = find.textContaining('Complete sale').last;
      await tester.ensureVisible(complete);
      await settle(tester);
      await tester.tap(complete);
      await settle(tester);
      await settle(tester);
      final invoice = (await tester.runAsync(() => store.customerInvoices(regular)))!.single;
      expect(invoice.customerId, regular.id);
      expect(invoice.customerName, 'Lalpeka');
      expect(invoice.customerPhone, '9876543210');
      expect(invoice.discountPercent, 10);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
    });

    testWidgets('takeaway page at ${size.width.toInt()} px: new order, items, checkout, back', (tester) async {
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('cuebill_takeaway');
        store = await AppStore.open(dbPath: '${dir.path}/t.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CueBillApp(store: store));
      await settle(tester);
      final nav = tester.element(find.byType(AppShell)).read<Nav>();
      final table = store.activeTables[2];
      nav.selectTable(table.id);
      nav.go(Section.takeaway);
      await settle(tester);
      expect(find.text('No takeaway orders open. Tap New takeaway to start one.'), findsOneWidget);
      expect(find.text('No order selected'), size.width >= 1080 ? findsOneWidget : findsNothing);

      await tester.tap(find.text('New takeaway'));
      await settle(tester);
      final order = store.takeawayOrders.single;
      expect(order.name, 'Takeaway #1');
      expect(nav.selectedTakeawayId, order.id);
      expect(nav.selectedTableId, table.id, reason: 'the table selection is kept apart');
      expect(find.text('Takeaway #1'), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'takeaway order open');

      // Not on Tables & Orders.
      nav.go(Section.pos);
      await settle(tester);
      expect(find.text('Takeaway #1'), findsNothing);
      nav.go(Section.takeaway);
      await settle(tester);

      await tester.runAsync(() => store.addItem(order, store.menu.first, 2));
      await settle(tester);
      if (size.width < 1080) {
        await tester.tap(find.text('Order'));
        await settle(tester);
      }
      await tester.tap(find.text('Checkout').hitTestable());
      await settle(tester);
      expect(nav.section, Section.takeaway);
      expect(nav.checkoutTableId, order.id);
      expect(find.text('Back to Takeaway #1'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'takeaway checkout');

      final complete = find.textContaining('Complete sale').last;
      await tester.ensureVisible(complete);
      await settle(tester);
      await tester.tap(complete);
      await settle(tester);
      await settle(tester);
      expect(store.takeawayOrders, isEmpty);
      expect(find.textContaining('Takeaway #1 is done.'), findsOneWidget);
      final back = find.text('Back to takeaway').last;
      await tester.ensureVisible(back);
      await settle(tester);
      await tester.tap(back);
      await settle(tester);
      expect(nav.section, Section.takeaway);
      expect(nav.checkoutTableId, isNull);
      expect(find.text('No takeaway orders open. Tap New takeaway to start one.'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'after checkout');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
    });
  }
}
