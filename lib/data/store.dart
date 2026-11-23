import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/billing.dart';
import '../core/format.dart';
import '../services/analytics.dart';
import '../services/checkout.dart';
import 'database.dart';
import 'demo_sales.dart';
import 'models.dart';

/// Something a booking would clash with: another booking, or the game in play.
typedef BookingConflict = ({String name, DateTime from, DateTime to, bool playing});

class CueBillException implements Exception {
  CueBillException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The app's single source of truth: loads menu, tables, open tables and settings
/// into memory, writes every change to SQLite, and notifies listeners.
class AppStore extends ChangeNotifier {
  AppStore._(this._db, this.dbPath, this._factory, this.filesDir);

  Database _db;
  final String dbPath;
  final DatabaseFactory _factory;

  /// Folder for logos and other files kept next to the database.
  final String filesDir;

  late BusinessSettings settings;
  List<MenuCategory> categories = [];
  List<MenuItem> menu = [];
  List<RestaurantTable> tables = [];

  /// Active regular customers, by name.
  List<Customer> customers = [];
  final Map<int, TableSession> _sessions = {}; // open sessions by table id

  /// Pool bookings that still hold a table (booked or playing), from today on, in time order.
  List<Booking> bookings = [];
  int invoiceCount = 0;

  /// The order line changed last, so the order panel can highlight it. Not saved.
  ({int tableId, int menuItemId, int serial})? lastTouched;
  int _touchSerial = 0;

  /// Bumped whenever invoices change, so dashboards and reports reload.
  int revision = 0;

  static Future<AppStore> open({
    required String dbPath,
    required DatabaseFactory factory,
    required String filesDir,
  }) async {
    final db = await AppDatabase.open(dbPath, factory);
    final store = AppStore._(db, dbPath, factory, filesDir);
    await store._load();
    return store;
  }

  Database get db => _db;

  Future<void> close() async {
    await _timeUpSaves;
    await _db.close();
  }

  /// Saves of tables paused by [pauseFinishedBookings], which runs on the clock tick.
  Future<void> _timeUpSaves = Future.value();

  /// Waits until tables paused by [pauseFinishedBookings] are saved.
  @visibleForTesting
  Future<void> get timeUpSaves => _timeUpSaves;

  Future<void> _load() async {
    final s = await _db.query('settings', where: 'id = 1');
    settings = s.isEmpty
        ? BusinessSettings()
        : BusinessSettings.fromJson((jsonDecode(s.first['data'] as String) as Map).cast<String, Object?>());
    categories = (await _db.query('categories', orderBy: 'sort, name')).map(MenuCategory.fromRow).toList();
    menu = (await _db.query('menu_items', orderBy: 'name')).map(MenuItem.fromRow).toList();
    customers = (await _db.query(
      'customers',
      where: 'is_active = 1',
      orderBy: 'name COLLATE NOCASE',
    )).map(Customer.fromRow).toList();
    // Billed takeaway orders stay in the database but are not loaded.
    tables = (await _db.query(
      'restaurant_tables',
      where: "type != 'takeaway' OR is_active = 1",
      orderBy: 'sort, name',
    )).map(RestaurantTable.fromRow).toList();

    _sessions.clear();
    final open = await _db.query('table_sessions', where: "status = 'open'", orderBy: 'id');
    for (final row in open) {
      final session = TableSession.fromRow(row);
      session.items = (await _db.query(
        'session_items',
        where: 'table_session_id = ?',
        whereArgs: [session.id],
        orderBy: 'id',
      )).map(SessionItem.fromRow).toList();
      session.events = (await _db.query(
        'session_events',
        where: 'table_session_id = ?',
        whereArgs: [session.id],
        orderBy: 'at, id',
      )).map(SessionEvent.fromRow).toList();
      _sessions[session.tableId] = session; // latest open session wins
    }
    invoiceCount = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM invoices')) ?? 0;
    // Earlier days' bookings that were never started stay on the Bookings page only.
    bookings = (await _db.query(
      'bookings',
      where: "status = 'playing' OR (status = 'booked' AND start_at + minutes * 60000 >= ?)",
      whereArgs: [startOfDay(DateTime.now()).millisecondsSinceEpoch],
      orderBy: 'start_at, id',
    )).map(Booking.fromRow).toList();
  }

  Future<void> reload() async {
    await _load();
    revision++;
    notifyListeners();
  }

  // ---------------------------------------------------------------- lookups

  Map<int, MenuItem> get menuById => {for (final m in menu) m.id!: m};
  Map<int, MenuCategory> get categoryById => {for (final c in categories) c.id!: c};
  RestaurantTable? tableById(int? id) => tables.where((t) => t.id == id).firstOrNull;

  static const _typeOrder = {'pool': 0, 'dining': 1};

  /// Active tables: pool first, then dining. Takeaway orders are in [takeawayOrders].
  List<RestaurantTable> get activeTables {
    final list = tables.where((t) => t.isActive && !t.isTakeaway).toList();
    list.sort((a, b) {
      final t = (_typeOrder[a.type] ?? 9).compareTo(_typeOrder[b.type] ?? 9);
      return t != 0 ? t : a.sort.compareTo(b.sort);
    });
    return list;
  }

  /// Takeaway orders not yet billed, oldest first.
  List<RestaurantTable> get takeawayOrders =>
      tables.where((t) => t.isTakeaway && t.isActive).toList()..sort((a, b) => a.id!.compareTo(b.id!));

  /// Menu items sorted by category order, then name.
  List<MenuItem> get sortedMenu {
    final cats = categoryById;
    final list = [...menu];
    list.sort((a, b) {
      final c = (cats[a.categoryId]?.sort ?? 0).compareTo(cats[b.categoryId]?.sort ?? 0);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  int get poolTableCount => tables.where((t) => t.isPool && t.isActive).length;

  TableSession? sessionFor(RestaurantTable table) => _sessions[table.id];

  BillCalc? calcFor(RestaurantTable table, {double discountPercent = 0, DateTime? now}) {
    final s = sessionFor(table);
    if (s == null) return null;
    return Checkout.calculate(
      settings: settings,
      table: table,
      session: s,
      menu: menuById,
      categories: categoryById,
      discountPercent: discountPercent,
      now: now,
    );
  }

  // ------------------------------------------------------- timer and orders

  /// Starts a takeaway order: no table, no pool timer. Orders are numbered Takeaway #1, #2, …
  /// from 1 each day. Each is billed or cleared on its own, then put away.
  Future<RestaurantTable> newTakeaway() async {
    final today = startOfDay(DateTime.now()).millisecondsSinceEpoch;
    late RestaurantTable table;
    late TableSession session;
    await _db.transaction((txn) async {
      final started = Sqflite.firstIntValue(
        await txn.rawQuery(
          '''SELECT COUNT(*) FROM table_sessions ts
             JOIN restaurant_tables rt ON rt.id = ts.restaurant_table_id
             WHERE rt.type = 'takeaway' AND ts.created_at >= ?''',
          [today],
        ),
      );
      table = RestaurantTable(name: 'Takeaway #${(started ?? 0) + 1}', type: 'takeaway');
      table.id = await txn.insert('restaurant_tables', table.toRow()..remove('id'));
      session = TableSession(tableId: table.id!);
      session.id = await txn.insert('table_sessions', session.toRow()..remove('id'));
    });
    tables.add(table);
    _sessions[table.id!] = session;
    notifyListeners();
    return table;
  }

  /// A billed or cleared takeaway order is put away; its invoice keeps the name.
  Future<void> _putAwayTakeaway(DatabaseExecutor db, RestaurantTable table) async {
    if (!table.isTakeaway) return;
    await db.update('restaurant_tables', {'is_active': 0}, where: 'id = ?', whereArgs: [table.id]);
  }

  Future<TableSession> ensureSession(RestaurantTable table) async {
    final existing = _sessions[table.id];
    if (existing != null) return existing;
    final s = TableSession(tableId: table.id!);
    final row = s.toRow()..remove('id');
    s.id = await _db.insert('table_sessions', row);
    _sessions[table.id!] = s;
    notifyListeners();
    return s;
  }

  Future<void> _saveSession(TableSession s) async {
    await _db.update('table_sessions', s.toRow(), where: 'id = ?', whereArgs: [s.id]);
    notifyListeners();
  }

  Future<void> _log(TableSession s, String type, {int? minutes, String? note, DateTime? at}) async {
    final e = SessionEvent(sessionId: s.id!, type: type, minutes: minutes, note: note, at: at);
    final row = e.toRow()..remove('id');
    e.id = await _db.insert('session_events', row);
    s.events.add(e);
  }

  /// Starts the pool timer. [bookedMinutes] null or 0 = open play.
  Future<void> startTimer(RestaurantTable table, {int? bookedMinutes, String? note}) async {
    final s = await ensureSession(table);
    if (s.timerStartedAt != null) return;
    final now = DateTime.now();
    final booked = (bookedMinutes ?? 0) > 0 ? bookedMinutes : null;
    s
      ..timerStartedAt = now
      ..timerPausedAt = null
      ..timerStoppedAt = null
      ..pausedSeconds = 0
      ..bookedMinutes = booked
      ..hourlyRate = settings.poolRateFor(table, now);
    await _log(s, 'start', minutes: booked, note: note);
    await _saveSession(s);
  }

  Future<void> pauseTimer(RestaurantTable table) async {
    final s = sessionFor(table);
    if (s == null || s.timerState != TimerState.running) return;
    s.timerPausedAt = DateTime.now();
    await _log(s, 'pause');
    await _saveSession(s);
  }

  /// Pauses every booked pool table whose booked time has run out, at the moment it ran
  /// out, so no overtime builds up while nobody is looking (or the app was closed).
  /// Each booking pauses once: resumed without adding time, the game runs on into
  /// overtime; after adding time it pauses again when that runs out. Off when
  /// [BusinessSettings.pauseWhenTimeUp] is. Returns the tables paused.
  ///
  /// The tables are paused in memory before this returns, so the caller sees the new
  /// state straight away; the database catches up in the background.
  List<RestaurantTable> pauseFinishedBookings([DateTime? now]) {
    if (!settings.pauseWhenTimeUp) return const [];
    final paused = <(RestaurantTable, TableSession, DateTime)>[];
    for (final (table, s) in openTables) {
      if (!table.isPool || !s.isBooked || s.timerState != TimerState.running) continue;
      final left = s.remainingSeconds(now);
      if (left == null || left > 0) continue;
      final booked = s.bookedMinutes!;
      if (s.events.any((e) => e.isTimeUpPause && e.minutes == booked)) continue;
      // The moment played time reached the booking.
      final endAt = s.timerStartedAt!.add(Duration(seconds: s.pausedSeconds + booked * 60));
      s.timerPausedAt = endAt;
      paused.add((table, s, endAt));
    }
    if (paused.isEmpty) return const [];
    notifyListeners();
    _timeUpSaves = _timeUpSaves.then((_) async {
      for (final (_, s, endAt) in paused) {
        await _log(s, 'pause', minutes: s.bookedMinutes, note: SessionEvent.timeUpNote, at: endAt);
        await _saveSession(s);
      }
    });
    return [for (final (t, _, _) in paused) t];
  }

  Future<void> resumeTimer(RestaurantTable table) async {
    final s = sessionFor(table);
    if (s == null || s.timerState != TimerState.paused) return;
    final paused = DateTime.now().difference(s.timerPausedAt!).inSeconds.abs();
    s.pausedSeconds += paused;
    s.timerPausedAt = null;
    await _log(s, 'resume', minutes: (paused / 60).round());
    await _saveSession(s);
  }

  Future<void> stopTimer(RestaurantTable table) async {
    final s = sessionFor(table);
    if (s == null) return;
    final state = s.timerState;
    if (state == TimerState.running || state == TimerState.paused) {
      s.timerStoppedAt = s.timerPausedAt ?? DateTime.now();
      await _log(s, 'stop', minutes: (s.elapsedSeconds() / 60).ceil());
      await _saveSession(s);
    }
  }

  /// Adds time to a booked table (+30 min, +1 hour). An open-play table becomes booked
  /// for the time played so far, rounded up to the billing block, plus [minutes].
  /// A game paused because its time ran out carries on straight away; one staff paused
  /// themselves stays paused.
  Future<void> extendBooking(RestaurantTable table, int minutes) async {
    await _timeUpSaves;
    final s = sessionFor(table);
    if (s == null || minutes <= 0 || s.timerStartedAt == null || s.timerState == TimerState.stopped) return;
    final base = s.bookedMinutes ?? _roundToBlock((s.elapsedSeconds() / 60).ceil());
    s.bookedMinutes = base + minutes;
    await _log(s, 'extend', minutes: minutes);
    await _saveSession(s);
    final lastPause = s.events.where((e) => e.type == 'pause').lastOrNull;
    if (s.timerState == TimerState.paused && (lastPause?.isTimeUpPause ?? false)) await resumeTimer(table);
  }

  int _roundToBlock(int minutes) {
    final block = settings.billingBlockMinutes;
    return block > 1 ? (minutes / block).ceil() * block : minutes;
  }

  /// Corrects a table by hand: change the booking ([bookedMinutes] 0 = open play) and/or
  /// add (+) or remove (−) played minutes, e.g. when the timer was started late.
  /// Every change is kept in the table's history. A [reason] is required when played
  /// time changes or the booking is cut, since both lower or rewrite the bill.
  Future<void> adjustTimer(
    RestaurantTable table, {
    required int? bookedMinutes,
    int playedDeltaMinutes = 0,
    String reason = '',
  }) async {
    final s = sessionFor(table);
    if (s == null || s.timerStartedAt == null) return;
    if (adjustNeedsReason(s, bookedMinutes: bookedMinutes, playedDeltaMinutes: playedDeltaMinutes) &&
        reason.trim().isEmpty) {
      throw CueBillException('Give a reason for the change.');
    }
    final note = reason.trim().isEmpty ? null : reason.trim();

    if (playedDeltaMinutes != 0) {
      final elapsed = s.elapsedSeconds();
      if (elapsed + playedDeltaMinutes * 60 < 0) {
        throw CueBillException('Played time cannot go below zero.');
      }
      // Moving the start earlier adds played time; pauses are unaffected.
      s.timerStartedAt = s.timerStartedAt!.subtract(Duration(minutes: playedDeltaMinutes));
      await _log(s, 'adjust', minutes: playedDeltaMinutes, note: note);
    }

    final booked = (bookedMinutes ?? 0) > 0 ? bookedMinutes : null;
    if (booked != s.bookedMinutes) {
      s.bookedMinutes = booked;
      await _log(s, 'booking', minutes: booked ?? 0, note: note);
    }
    await _saveSession(s);
  }

  static bool adjustNeedsReason(TableSession s, {required int? bookedMinutes, int playedDeltaMinutes = 0}) {
    final before = s.bookedMinutes ?? 0;
    final after = bookedMinutes ?? 0;
    final cut = before > 0 && after < before; // includes booked → open play
    return playedDeltaMinutes != 0 || cut;
  }

  /// Open tables, for the booking alerts.
  Iterable<(RestaurantTable, TableSession)> get openTables sync* {
    for (final t in activeTables) {
      final s = _sessions[t.id];
      if (s != null) yield (t, s);
    }
  }

  /// Time played so far on pool tables that are open (not yet paid), in seconds.
  /// Paid time is on the invoices; this is the part the reports cannot see yet.
  int livePoolSeconds([DateTime? now]) {
    var total = 0;
    for (final (t, s) in openTables) {
      if (t.isPool && s.timerStartedAt != null) total += s.elapsedSeconds(now);
    }
    return total;
  }

  /// Pool tables with the timer running right now.
  int get poolTablesPlaying => openTables.where((e) => e.$1.isPool && e.$2.timerState == TimerState.running).length;

  Future<void> addItem(RestaurantTable table, MenuItem item, [int qty = 1]) async {
    final s = await ensureSession(table);
    final line = s.items.where((l) => l.menuItemId == item.id).firstOrNull;
    if (line != null) {
      line.qty += qty;
      await _db.update('session_items', {'qty': line.qty}, where: 'id = ?', whereArgs: [line.id]);
    } else {
      final l = SessionItem(sessionId: s.id!, menuItemId: item.id!, qty: qty);
      l.id = await _db.insert('session_items', {'table_session_id': s.id, 'menu_item_id': item.id, 'qty': qty});
      s.items.add(l);
    }
    _touch(table, item.id!);
    notifyListeners();
  }

  void _touch(RestaurantTable table, int menuItemId) =>
      lastTouched = (tableId: table.id!, menuItemId: menuItemId, serial: ++_touchSerial);

  /// Sets a line's quantity directly (typed in); 0 removes the line.
  Future<void> setQty(RestaurantTable table, int menuItemId, int qty) async {
    final line = sessionFor(table)?.items.where((l) => l.menuItemId == menuItemId).firstOrNull;
    if (line == null || qty == line.qty) return;
    await changeQty(table, menuItemId, qty - line.qty);
  }

  /// Removing the last one deletes the line.
  Future<void> changeQty(RestaurantTable table, int menuItemId, int delta) async {
    final s = sessionFor(table);
    final line = s?.items.where((l) => l.menuItemId == menuItemId).firstOrNull;
    if (s == null || line == null) return;
    final qty = line.qty + delta;
    if (qty > 0) {
      line.qty = qty;
      await _db.update('session_items', {'qty': qty}, where: 'id = ?', whereArgs: [line.id]);
      _touch(table, menuItemId);
    } else {
      s.items.remove(line);
      await _db.delete('session_items', where: 'id = ?', whereArgs: [line.id]);
    }
    notifyListeners();
  }

  /// Close a session without billing (table opened by mistake, order cancelled).
  Future<void> clearTable(RestaurantTable table) async {
    final s = sessionFor(table);
    if (s == null) return;
    await _db.transaction((txn) async {
      await txn.delete('session_items', where: 'table_session_id = ?', whereArgs: [s.id]);
      await txn.update(
        'table_sessions',
        {'status': 'closed', 'timer_stopped_at': (s.timerStoppedAt ?? DateTime.now()).millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [s.id],
      );
      await _putAwayTakeaway(txn, table);
      if (s.bookingId != null) {
        await txn.update(
          'bookings',
          {'status': 'cancelled', 'cancel_reason': 'Table cleared'},
          where: "id = ? AND status = 'playing'",
          whereArgs: [s.bookingId],
        );
      }
    });
    _sessions.remove(table.id);
    if (table.isTakeaway) tables.removeWhere((t) => t.id == table.id);
    bookings.removeWhere((b) => b.id == s.bookingId && b.isPlaying);
    bookingRevision++;
    notifyListeners();
  }

  // ------------------------------------------------------------- bookings

  /// Bumped whenever a booking changes, so the Bookings page reloads.
  int bookingRevision = 0;

  Booking? bookingById(int? id) => id == null ? null : bookings.where((b) => b.id == id).firstOrNull;

  /// The booking the game on [table] was started from.
  Booking? playingBooking(RestaurantTable table) => bookingById(_sessions[table.id]?.bookingId);

  /// Bookings on [table] not yet started, soonest first. Late ones stay until started,
  /// marked no-show or cancelled.
  List<Booking> upcomingFor(RestaurantTable table) =>
      bookings.where((b) => b.tableId == table.id && b.isUpcoming).toList();

  /// Upcoming bookings on [table] for the day of [now].
  List<Booking> todayFor(RestaurantTable table, [DateTime? now]) {
    final end = endOfDay(now ?? DateTime.now());
    return upcomingFor(table).where((b) => !b.startAt.isAfter(end)).toList();
  }

  /// The next booking on [table] that has not run out yet.
  Booking? nextBookingFor(RestaurantTable table, [DateTime? now]) {
    final n = now ?? DateTime.now();
    return upcomingFor(table).where((b) => b.endAt.isAfter(n)).firstOrNull;
  }

  /// Everything booked on [day], including done, cancelled and no-shows, in time order.
  Future<List<Booking>> bookingsOn(DateTime day) async {
    final rows = await _db.query(
      'bookings',
      where: 'start_at BETWEEN ? AND ?',
      whereArgs: [startOfDay(day).millisecondsSinceEpoch, endOfDay(day).millisecondsSinceEpoch],
      orderBy: 'start_at, id',
    );
    return rows.map(Booking.fromRow).toList();
  }

  /// What [b] would clash with on its table: other bookings not yet started, and the game in
  /// play until its booked time runs out. Open play has no end, so it clashes with nothing.
  List<BookingConflict> bookingConflicts(Booking b, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final from = b.startAt, to = b.minutes > 0 ? b.endAt : b.startAt.add(const Duration(minutes: 1));
    final out = <BookingConflict>[
      for (final o in bookings)
        if (o.id != b.id && o.tableId == b.tableId && o.isUpcoming && o.overlapsRange(from, to))
          (name: o.customerName, from: o.startAt, to: o.endAt, playing: false),
    ];
    final s = _sessions[b.tableId];
    if (s != null && s.bookingId != b.id && s.timerStartedAt != null && s.timerState != TimerState.stopped) {
      final end = s.expectedEnd(n);
      if (end != null && from.isBefore(end) && n.isBefore(to)) {
        out.insert(0, (name: s.customerName ?? 'Game in play', from: s.timerStartedAt!, to: end, playing: true));
      }
    }
    return out;
  }

  static String describeConflict(BookingConflict c) => c.playing
      ? '${c.name} is playing until ${Fmt.time(c.to)}'
      : 'Overlaps ${c.name}, ${Fmt.time(c.from)}–${Fmt.time(c.to)}';

  void _tidyBooking(Booking b, {bool walkIn = false}) {
    b.customerName = b.customerName.trim();
    if (b.customerName.isEmpty) throw CueBillException("Enter the customer's name.");
    if (b.minutes < 0 || (b.minutes == 0 && !walkIn)) throw CueBillException('Pick how long the booking is for.');
    b.customerPhone = Customer.normalisePhone(b.customerPhone);
    final note = b.note?.trim() ?? '';
    b.note = note.isEmpty ? null : note;
    if (tableById(b.tableId) == null) throw CueBillException('Pick a pool table.');
  }

  /// Adds or changes a booking. Clashes are refused unless [allowOverlap], so staff decide.
  Future<Booking> saveBooking(Booking b, {bool allowOverlap = false}) async {
    _tidyBooking(b);
    if (b.id != null && !b.isUpcoming) throw CueBillException('Only bookings not yet started can be changed.');
    if (!allowOverlap) {
      final clash = bookingConflicts(b);
      if (clash.isNotEmpty) throw CueBillException(describeConflict(clash.first));
    }
    final row = b.toRow()..remove('id');
    if (b.id == null) {
      b.id = await _db.insert('bookings', row);
    } else {
      await _db.update('bookings', row, where: 'id = ?', whereArgs: [b.id]);
    }
    bookings
      ..removeWhere((o) => o.id == b.id)
      ..add(b)
      ..sort(_byStart);
    bookingRevision++;
    notifyListeners();
    return b;
  }

  static int _byStart(Booking a, Booking b) {
    final c = a.startAt.compareTo(b.startAt);
    return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
  }

  Future<void> _setBookingStatus(Booking b, String status, {String? reason}) async {
    b
      ..status = status
      ..cancelReason = reason;
    await _db.update('bookings', {'status': status, 'cancel_reason': reason}, where: 'id = ?', whereArgs: [b.id]);
    bookings.removeWhere((o) => o.id == b.id);
    if (b.isActive) {
      bookings
        ..add(b)
        ..sort(_byStart);
    }
    bookingRevision++;
    notifyListeners();
  }

  Future<void> cancelBooking(Booking b, {String? reason}) async {
    if (!b.isUpcoming) throw CueBillException('Only bookings not yet started can be cancelled.');
    final r = reason?.trim() ?? '';
    await _setBookingStatus(b, 'cancelled', reason: r.isEmpty ? null : r);
  }

  Future<void> markNoShow(Booking b) async {
    if (!b.isUpcoming) throw CueBillException('Only bookings not yet started can be marked as no-show.');
    await _setBookingStatus(b, 'no_show');
  }

  /// Puts a cancelled or no-show booking back on the list.
  Future<void> restoreBooking(Booking b) async {
    if (b.status != 'cancelled' && b.status != 'no_show') return;
    await _setBookingStatus(b, 'booked');
  }

  /// The customer has arrived: open the table and start the game for the booked time.
  /// The booked slot stays as it was; billing counts from now.
  Future<void> startBooking(Booking b) async {
    final table = tableById(b.tableId);
    if (table == null) throw CueBillException('That pool table no longer exists.');
    if (!b.isUpcoming) throw CueBillException('This booking is not waiting to start.');
    final open = _sessions[table.id];
    if (open != null && open.timerStartedAt != null) {
      throw CueBillException('${table.name} is in use. End the current game first.');
    }
    final s = await ensureSession(table);
    s
      ..customerName = b.customerName
      ..customerPhone = b.customerPhone
      ..customerId = b.customerId
      ..bookingId = b.id;
    await startTimer(table, bookedMinutes: b.minutes, note: b.customerName);
    b
      ..status = 'playing'
      ..sessionId = s.id;
    await _db.update('bookings', {'status': 'playing', 'table_session_id': s.id}, where: 'id = ?', whereArgs: [b.id]);
    bookingRevision++;
    notifyListeners();
  }

  /// A walk-in: a booking from now for [minutes] (0 = open play), started right away.
  Future<Booking> startWalkIn(
    RestaurantTable table, {
    required String name,
    String? phone,
    int? customerId,
    required int minutes,
    String? note,
    bool allowOverlap = false,
  }) async {
    final open = _sessions[table.id];
    if (open != null && open.timerStartedAt != null) {
      throw CueBillException('${table.name} is in use. End the current game first.');
    }
    final b = Booking(
      tableId: table.id!,
      customerName: name,
      customerPhone: phone,
      customerId: customerId,
      note: note,
      startAt: DateTime.now(),
      minutes: minutes,
    );
    _tidyBooking(b, walkIn: true);
    if (!allowOverlap) {
      final clash = bookingConflicts(b);
      if (clash.isNotEmpty) throw CueBillException(describeConflict(clash.first));
    }
    b.id = await _db.insert('bookings', b.toRow()..remove('id'));
    bookings
      ..add(b)
      ..sort(_byStart);
    await startBooking(b);
    return b;
  }

  /// Bookings not yet started whose time overlaps the game in play on [table], if it runs to
  /// its booked end (after [extraMinutes] more), e.g. before adding time.
  List<Booking> bookingsHitBy(RestaurantTable table, {int extraMinutes = 0, DateTime? now}) {
    final s = _sessions[table.id];
    final n = now ?? DateTime.now();
    final end = s?.expectedEnd(n)?.add(Duration(minutes: extraMinutes));
    if (end == null) return [];
    return upcomingFor(table).where((b) => b.startAt.isBefore(end) && b.endAt.isAfter(n)).toList();
  }

  // ------------------------------------------------------------- checkout

  /// Save the sale: create the invoice, close the table and bump the invoice number.
  Future<Invoice> completeSale(RestaurantTable table, CheckoutOptions options) async {
    final session = sessionFor(table);
    if (session == null) throw CueBillException('This table has already been checked out.');

    final calc = calcFor(table, discountPercent: options.discountPercent)!;
    if (calc.isEmpty) throw CueBillException('Nothing to bill yet.');

    late Invoice invoice;
    await _db.transaction((txn) async {
      final fresh = await txn.query('table_sessions', where: 'id = ?', whereArgs: [session.id]);
      if (fresh.isEmpty || fresh.first['status'] != 'open') {
        throw CueBillException('This table has already been checked out.');
      }
      final s = await txn.query('settings', where: 'id = 1');
      final current = BusinessSettings.fromJson((jsonDecode(s.first['data'] as String) as Map).cast<String, Object?>());

      // Skip any number already used (e.g. if the next number was set back by hand).
      var n = current.nextInvoiceNumber;
      while ((Sqflite.firstIntValue(
                await txn.rawQuery('SELECT COUNT(*) FROM invoices WHERE number = ?', [current.invoiceNumber(n)]),
              ) ??
              0) >
          0) {
        n++;
      }
      final number = current.invoiceNumber(n);
      current.nextInvoiceNumber = n + 1;
      await txn.update('settings', {'data': jsonEncode(current.toJson())}, where: 'id = 1');

      String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
      final t = calc.totals;
      invoice = Invoice(
        number: number,
        tableSessionId: session.id,
        tableName: table.name,
        orderType: table.orderType,
        customerName: clean(options.customerName),
        customerPhone: clean(options.customerPhone),
        customerId: options.customerId,
        paymentMethod: options.paymentMethod,
        cashReceived: options.paymentMethod == 'cash' ? options.cashReceived : null,
        poolStartedAt: calc.isPool ? calc.poolStartedAt : null,
        poolEndedAt: calc.poolEndedAt,
        poolPlayedMinutes: calc.playedMinutes,
        poolBilledMinutes: calc.billedMinutes,
        poolBookedMinutes: calc.isPool ? calc.bookedMinutes : null,
        poolRate: calc.billedMinutes > 0 ? calc.rate : 0,
        poolAmount: calc.poolAmount,
        poolCost: calc.poolCost,
        itemsSubtotal: calc.itemsSubtotal,
        itemsCost: calc.itemsCost,
        discountPercent: calc.discountPercent,
        discountAmount: t.discount,
        gstPool: t.gstPool,
        gstFood: t.gstFood,
        gstPoolRate: current.gstPoolRate,
        gstFoodRate: current.gstFoodRate,
        roundOff: t.roundOff,
        total: t.total,
        netRevenue: t.netRevenue,
        totalCost: roundTo(calc.poolCost + calc.itemsCost, 2),
        business: current.snapshot(),
        paidAt: DateTime.now(),
        items: calc.items,
      );
      final row = invoice.toRow()..remove('id');
      invoice.id = await txn.insert('invoices', row);
      for (final item in invoice.items) {
        item.invoiceId = invoice.id;
        final r = item.toRow()..remove('id');
        item.id = await txn.insert('invoice_items', r);
      }
      await txn.update(
        'table_sessions',
        {'status': 'closed', 'timer_stopped_at': (calc.poolEndedAt ?? session.timerStoppedAt)?.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [session.id],
      );
      await _putAwayTakeaway(txn, table);
      if (session.bookingId != null) {
        // Record the time the game actually took, so the day's bookings show it.
        final took = calc.bookedMinutes ?? calc.billedMinutes;
        await txn.update(
          'bookings',
          {'status': 'done', if (took > 0) 'minutes': took},
          where: 'id = ?',
          whereArgs: [session.bookingId],
        );
      }
      settings.nextInvoiceNumber = current.nextInvoiceNumber;
    });

    _sessions.remove(table.id);
    bookings.removeWhere((b) => b.id == session.bookingId);
    bookingRevision++;
    if (table.isTakeaway) tables.removeWhere((t) => t.id == table.id);
    invoiceCount++;
    revision++;
    notifyListeners();
    return invoice;
  }

  // ------------------------------------------------------------- invoices

  Future<List<Invoice>> _withItems(List<Map<String, Object?>> rows) async {
    final invoices = rows.map(Invoice.fromRow).toList();
    if (invoices.isEmpty) return invoices;
    final byId = {for (final i in invoices) i.id!: i};
    const chunk = 500;
    final ids = byId.keys.toList();
    for (var start = 0; start < ids.length; start += chunk) {
      final part = ids.sublist(start, (start + chunk).clamp(0, ids.length));
      final items = await _db.query(
        'invoice_items',
        where: 'invoice_id IN (${List.filled(part.length, '?').join(',')})',
        whereArgs: part,
        orderBy: 'id',
      );
      for (final r in items) {
        final item = InvoiceItem.fromRow(r);
        byId[item.invoiceId]?.items.add(item);
      }
    }
    return invoices;
  }

  Future<List<Invoice>> invoicesBetween(DateTime from, DateTime to, {String? payment, String? orderType}) async {
    final where = StringBuffer('paid_at BETWEEN ? AND ?');
    final args = <Object>[startOfDay(from).millisecondsSinceEpoch, endOfDay(to).millisecondsSinceEpoch];
    if (payment != null) {
      where.write(' AND payment_method = ?');
      args.add(payment);
    }
    if (orderType != null) {
      where.write(' AND order_type = ?');
      args.add(orderType);
    }
    final rows = await _db.query('invoices', where: where.toString(), whereArgs: args, orderBy: 'paid_at DESC');
    return _withItems(rows);
  }

  Future<List<Invoice>> recentInvoices({int limit = 50, int offset = 0, String? search}) async {
    final q = search?.trim() ?? '';
    final rows = await _db.query(
      'invoices',
      where: q.isEmpty ? null : 'number LIKE ? OR table_name LIKE ? OR customer_name LIKE ? OR customer_phone LIKE ?',
      whereArgs: q.isEmpty ? null : List.filled(4, '%$q%'),
      orderBy: 'paid_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return _withItems(rows);
  }

  Future<SalesAnalytics> analytics(DateTime from, DateTime to, {String? payment, String? orderType}) async {
    return SalesAnalytics(
      from: from,
      to: to,
      payment: payment,
      orderType: orderType,
      invoices: await invoicesBetween(from, to, payment: payment, orderType: orderType),
      activeMenu: menu.where((m) => m.isActive).toList(),
      categories: categoryById,
      poolTables: poolTableCount,
    );
  }

  // ------------------------------------------------------------ customers

  Customer? customerById(int? id) => id == null ? null : customers.where((c) => c.id == id).firstOrNull;

  /// Regulars whose phone contains the typed digits or whose name contains the typed text.
  List<Customer> searchCustomers(String query, {int limit = 6}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final phoneOnly = digits.isNotEmpty && RegExp(r'^[\d\s+()-]+$').hasMatch(q);
    return customers
        .where(
          (c) => phoneOnly
              ? (c.phone ?? '').contains(Customer.normalisePhone(q) ?? digits)
              : c.name.toLowerCase().contains(q),
        )
        .take(limit)
        .toList();
  }

  /// The regular with exactly this phone, if any.
  Customer? customerByPhone(String? phone) {
    final p = Customer.normalisePhone(phone);
    return p == null ? null : customers.where((c) => c.phone == p).firstOrNull;
  }

  Future<Customer> saveCustomer(Customer c) async {
    c.name = c.name.trim();
    if (c.name.isEmpty) throw CueBillException('Enter a name.');
    c.phone = Customer.normalisePhone(c.phone);
    if (c.phone != null && customers.any((o) => o.phone == c.phone && o.id != c.id)) {
      throw CueBillException('A customer with this phone already exists.');
    }
    c.discountPercent = c.discountPercent.clamp(0, 100).toDouble();
    final row = c.toRow()..remove('id');
    if (c.id == null) {
      c.id = await _db.insert('customers', row);
      customers.add(c);
    } else {
      await _db.update('customers', row, where: 'id = ?', whereArgs: [c.id]);
    }
    customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    revision++;
    notifyListeners();
    return c;
  }

  /// Hides the customer. Their invoices keep the link; the phone is freed for a new record.
  Future<void> deleteCustomer(Customer c) async {
    await _db.update('customers', {'is_active': 0, 'phone': null}, where: 'id = ?', whereArgs: [c.id]);
    customers.removeWhere((o) => o.id == c.id);
    revision++;
    notifyListeners();
  }

  /// Which regular an invoice belongs to: the one picked at checkout, or else the one whose
  /// phone matches (sales from before the customer was saved).
  int? _customerFor(Object? customerId, Object? phone, Map<String, int> byPhone) {
    if (customerId != null) return (customerId as num).toInt();
    final p = Customer.normalisePhone(phone as String?);
    return p == null ? null : byPhone[p];
  }

  /// Visits, spend and last visit for every regular, from one pass over the invoices.
  Future<Map<int, CustomerStats>> customerStatsAll() async {
    final byPhone = {
      for (final c in customers)
        if (c.phone != null) c.phone!: c.id!,
    };
    final rows = await _db.rawQuery(
      'SELECT customer_id, customer_phone, total, paid_at FROM invoices '
      'WHERE customer_id IS NOT NULL OR customer_phone IS NOT NULL',
    );
    final out = <int, CustomerStats>{};
    for (final r in rows) {
      final id = _customerFor(r['customer_id'], r['customer_phone'], byPhone);
      if (id == null) continue;
      final paid = DateTime.fromMillisecondsSinceEpoch((r['paid_at'] as num).toInt());
      final prev = out[id] ?? (visits: 0, spend: 0.0, lastVisit: null);
      out[id] = (
        visits: prev.visits + 1,
        spend: roundTo(prev.spend + (r['total'] as num).toDouble(), 2),
        lastVisit: prev.lastVisit == null || paid.isAfter(prev.lastVisit!) ? paid : prev.lastVisit,
      );
    }
    return out;
  }

  Future<CustomerStats> customerStats(Customer c) async =>
      (await customerStatsAll())[c.id] ?? (visits: 0, spend: 0.0, lastVisit: null);

  /// A customer's invoices, newest first.
  Future<List<Invoice>> customerInvoices(Customer c, {int limit = 50}) async {
    final rows = await _db.query(
      'invoices',
      where: c.phone == null
          ? 'customer_id = ?'
          : 'customer_id = ? OR (customer_id IS NULL AND customer_phone IS NOT NULL)',
      whereArgs: [c.id],
      orderBy: 'paid_at DESC, id DESC',
    );
    final mine = rows
        .where((r) => r['customer_id'] != null || Customer.normalisePhone(r['customer_phone'] as String?) == c.phone)
        .take(limit)
        .toList();
    return _withItems(mine);
  }

  // ----------------------------------------------------------------- menu

  Future<void> saveMenuItem(MenuItem item) async {
    final row = item.toRow()..remove('id');
    if (item.id == null) {
      item.id = await _db.insert('menu_items', row);
      menu.add(item);
    } else {
      await _db.update('menu_items', row, where: 'id = ?', whereArgs: [item.id]);
      final i = menu.indexWhere((m) => m.id == item.id);
      if (i >= 0) menu[i] = item;
    }
    notifyListeners();
  }

  Future<void> deleteMenuItem(MenuItem item) async {
    await _db.delete('menu_items', where: 'id = ?', whereArgs: [item.id]);
    menu.removeWhere((m) => m.id == item.id);
    for (final s in _sessions.values) {
      s.items.removeWhere((l) => l.menuItemId == item.id);
    }
    notifyListeners();
  }

  Future<void> saveCategory(MenuCategory c) async {
    final row = c.toRow()..remove('id');
    if (c.id == null) {
      c.id = await _db.insert('categories', row);
      categories.add(c);
    } else {
      await _db.update('categories', row, where: 'id = ?', whereArgs: [c.id]);
    }
    categories.sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> deleteCategory(MenuCategory c) async {
    await _db.delete('categories', where: 'id = ?', whereArgs: [c.id]);
    await reload();
  }

  Future<void> saveTable(RestaurantTable t) async {
    final row = t.toRow()..remove('id');
    if (t.id == null) {
      t.id = await _db.insert('restaurant_tables', row);
      tables.add(t);
    } else {
      await _db.update('restaurant_tables', row, where: 'id = ?', whereArgs: [t.id]);
    }
    tables.sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> deleteTable(RestaurantTable t) async {
    await _db.delete('restaurant_tables', where: 'id = ?', whereArgs: [t.id]);
    await reload();
  }

  // ------------------------------------------------------------- settings

  Future<void> saveSettings(BusinessSettings next) async {
    next.savedAt = DateTime.now();
    await _db.update('settings', {'data': jsonEncode(next.toJson())}, where: 'id = 1');
    settings = next;
    notifyListeners();
  }

  /// Saves bookkeeping fields (backup times, Drive folder) without marking the settings as edited.
  Future<void> updateSettings(void Function(BusinessSettings s) change) async {
    change(settings);
    await _db.update('settings', {'data': jsonEncode(settings.toJson())}, where: 'id = 1');
    notifyListeners();
  }

  /// Copies the logo into the app folder under a new name, so old invoices keep their logo.
  Future<String> storeLogo(Uint8List bytes, String extension) async {
    final dir = Directory(p.join(filesDir, 'logos'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'logo-${DateTime.now().millisecondsSinceEpoch}.$extension'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // --------------------------------------------------------------- backup

  /// A consistent copy of the whole database.
  Future<Uint8List> backupBytes() async {
    final tmp = p.join(filesDir, 'backup-${DateTime.now().millisecondsSinceEpoch}.sqlite');
    await Directory(filesDir).create(recursive: true);
    Uint8List bytes;
    try {
      await _db.execute('VACUUM INTO ?', [tmp]);
      final file = File(tmp);
      bytes = await file.readAsBytes();
      await file.delete();
    } on Object {
      // Older SQLite (before 3.27) has no VACUUM INTO: flush the journal and copy the file.
      try {
        await _db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } on Object {
        // Not in WAL mode: nothing to flush.
      }
      bytes = await File(dbPath).readAsBytes();
    }
    settings.lastBackupAt = DateTime.now();
    await _db.update('settings', {'data': jsonEncode(settings.toJson())}, where: 'id = 1');
    notifyListeners();
    return bytes;
  }

  /// Replace all data with a backup file made by [backupBytes].
  Future<void> restore(Uint8List bytes) async {
    const header = 'SQLite format 3';
    if (bytes.length < 100 || String.fromCharCodes(bytes.sublist(0, header.length)) != header) {
      throw CueBillException('That file is not a CueBill backup.');
    }
    final tmp = '$dbPath.restore';
    await File(tmp).writeAsBytes(bytes, flush: true);
    final check = await _factory.openDatabase(tmp, options: OpenDatabaseOptions(readOnly: true));
    try {
      final names = (await check.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((r) => r['name']).toSet();
      if (!names.containsAll(['settings', 'invoices', 'menu_items', 'restaurant_tables'])) {
        throw CueBillException('That file is not a CueBill backup.');
      }
    } finally {
      await check.close();
    }
    await _db.close();
    await File(tmp).rename(dbPath);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
    _db = await AppDatabase.open(dbPath, _factory);
    await reload();
  }

  /// Fills the last 45 days with sample sales so the dashboard and reports have something to show.
  Future<int> loadSampleSales() async {
    final count = await DemoSales.generate(this);
    await reload();
    return count;
  }
}
