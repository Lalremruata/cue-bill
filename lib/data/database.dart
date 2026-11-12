import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// SQLite schema (mirrors the Laravel migration) and first-run seed data.
class AppDatabase {
  AppDatabase._();

  static const version = 2;

  static Future<Database> open(String path, DatabaseFactory factory) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await createSchema(db);
          await seed(db);
        },
        onUpgrade: upgrade,
      ),
    );
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    const statements = [
      // Single row: the whole BusinessSettings object as JSON.
      'CREATE TABLE settings (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
      '''CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'food',
        sort INTEGER NOT NULL DEFAULT 0)''',
      '''CREATE TABLE menu_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        cost_price REAL NOT NULL DEFAULT 0,
        price REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE restaurant_tables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'dining',
        hourly_rate REAL,
        sort INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE table_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        restaurant_table_id INTEGER NOT NULL REFERENCES restaurant_tables(id) ON DELETE CASCADE,
        status TEXT NOT NULL DEFAULT 'open',
        timer_started_at INTEGER,
        timer_paused_at INTEGER,
        paused_seconds INTEGER NOT NULL DEFAULT 0,
        timer_stopped_at INTEGER,
        hourly_rate REAL,
        booked_minutes INTEGER,
        created_at INTEGER)''',
      'CREATE INDEX table_sessions_status ON table_sessions (restaurant_table_id, status)',
      '''CREATE TABLE session_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_session_id INTEGER NOT NULL REFERENCES table_sessions(id) ON DELETE CASCADE,
        menu_item_id INTEGER NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
        qty INTEGER NOT NULL DEFAULT 1,
        UNIQUE (table_session_id, menu_item_id))''',
      '''CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number TEXT NOT NULL UNIQUE,
        table_session_id INTEGER REFERENCES table_sessions(id) ON DELETE SET NULL,
        table_name TEXT NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        payment_method TEXT NOT NULL,
        cash_received REAL,
        pool_started_at INTEGER,
        pool_ended_at INTEGER,
        pool_played_minutes INTEGER NOT NULL DEFAULT 0,
        pool_billed_minutes INTEGER NOT NULL DEFAULT 0,
        pool_booked_minutes INTEGER,
        pool_rate REAL NOT NULL DEFAULT 0,
        pool_amount REAL NOT NULL DEFAULT 0,
        pool_cost REAL NOT NULL DEFAULT 0,
        items_subtotal REAL NOT NULL DEFAULT 0,
        items_cost REAL NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        gst_pool REAL NOT NULL DEFAULT 0,
        gst_food REAL NOT NULL DEFAULT 0,
        gst_pool_rate REAL NOT NULL DEFAULT 0,
        gst_food_rate REAL NOT NULL DEFAULT 0,
        round_off REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        net_revenue REAL NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0,
        business TEXT NOT NULL,
        paid_at INTEGER NOT NULL,
        created_at INTEGER)''',
      'CREATE INDEX invoices_paid_at ON invoices (paid_at)',
      '''CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
        menu_item_id INTEGER REFERENCES menu_items(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        category_name TEXT,
        category_type TEXT,
        qty INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost REAL NOT NULL DEFAULT 0,
        amount REAL NOT NULL)''',
      'CREATE INDEX invoice_items_invoice ON invoice_items (invoice_id)',
      _sessionEvents,
      _sessionEventsIndex,
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  /// Timer history for each table: start, pause, resume, extend, adjust, stop.
  static const _sessionEvents = '''CREATE TABLE session_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_session_id INTEGER NOT NULL REFERENCES table_sessions(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        minutes INTEGER,
        note TEXT,
        at INTEGER NOT NULL)''';
  static const _sessionEventsIndex = 'CREATE INDEX session_events_session ON session_events (table_session_id)';

  /// Brings an older database (or an older backup being restored) up to [version].
  static Future<void> upgrade(Database db, int from, int to) async {
    if (from < 2) {
      // v2: booked pool time and the timer history.
      await db.execute('ALTER TABLE table_sessions ADD COLUMN booked_minutes INTEGER');
      await db.execute('ALTER TABLE invoices ADD COLUMN pool_booked_minutes INTEGER');
      await db.execute(_sessionEvents);
      await db.execute(_sessionEventsIndex);
    }
  }

  /// Menu, tables and default settings (port of DatabaseSeeder).
  static Future<void> seed(DatabaseExecutor db) async {
    final settings = BusinessSettings(
      name: 'Your Restaurant Name',
      address: 'Street, Locality',
      city: 'Aizawl',
      state: 'Mizoram',
      pin: '796001',
      invoicePrefix: 'INV-',
      invoiceFooter: 'Thank you! Come back for another frame.',
    );
    await db.insert('settings', {'id': 1, 'data': jsonEncode(settings.toJson())});

    const menu = [
      (
        'Food',
        'food',
        [
          ('Chicken momo (8 pc)', 46, 120),
          ('Pork chowmein', 72, 150),
          ('Veg thali', 98, 180),
          ('Pork ribs', 243, 320),
          ('Grilled fish platter', 312, 380),
        ],
      ),
      (
        'Snacks',
        'snacks',
        [
          ('French fries', 29, 90),
          ('Loaded nachos', 70, 160),
          ('Chicken wings (6)', 118, 220),
          ('Veg club sandwich', 77, 130),
        ],
      ),
      (
        'Drinks',
        'drinks',
        [
          ('Cold coffee', 30, 100),
          ('Fresh lime soda', 16, 60),
          ('Coke (300 ml)', 30, 40),
          ('Masala tea', 8, 30),
          ('Oreo shake', 55, 140),
          ('Energy drink (can)', 99, 125),
          ('Hot chocolate', 54, 120),
        ],
      ),
    ];
    for (var i = 0; i < menu.length; i++) {
      final (name, type, items) = menu[i];
      final categoryId = await db.insert('categories', {'name': name, 'type': type, 'sort': i});
      for (final (item, cost, price) in items) {
        await db.insert('menu_items', {
          'category_id': categoryId,
          'name': item,
          'cost_price': cost,
          'price': price,
          'is_active': 1,
        });
      }
    }

    const tables = [
      ('Pool Table 1', 'pool'),
      ('Pool Table 2', 'pool'),
      ('Table 1', 'dining'),
      ('Table 2', 'dining'),
      ('Table 3', 'dining'),
      ('Table 4', 'dining'),
      ('Table 5', 'dining'),
      ('Takeaway', 'takeaway'),
    ];
    for (var sort = 0; sort < tables.length; sort++) {
      final (name, type) = tables[sort];
      await db.insert('restaurant_tables', {'name': name, 'type': type, 'sort': sort, 'is_active': 1});
    }
  }
}
