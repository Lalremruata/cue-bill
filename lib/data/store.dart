import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/billing.dart';
import '../services/analytics.dart';
import '../services/checkout.dart';
import 'database.dart';
import 'demo_sales.dart';
import 'models.dart';

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
  final Map<int, TableSession> _sessions = {}; // open sessions by table id
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

  Future<void> close() => _db.close();

  Future<void> _load() async {
    final s = await _db.query('settings', where: 'id = 1');
    settings = s.isEmpty
        ? BusinessSettings()
        : BusinessSettings.fromJson((jsonDecode(s.first['data'] as String) as Map).cast<String, Object?>());
    categories = (await _db.query('categories', orderBy: 'sort, name')).map(MenuCategory.fromRow).toList();
    menu = (await _db.query('menu_items', orderBy: 'name')).map(MenuItem.fromRow).toList();
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

  Future<void> _log(TableSession s, String type, {int? minutes, String? note}) async {
    final e = SessionEvent(sessionId: s.id!, type: type, minutes: minutes, note: note);
    final row = e.toRow()..remove('id');
    e.id = await _db.insert('session_events', row);
    s.events.add(e);
  }

  /// Starts the pool timer. [bookedMinutes] null or 0 = open play.
  Future<void> startTimer(RestaurantTable table, {int? bookedMinutes}) async {
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
    await _log(s, 'start', minutes: booked);
    await _saveSession(s);
  }

  Future<void> pauseTimer(RestaurantTable table) async {
    final s = sessionFor(table);
    if (s == null || s.timerState != TimerState.running) return;
    s.timerPausedAt = DateTime.now();
    await _log(s, 'pause');
    await _saveSession(s);
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
  Future<void> extendBooking(RestaurantTable table, int minutes) async {
    final s = sessionFor(table);
    if (s == null || minutes <= 0 || s.timerStartedAt == null || s.timerState == TimerState.stopped) return;
    final base = s.bookedMinutes ?? _roundToBlock((s.elapsedSeconds() / 60).ceil());
    s.bookedMinutes = base + minutes;
    await _log(s, 'extend', minutes: minutes);
    await _saveSession(s);
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
    });
    _sessions.remove(table.id);
    if (table.isTakeaway) tables.removeWhere((t) => t.id == table.id);
    notifyListeners();
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
      settings.nextInvoiceNumber = current.nextInvoiceNumber;
    });

    _sessions.remove(table.id);
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
