import 'dart:io';

import 'package:cue_bill/data/database.dart';
import 'package:cue_bill/data/models.dart';
import 'package:cue_bill/data/store.dart';
import 'package:cue_bill/services/checkout.dart';
import 'package:cue_bill/ui/screens/pos_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late AppStore store;
  late RestaurantTable pool;

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cuebill_bookings');
    store = await AppStore.open(dbPath: '${dir.path}/test.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
    pool = store.activeTables.firstWhere((t) => t.isPool);
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  /// Today at [hour]:[minute], or tomorrow if that has passed, so tests work at any time of day.
  DateTime at(int hour, [int minute = 0]) {
    final now = DateTime.now();
    final t = DateTime(now.year, now.month, now.day, hour, minute);
    return t.isAfter(now) ? t : t.add(const Duration(days: 1));
  }

  Booking booking(String name, DateTime start, int minutes, {String? phone}) =>
      Booking(tableId: pool.id!, customerName: name, customerPhone: phone, startAt: start, minutes: minutes);

  test('a fresh install has one pool table', () {
    expect(store.activeTables.where((t) => t.isPool).length, 1);
  });

  test('bookings are saved, tidied and listed in time order; clashes need staff to agree', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    final day = DateTime(start.year, start.month, start.day, 18);
    final ravi = await store.saveBooking(booking('  Ravi ', day, 60, phone: '+91 98765-43210'));
    expect(ravi.customerName, 'Ravi');
    expect(ravi.customerPhone, '9876543210');
    await store.saveBooking(booking('Mama', day.subtract(const Duration(hours: 2)), 90));
    expect(store.upcomingFor(pool).map((b) => b.customerName), ['Mama', 'Ravi']);

    // 18:30 overlaps Ravi 18:00–19:00; 19:00 sits right after.
    final clash = booking('Priya', day.add(const Duration(minutes: 30)), 60);
    expect(store.bookingConflicts(clash).single.name, 'Ravi');
    expect(() => store.saveBooking(clash), throwsA(isA<CueBillException>()));
    await store.saveBooking(clash, allowOverlap: true);
    expect(store.bookingConflicts(booking('Zote', day.add(const Duration(hours: 1)), 60)).map((c) => c.name), [
      'Priya',
    ]);

    expect(() => store.saveBooking(booking(' ', day, 60)), throwsA(isA<CueBillException>()));
    expect(() => store.saveBooking(booking('Nobody', day, 0)), throwsA(isA<CueBillException>()));

    // Editing a booking does not clash with itself.
    ravi.minutes = 45;
    await store.saveBooking(ravi.copy()..minutes = 45, allowOverlap: true);
    expect(store.bookingById(ravi.id)!.minutes, 45);

    final listed = await store.bookingsOn(day);
    expect(listed.map((b) => b.customerName), ['Mama', 'Ravi', 'Priya']);

    // Survives a reload.
    await store.reload();
    expect(store.upcomingFor(pool).length, 3);
  });

  test('starting a booking opens the table for the booked time; checkout bills the customer', () async {
    final regular = await store.saveCustomer(Customer(name: 'Lalpeka', phone: '9876543210', discountPercent: 10));
    final b = await store.saveBooking(
      Booking(
        tableId: pool.id!,
        customerName: 'Lalpeka',
        customerPhone: '9876543210',
        customerId: regular.id,
        startAt: at(23, 30),
        minutes: 90,
      ),
    );
    await store.startBooking(b);
    final s = store.sessionFor(pool)!;
    expect(s.timerState, TimerState.running);
    expect(s.bookedMinutes, 90);
    expect(s.customerName, 'Lalpeka');
    expect(s.customerId, regular.id);
    expect(s.events.single.note, 'Lalpeka');
    expect(b.status, 'playing');
    expect(store.playingBooking(pool)!.id, b.id);
    expect(store.upcomingFor(pool), isEmpty);

    // A second booking cannot start while the table is in use.
    final next = await store.saveBooking(booking('Next', at(23, 59), 30), allowOverlap: true);
    expect(() => store.startBooking(next), throwsA(isA<CueBillException>()));

    // Who is playing survives a restart.
    await store.reload();
    expect(store.sessionFor(pool)!.customerName, 'Lalpeka');
    expect(store.playingBooking(pool)!.id, b.id);

    store.sessionFor(pool)!.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 80));
    await store.stopTimer(pool);
    final invoice = await store.completeSale(
      pool,
      const CheckoutOptions(paymentMethod: 'cash', customerName: 'Lalpeka', customerPhone: '9876543210'),
    );
    expect(invoice.customerName, 'Lalpeka');
    expect(store.playingBooking(pool), isNull);
    final done = (await store.bookingsOn(b.startAt)).firstWhere((x) => x.id == b.id);
    expect(done.status, 'done');
    expect(done.sessionId, s.id);
  });

  test('a walk-in is a booking that starts now, and it warns about the next booking', () async {
    final soon = await store.saveBooking(booking('Priya', DateTime.now().add(const Duration(minutes: 40)), 60));
    expect(() => store.startWalkIn(pool, name: 'Walk-in Ravi', minutes: 60), throwsA(isA<CueBillException>()));
    expect(store.sessionFor(pool), isNull);

    final walkIn = await store.startWalkIn(pool, name: 'Ravi', phone: '98765 11111', minutes: 30);
    expect(walkIn.status, 'playing');
    expect(store.sessionFor(pool)!.bookedMinutes, 30);
    expect(store.bookingsHitBy(pool), isEmpty);
    // Adding an hour would run into Priya's booking.
    expect(store.bookingsHitBy(pool, extraMinutes: 60).single.id, soon.id);
    // A booking during the game clashes with it.
    final during = booking('Zote', DateTime.now().add(const Duration(minutes: 10)), 30);
    expect(store.bookingConflicts(during).first.playing, isTrue);
    expect(store.nextBookingFor(pool)!.id, soon.id);
    expect(() => store.startWalkIn(pool, name: 'Again', minutes: 30), throwsA(isA<CueBillException>()));
  });

  test('open play walk-in, cancel, no-show, restore, and clearing a table cancels its booking', () async {
    await store.startWalkIn(pool, name: 'Open', minutes: 0);
    expect(store.sessionFor(pool)!.bookedMinutes, isNull);
    final open = store.playingBooking(pool)!;
    await store.clearTable(pool);
    expect(store.playingBooking(pool), isNull);
    final cleared = (await store.bookingsOn(open.startAt)).firstWhere((x) => x.id == open.id);
    expect(cleared.status, 'cancelled');
    expect(cleared.cancelReason, 'Table cleared');

    final a = await store.saveBooking(booking('A', at(22), 60));
    final b = await store.saveBooking(booking('B', at(23), 60));
    await store.cancelBooking(a, reason: 'Phoned to cancel');
    await store.markNoShow(b);
    expect(store.upcomingFor(pool), isEmpty);
    final listed = await store.bookingsOn(a.startAt);
    expect(listed.firstWhere((x) => x.id == a.id).cancelReason, 'Phoned to cancel');
    expect(listed.firstWhere((x) => x.id == b.id).statusLabel, 'No-show');
    expect(() => store.cancelBooking(a), throwsA(isA<CueBillException>()));

    await store.restoreBooking(b);
    expect(store.upcomingFor(pool).single.id, b.id);
  });

  test('a version 5 database is upgraded to bookings', () async {
    await store.close();
    final path = '${dir.path}/v5.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE restaurant_tables (id INTEGER PRIMARY KEY, name TEXT, type TEXT)');
          await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)');
          await db.execute(
            'CREATE TABLE table_sessions (id INTEGER PRIMARY KEY, restaurant_table_id INTEGER, status TEXT)',
          );
          await db.insert('restaurant_tables', {'id': 1, 'name': 'Pool', 'type': 'pool'});
          await db.insert('table_sessions', {'id': 1, 'restaurant_table_id': 1, 'status': 'open'});
        },
      ),
    );
    await old.close();
    final db = await AppDatabase.open(path, databaseFactoryFfi);
    Future<Set<Object?>> cols(String t) async =>
        (await db.rawQuery('PRAGMA table_info($t)')).map((r) => r['name']).toSet();
    expect(await cols('table_sessions'), containsAll(['customer_name', 'customer_phone', 'customer_id', 'booking_id']));
    expect(await cols('bookings'), containsAll(['customer_name', 'start_at', 'minutes', 'status', 'note']));
    expect((await db.query('table_sessions')).single['status'], 'open');
    await db.close();
    store = await AppStore.open(dbPath: '${dir.path}/test.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
  });

  test('a booked game pauses when its time runs out, once per booking', () async {
    await store.startTimer(pool, bookedMinutes: 60);
    final s = store.sessionFor(pool)!;

    // Time left: nothing happens.
    s.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 50));
    expect(store.pauseFinishedBookings(), isEmpty);
    expect(s.timerState, TimerState.running);

    // Time ran out 15 minutes ago (the app was closed): paused at the hour, no overtime.
    s.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 75));
    expect(store.pauseFinishedBookings(), [pool]);
    expect(s.timerState, TimerState.paused);
    expect(s.elapsedSeconds(), 60 * 60);
    expect(s.remainingSeconds(), 0);
    await store.timeUpSaves;
    expect(s.events.last.isTimeUpPause, isTrue);
    expect(s.events.last.at, s.timerPausedAt);

    // Saved: still paused at the hour after a reload.
    await store.reload();
    final reloaded = store.sessionFor(pool)!;
    expect(reloaded.timerState, TimerState.paused);
    expect(reloaded.elapsedSeconds(), 60 * 60);

    // Resumed without adding time: it runs on into overtime and is not paused again.
    await store.resumeTimer(pool);
    reloaded.pausedSeconds -= 10 * 60; // ten minutes of overtime played since
    expect(store.pauseFinishedBookings(), isEmpty);
    expect(reloaded.timerState, TimerState.running);
    expect(reloaded.elapsedSeconds(), closeTo(70 * 60, 2));

    // Time added: it pauses again when that runs out too.
    await store.extendBooking(pool, 30);
    expect(store.pauseFinishedBookings(), isEmpty);
    reloaded.pausedSeconds -= 25 * 60;
    expect(store.pauseFinishedBookings().map((t) => t.id), [pool.id]);
    expect(reloaded.elapsedSeconds(), 90 * 60);

    // Adding time to a game paused at time up carries it on straight away, with no overtime.
    await store.extendBooking(pool, 30);
    expect(reloaded.timerState, TimerState.running);
    expect(reloaded.bookedMinutes, 120);
    expect(reloaded.elapsedSeconds(), closeTo(90 * 60, 2));
    expect(reloaded.events.map((e) => e.type).toList().reversed.take(3), ['resume', 'extend', 'pause']);

    // A game staff paused themselves stays paused when time is added.
    await store.pauseTimer(pool);
    await store.extendBooking(pool, 30);
    expect(reloaded.timerState, TimerState.paused);
    expect(reloaded.bookedMinutes, 150);
  });

  test('time-up pause can be turned off, and open play never pauses', () async {
    await store.saveTable(RestaurantTable(name: 'Pool Table 2', type: 'pool', sort: 1));
    final open = store.activeTables.firstWhere((t) => t.isPool && t.id != pool.id);
    await store.startTimer(open);
    store.sessionFor(open)!.timerStartedAt = DateTime.now().subtract(const Duration(hours: 3));
    expect(store.pauseFinishedBookings(), isEmpty);

    await store.startTimer(pool, bookedMinutes: 60);
    store.sessionFor(pool)!.timerStartedAt = DateTime.now().subtract(const Duration(minutes: 75));
    store.settings.pauseWhenTimeUp = false;
    expect(store.pauseFinishedBookings(), isEmpty);
    expect(store.sessionFor(pool)!.timerState, TimerState.running);
  });

  test('booking reminders fire once each: soon, then due', () {
    final t = BookingReminderTracker();
    final start = DateTime(2026, 11, 21, 18);
    final b = Booking(id: 7, tableId: 1, customerName: 'Ravi', startAt: start, minutes: 60);
    DateTime m(int minutesBefore) => start.subtract(Duration(minutes: minutesBefore));
    expect(t.check(b, m(20), remindMinutes: 10), isNull);
    expect(t.check(b, m(10), remindMinutes: 10), BookingReminder.soon);
    expect(t.check(b, m(5), remindMinutes: 10), isNull);
    expect(t.check(b, m(0), remindMinutes: 10), BookingReminder.due);
    expect(t.check(b, m(-5), remindMinutes: 10), isNull);
    // After the slot has ended nothing more fires.
    final late = Booking(id: 8, tableId: 1, customerName: 'Late', startAt: start, minutes: 30);
    expect(t.check(late, m(-31), remindMinutes: 10), isNull);
    // Reminder off: only due.
    final off = Booking(id: 9, tableId: 1, customerName: 'Off', startAt: start, minutes: 60);
    expect(t.check(off, m(5), remindMinutes: 0), isNull);
    expect(t.check(off, m(-1), remindMinutes: 0), BookingReminder.due);
    t.forgetExcept({7});
    expect(t.check(off, m(-2), remindMinutes: 0), BookingReminder.due);
  });
}
