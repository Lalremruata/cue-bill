import 'dart:io';

import 'package:cue_bill/data/models.dart';
import 'package:cue_bill/data/store.dart';
import 'package:cue_bill/main.dart';
import 'package:cue_bill/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renders every screen at counter-PC and phone sizes, in light and dark, and fails on any layout error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppStore store;

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

  for (final size in const [Size(1440, 1000), Size(390, 844)]) {
    testWidgets('all screens render at ${size.width.toInt()} px', (tester) async {
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('cuebill_ui');
        store = await AppStore.open(dbPath: '${dir.path}/ui.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
        await store.loadSampleSales();
        // An open pool table with a running timer and items, and a dining table with items.
        final pool = store.activeTables.first;
        await store.startTimer(pool);
        await store.addItem(pool, store.menu.first, 2);
        await store.addItem(store.activeTables[3], store.menu[3]);
        // A long order: every menu item, so the order lines must scroll.
        for (final m in store.menu.skip(1)) {
          await store.addItem(pool, m);
        }
        // Pool Table 2: booked for an hour, 70 minutes ago, so it is over time.
        final booked = store.activeTables[1];
        await store.startTimer(booked, bookedMinutes: 60);
        store.sessionFor(booked)!.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 70));
        // A third, free pool table for the start dialog.
        await store.saveTable(RestaurantTable(name: 'Pool Table 3', type: 'pool', sort: 2));
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
      expect(find.text('Timer history'), findsOneWidget);
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
      expect(find.text('Stop & checkout').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'long order');
      if (phone) {
        Navigator.of(tester.element(find.text('Stop & checkout'))).pop();
        await settle(tester);
      }

      // Free pool table: pick a booking and start.
      final third = store.activeTables.firstWhere((t) => t.name == 'Pool Table 3');
      nav.selectTable(third.id);
      await settle(tester);
      await tester.tap(find.text(phone ? 'Start' : 'Start timer').last);
      await settle(tester);
      expect(find.text('How long is the table booked for?'), findsOneWidget);
      await tester.tap(find.text('1h 30m'));
      await settle(tester);
      await tester.tap(find.text('Start timer').last);
      await settle(tester);
      expect(store.sessionFor(third)!.bookedMinutes, 90);
      expect(tester.takeException(), isNull, reason: 'start dialog');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
    });
  }
}
