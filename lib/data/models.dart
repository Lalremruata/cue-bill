import 'dart:convert';

import '../core/billing.dart';

int? _ms(DateTime? t) => t?.millisecondsSinceEpoch;
DateTime? _dt(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
double _d(Object? v, [double fallback = 0]) => v == null ? fallback : (v as num).toDouble();
int _i(Object? v, [int fallback = 0]) => v == null ? fallback : (v as num).toInt();
bool _b(Object? v, [bool fallback = false]) => v == null ? fallback : (v == true || v == 1);
String? _s(Object? v) => (v == null || (v is String && v.isEmpty)) ? null : v.toString();

const categoryTypes = {'food': 'Food', 'drinks': 'Drinks', 'snacks': 'Snacks'};

/// Table types you can add under Menu & Tables. Takeaway orders are not tables: each one is
/// started from the POS screen and gets its own `takeaway` row (see [RestaurantTable.isTakeaway]).
const tableTypes = {'pool': 'Pool table', 'dining': 'Dining'};
const orderTypes = {'dine_in': 'Dine-in', 'takeaway': 'Takeaway'};
const paymentMethods = {'cash': 'Cash', 'upi': 'UPI', 'card': 'Card', 'split': 'Split'};

/// The single settings row: restaurant details, invoice, UPI, pool rates and GST.
class BusinessSettings {
  BusinessSettings({
    this.name = 'Your Restaurant Name',
    this.address,
    this.city,
    this.state = 'Mizoram',
    this.pin,
    this.phone,
    this.email,
    this.gstin,
    this.fssai,
    this.logoPath,
    this.invoicePrefix = 'INV-',
    this.nextInvoiceNumber = 1,
    this.invoiceFooter,
    this.upiId,
    this.upiPayeeName,
    this.showUpiQr = true,
    this.poolRatePerHour = 200,
    this.billingBlockMinutes = 15,
    this.minimumMinutes = 30,
    this.poolCostPerHour = 30,
    this.happyHourEnabled = false,
    this.happyHourRate = 150,
    this.happyHourStart = '12:00',
    this.happyHourEnd = '16:00',
    this.defaultBookingMinutes = 60,
    this.overtimeGraceMinutes = 5,
    this.bookingWarnMinutes = 5,
    this.overtimeRepeatMinutes = 5,
    this.bookedIsMinimum = true,
    this.gstFoodRate = 5,
    this.gstPoolRate = 18,
    this.savedAt,
    this.lastBackupAt,
    this.driveAutoBackup = true,
    this.driveLastBackupAt,
    this.driveFolderId,
  });

  String name;
  String? address;
  String? city;
  String state;
  String? pin;
  String? phone;
  String? email;
  String? gstin;
  String? fssai;
  String? logoPath;
  String invoicePrefix;
  int nextInvoiceNumber;
  String? invoiceFooter;
  String? upiId;
  String? upiPayeeName;
  bool showUpiQr;
  double poolRatePerHour;
  int billingBlockMinutes;
  int minimumMinutes;
  double poolCostPerHour;
  bool happyHourEnabled;
  double happyHourRate;

  /// `HH:mm`, 24-hour.
  String happyHourStart;
  String happyHourEnd;

  /// Booking picked by default when a pool timer starts; 0 = open play.
  int defaultBookingMinutes;

  /// Overtime past a booking that is not charged.
  int overtimeGraceMinutes;

  /// Warn this many minutes before a booking ends; 0 = no warning.
  int bookingWarnMinutes;

  /// Once a booking is over, sound the alert again every this many minutes while the
  /// timer runs; 0 = alert once only.
  int overtimeRepeatMinutes;

  /// A booking is charged in full even if the table finishes early.
  bool bookedIsMinimum;
  double gstFoodRate;
  double gstPoolRate;
  DateTime? savedAt;
  DateTime? lastBackupAt;

  /// Google Drive: back up once a day on its own.
  bool driveAutoBackup;
  DateTime? driveLastBackupAt;

  /// Cached ID of the "CueBill backups" folder.
  String? driveFolderId;

  String invoiceNumber([int? n]) => '$invoicePrefix${(n ?? nextInvoiceNumber).toString().padLeft(5, '0')}';

  /// Hourly rate for a pool table timer that starts at [at].
  double poolRateFor(RestaurantTable? table, DateTime at) {
    if (happyHourEnabled) {
      final t = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      if (t.compareTo(happyHourStart) >= 0 && t.compareTo(happyHourEnd) < 0) {
        return happyHourRate;
      }
    }
    final own = table?.hourlyRate;
    return (own != null && own > 0) ? own : poolRatePerHour;
  }

  /// Details printed on every invoice; copied onto the invoice when it is saved.
  BusinessSnapshot snapshot() => BusinessSnapshot(
    name: name,
    address: address,
    city: city,
    state: state,
    pin: pin,
    phone: phone,
    email: email,
    gstin: gstin,
    fssai: fssai,
    logoPath: logoPath,
    footer: invoiceFooter,
    upiId: upiId,
    upiPayeeName: (upiPayeeName == null || upiPayeeName!.isEmpty) ? name : upiPayeeName!,
    showUpiQr: showUpiQr,
  );

  BusinessSettings copy() => BusinessSettings.fromJson(toJson());

  Map<String, Object?> toJson() => {
    'name': name,
    'address': address,
    'city': city,
    'state': state,
    'pin': pin,
    'phone': phone,
    'email': email,
    'gstin': gstin,
    'fssai': fssai,
    'logo_path': logoPath,
    'invoice_prefix': invoicePrefix,
    'next_invoice_number': nextInvoiceNumber,
    'invoice_footer': invoiceFooter,
    'upi_id': upiId,
    'upi_payee_name': upiPayeeName,
    'show_upi_qr': showUpiQr,
    'pool_rate_per_hour': poolRatePerHour,
    'billing_block_minutes': billingBlockMinutes,
    'minimum_minutes': minimumMinutes,
    'pool_cost_per_hour': poolCostPerHour,
    'happy_hour_enabled': happyHourEnabled,
    'happy_hour_rate': happyHourRate,
    'happy_hour_start': happyHourStart,
    'happy_hour_end': happyHourEnd,
    'default_booking_minutes': defaultBookingMinutes,
    'overtime_grace_minutes': overtimeGraceMinutes,
    'booking_warn_minutes': bookingWarnMinutes,
    'overtime_repeat_minutes': overtimeRepeatMinutes,
    'booked_is_minimum': bookedIsMinimum,
    'gst_food_rate': gstFoodRate,
    'gst_pool_rate': gstPoolRate,
    'saved_at': _ms(savedAt),
    'last_backup_at': _ms(lastBackupAt),
    'drive_auto_backup': driveAutoBackup,
    'drive_last_backup_at': _ms(driveLastBackupAt),
    'drive_folder_id': driveFolderId,
  };

  factory BusinessSettings.fromJson(Map<String, Object?> j) => BusinessSettings(
    name: _s(j['name']) ?? 'Your Restaurant Name',
    address: _s(j['address']),
    city: _s(j['city']),
    state: _s(j['state']) ?? 'Mizoram',
    pin: _s(j['pin']),
    phone: _s(j['phone']),
    email: _s(j['email']),
    gstin: _s(j['gstin']),
    fssai: _s(j['fssai']),
    logoPath: _s(j['logo_path']),
    invoicePrefix: (j['invoice_prefix'] as String?) ?? 'INV-',
    nextInvoiceNumber: _i(j['next_invoice_number'], 1),
    invoiceFooter: _s(j['invoice_footer']),
    upiId: _s(j['upi_id']),
    upiPayeeName: _s(j['upi_payee_name']),
    showUpiQr: _b(j['show_upi_qr'], true),
    poolRatePerHour: _d(j['pool_rate_per_hour'], 200),
    billingBlockMinutes: _i(j['billing_block_minutes'], 15),
    minimumMinutes: _i(j['minimum_minutes'], 30),
    poolCostPerHour: _d(j['pool_cost_per_hour'], 30),
    happyHourEnabled: _b(j['happy_hour_enabled']),
    happyHourRate: _d(j['happy_hour_rate'], 150),
    happyHourStart: _s(j['happy_hour_start']) ?? '12:00',
    happyHourEnd: _s(j['happy_hour_end']) ?? '16:00',
    defaultBookingMinutes: _i(j['default_booking_minutes'], 60),
    overtimeGraceMinutes: _i(j['overtime_grace_minutes'], 5),
    bookingWarnMinutes: _i(j['booking_warn_minutes'], 5),
    overtimeRepeatMinutes: _i(j['overtime_repeat_minutes'], 5),
    bookedIsMinimum: _b(j['booked_is_minimum'], true),
    gstFoodRate: _d(j['gst_food_rate'], 5),
    gstPoolRate: _d(j['gst_pool_rate'], 18),
    savedAt: _dt(j['saved_at']),
    lastBackupAt: _dt(j['last_backup_at']),
    driveAutoBackup: _b(j['drive_auto_backup'], true),
    driveLastBackupAt: _dt(j['drive_last_backup_at']),
    driveFolderId: _s(j['drive_folder_id']),
  );
}

/// Copy of the business details stored on each invoice, so reprints never change.
class BusinessSnapshot {
  const BusinessSnapshot({
    required this.name,
    this.address,
    this.city,
    this.state,
    this.pin,
    this.phone,
    this.email,
    this.gstin,
    this.fssai,
    this.logoPath,
    this.footer,
    this.upiId,
    this.upiPayeeName = '',
    this.showUpiQr = false,
  });

  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? pin;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? fssai;
  final String? logoPath;
  final String? footer;
  final String? upiId;
  final String upiPayeeName;
  final bool showUpiQr;

  /// `Aizawl, Mizoram 796001`
  String get cityLine => [
    if (city != null && city!.isNotEmpty) city!,
    '${state ?? ''} ${pin ?? ''}'.trim(),
  ].where((s) => s.isNotEmpty).join(', ');

  Map<String, Object?> toJson() => {
    'name': name,
    'address': address,
    'city': city,
    'state': state,
    'pin': pin,
    'phone': phone,
    'email': email,
    'gstin': gstin,
    'fssai': fssai,
    'logo_path': logoPath,
    'footer': footer,
    'upi_id': upiId,
    'upi_payee_name': upiPayeeName,
    'show_upi_qr': showUpiQr,
  };

  factory BusinessSnapshot.fromJson(Map<String, Object?> j) => BusinessSnapshot(
    name: (j['name'] as String?) ?? '',
    address: _s(j['address']),
    city: _s(j['city']),
    state: _s(j['state']),
    pin: _s(j['pin']),
    phone: _s(j['phone']),
    email: _s(j['email']),
    gstin: _s(j['gstin']),
    fssai: _s(j['fssai']),
    logoPath: _s(j['logo_path']),
    footer: _s(j['footer']),
    upiId: _s(j['upi_id']),
    upiPayeeName: (j['upi_payee_name'] as String?) ?? '',
    showUpiQr: _b(j['show_upi_qr']),
  );
}

class MenuCategory {
  MenuCategory({this.id, required this.name, this.type = 'food', this.sort = 0});

  int? id;
  String name;
  String type; // food | drinks | snacks
  int sort;

  String get typeLabel => categoryTypes[type] ?? type;

  Map<String, Object?> toRow() => {'id': id, 'name': name, 'type': type, 'sort': sort};

  factory MenuCategory.fromRow(Map<String, Object?> r) =>
      MenuCategory(id: _i(r['id']), name: r['name'] as String, type: r['type'] as String, sort: _i(r['sort']));
}

class MenuItem {
  MenuItem({
    this.id,
    required this.categoryId,
    required this.name,
    this.costPrice = 0,
    required this.price,
    this.isActive = true,
  });

  int? id;
  int categoryId;
  String name;
  double costPrice;
  double price;
  bool isActive;

  double get profit => price - costPrice;

  double get marginPercent => price > 0 ? roundTo((price - costPrice) / price * 100, 1) : 0;

  Map<String, Object?> toRow() => {
    'id': id,
    'category_id': categoryId,
    'name': name,
    'cost_price': costPrice,
    'price': price,
    'is_active': isActive ? 1 : 0,
  };

  factory MenuItem.fromRow(Map<String, Object?> r) => MenuItem(
    id: _i(r['id']),
    categoryId: _i(r['category_id']),
    name: r['name'] as String,
    costPrice: _d(r['cost_price']),
    price: _d(r['price']),
    isActive: _b(r['is_active'], true),
  );
}

class RestaurantTable {
  RestaurantTable({
    this.id,
    required this.name,
    this.type = 'dining',
    this.hourlyRate,
    this.sort = 0,
    this.isActive = true,
  });

  int? id;
  String name;
  String type; // pool | dining | takeaway (one row per takeaway order, put away once billed)
  double? hourlyRate; // overrides the default pool rate
  int sort;
  bool isActive;

  bool get isPool => type == 'pool';

  /// A takeaway order (Takeaway #1, #2, …), not a real table.
  bool get isTakeaway => type == 'takeaway';

  /// Takeaway orders are takeaway; pool and dining tables are dine-in.
  String get orderType => isTakeaway ? 'takeaway' : 'dine_in';

  String get typeLabel => isTakeaway ? 'Takeaway' : (tableTypes[type] ?? type);

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'type': type,
    'hourly_rate': hourlyRate,
    'sort': sort,
    'is_active': isActive ? 1 : 0,
  };

  factory RestaurantTable.fromRow(Map<String, Object?> r) => RestaurantTable(
    id: _i(r['id']),
    name: r['name'] as String,
    type: r['type'] as String,
    hourlyRate: r['hourly_rate'] == null ? null : _d(r['hourly_rate']),
    sort: _i(r['sort']),
    isActive: _b(r['is_active'], true),
  );
}

enum TimerState { idle, running, paused, stopped }

class SessionItem {
  SessionItem({this.id, required this.sessionId, required this.menuItemId, this.qty = 1});

  int? id;
  int sessionId;
  int menuItemId;
  int qty;

  factory SessionItem.fromRow(Map<String, Object?> r) => SessionItem(
    id: _i(r['id']),
    sessionId: _i(r['table_session_id']),
    menuItemId: _i(r['menu_item_id']),
    qty: _i(r['qty'], 1),
  );
}

/// One entry in a table's timer history: start, pause, resume, extend, adjust, stop.
class SessionEvent {
  SessionEvent({this.id, required this.sessionId, required this.type, this.minutes, this.note, DateTime? at})
    : at = at ?? DateTime.now();

  int? id;
  int sessionId;
  String type; // start | pause | resume | extend | booking | adjust | stop
  int? minutes;
  String? note;
  DateTime at;

  Map<String, Object?> toRow() => {
    'id': id,
    'table_session_id': sessionId,
    'type': type,
    'minutes': minutes,
    'note': note,
    'at': _ms(at),
  };

  factory SessionEvent.fromRow(Map<String, Object?> r) => SessionEvent(
    id: _i(r['id']),
    sessionId: _i(r['table_session_id']),
    type: r['type'] as String,
    minutes: r['minutes'] == null ? null : _i(r['minutes']),
    note: _s(r['note']),
    at: _dt(r['at']),
  );
}

/// How a booked pool table is doing against its booking.
enum BookingState { none, ok, warning, over }

/// An open table: pool timer state plus the food and drinks ordered.
class TableSession {
  TableSession({
    this.id,
    required this.tableId,
    this.status = 'open',
    this.timerStartedAt,
    this.timerPausedAt,
    this.pausedSeconds = 0,
    this.timerStoppedAt,
    this.hourlyRate,
    this.bookedMinutes,
    DateTime? createdAt,
    List<SessionItem>? items,
    List<SessionEvent>? events,
  }) : createdAt = createdAt ?? DateTime.now(),
       items = items ?? [],
       events = events ?? [];

  int? id;
  int tableId;
  String status; // open | closed
  DateTime? timerStartedAt;
  DateTime? timerPausedAt;
  int pausedSeconds;
  DateTime? timerStoppedAt;
  double? hourlyRate; // locked in when the timer starts

  /// Booked pool time in minutes; null = open play.
  int? bookedMinutes;
  DateTime createdAt;
  List<SessionItem> items;
  List<SessionEvent> events;

  bool get isBooked => (bookedMinutes ?? 0) > 0;

  /// Seconds left on the booking (negative once over); null for open play or before the timer starts.
  int? remainingSeconds([DateTime? now]) =>
      timerStartedAt == null ? null : Billing.remainingSeconds(elapsedSeconds(now), bookedMinutes);

  BookingState bookingState(int warnMinutes, [DateTime? now]) {
    final left = remainingSeconds(now);
    if (left == null || timerState == TimerState.stopped) return BookingState.none;
    if (left <= 0) return BookingState.over;
    if (warnMinutes > 0 && left <= warnMinutes * 60) return BookingState.warning;
    return BookingState.ok;
  }

  TimerState get timerState {
    if (timerStartedAt == null) return TimerState.idle;
    if (timerStoppedAt != null) return TimerState.stopped;
    return timerPausedAt != null ? TimerState.paused : TimerState.running;
  }

  int elapsedSeconds([DateTime? now]) {
    int? sec(DateTime? t) => t == null ? null : t.millisecondsSinceEpoch ~/ 1000;
    return Billing.elapsedSeconds(
      startedAt: sec(timerStartedAt),
      pausedSeconds: pausedSeconds,
      pausedAt: sec(timerPausedAt),
      stoppedAt: sec(timerStoppedAt),
      now: sec(now ?? DateTime.now())!,
    );
  }

  int get itemCount => items.fold(0, (sum, i) => sum + i.qty);

  Map<String, Object?> toRow() => {
    'id': id,
    'restaurant_table_id': tableId,
    'status': status,
    'timer_started_at': _ms(timerStartedAt),
    'timer_paused_at': _ms(timerPausedAt),
    'paused_seconds': pausedSeconds,
    'timer_stopped_at': _ms(timerStoppedAt),
    'hourly_rate': hourlyRate,
    'booked_minutes': bookedMinutes,
    'created_at': _ms(createdAt),
  };

  factory TableSession.fromRow(Map<String, Object?> r) => TableSession(
    id: _i(r['id']),
    tableId: _i(r['restaurant_table_id']),
    status: r['status'] as String,
    timerStartedAt: _dt(r['timer_started_at']),
    timerPausedAt: _dt(r['timer_paused_at']),
    pausedSeconds: _i(r['paused_seconds']),
    timerStoppedAt: _dt(r['timer_stopped_at']),
    hourlyRate: r['hourly_rate'] == null ? null : _d(r['hourly_rate']),
    bookedMinutes: r['booked_minutes'] == null ? null : _i(r['booked_minutes']),
    createdAt: _dt(r['created_at']),
  );
}

class InvoiceItem {
  InvoiceItem({
    this.id,
    this.invoiceId,
    this.menuItemId,
    required this.name,
    this.categoryName,
    this.categoryType,
    required this.qty,
    required this.unitPrice,
    this.unitCost = 0,
    required this.amount,
  });

  int? id;
  int? invoiceId;
  int? menuItemId;
  String name;
  String? categoryName;
  String? categoryType;
  int qty;
  double unitPrice;
  double unitCost;
  double amount;

  Map<String, Object?> toRow() => {
    'id': id,
    'invoice_id': invoiceId,
    'menu_item_id': menuItemId,
    'name': name,
    'category_name': categoryName,
    'category_type': categoryType,
    'qty': qty,
    'unit_price': unitPrice,
    'unit_cost': unitCost,
    'amount': amount,
  };

  factory InvoiceItem.fromRow(Map<String, Object?> r) => InvoiceItem(
    id: _i(r['id']),
    invoiceId: _i(r['invoice_id']),
    menuItemId: r['menu_item_id'] == null ? null : _i(r['menu_item_id']),
    name: r['name'] as String,
    categoryName: _s(r['category_name']),
    categoryType: _s(r['category_type']),
    qty: _i(r['qty']),
    unitPrice: _d(r['unit_price']),
    unitCost: _d(r['unit_cost']),
    amount: _d(r['amount']),
  );
}

/// A completed sale. Invoices are GST records: they are never edited or deleted.
class Invoice {
  Invoice({
    this.id,
    required this.number,
    this.tableSessionId,
    required this.tableName,
    this.orderType = 'dine_in',
    this.customerName,
    this.customerPhone,
    required this.paymentMethod,
    this.cashReceived,
    this.poolStartedAt,
    this.poolEndedAt,
    this.poolPlayedMinutes = 0,
    this.poolBilledMinutes = 0,
    this.poolBookedMinutes,
    this.poolRate = 0,
    this.poolAmount = 0,
    this.poolCost = 0,
    this.itemsSubtotal = 0,
    this.itemsCost = 0,
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.gstPool = 0,
    this.gstFood = 0,
    this.gstPoolRate = 0,
    this.gstFoodRate = 0,
    this.roundOff = 0,
    required this.total,
    this.netRevenue = 0,
    this.totalCost = 0,
    required this.business,
    required this.paidAt,
    List<InvoiceItem>? items,
  }) : items = items ?? [];

  int? id;
  String number;
  int? tableSessionId;
  String tableName;
  String orderType; // dine_in | takeaway, copied from the table type at checkout
  String? customerName;
  String? customerPhone;
  String paymentMethod; // cash | upi | card | split
  double? cashReceived;
  DateTime? poolStartedAt;
  DateTime? poolEndedAt;
  int poolPlayedMinutes;
  int poolBilledMinutes;
  int? poolBookedMinutes; // null = open play
  double poolRate;
  double poolAmount;
  double poolCost;
  double itemsSubtotal;
  double itemsCost;
  double discountPercent;
  double discountAmount;
  double gstPool;
  double gstFood;
  double gstPoolRate;
  double gstFoodRate;
  double roundOff;
  double total;
  double netRevenue; // after discount, before GST
  double totalCost;
  BusinessSnapshot business;
  DateTime paidAt;
  List<InvoiceItem> items;

  double get profit => roundTo(netRevenue - totalCost, 2);

  String get paymentLabel => paymentMethods[paymentMethod] ?? paymentMethod;

  bool get isTakeaway => orderType == 'takeaway';

  String get orderTypeLabel => orderTypes[orderType] ?? orderType;

  Map<String, Object?> toRow() => {
    'id': id,
    'number': number,
    'table_session_id': tableSessionId,
    'table_name': tableName,
    'order_type': orderType,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'payment_method': paymentMethod,
    'cash_received': cashReceived,
    'pool_started_at': _ms(poolStartedAt),
    'pool_ended_at': _ms(poolEndedAt),
    'pool_played_minutes': poolPlayedMinutes,
    'pool_billed_minutes': poolBilledMinutes,
    'pool_booked_minutes': poolBookedMinutes,
    'pool_rate': poolRate,
    'pool_amount': poolAmount,
    'pool_cost': poolCost,
    'items_subtotal': itemsSubtotal,
    'items_cost': itemsCost,
    'discount_percent': discountPercent,
    'discount_amount': discountAmount,
    'gst_pool': gstPool,
    'gst_food': gstFood,
    'gst_pool_rate': gstPoolRate,
    'gst_food_rate': gstFoodRate,
    'round_off': roundOff,
    'total': total,
    'net_revenue': netRevenue,
    'total_cost': totalCost,
    'business': jsonEncode(business.toJson()),
    'paid_at': _ms(paidAt),
    'created_at': DateTime.now().millisecondsSinceEpoch,
  };

  factory Invoice.fromRow(Map<String, Object?> r) => Invoice(
    id: _i(r['id']),
    number: r['number'] as String,
    tableSessionId: r['table_session_id'] == null ? null : _i(r['table_session_id']),
    tableName: r['table_name'] as String,
    orderType: _s(r['order_type']) ?? 'dine_in',
    customerName: _s(r['customer_name']),
    customerPhone: _s(r['customer_phone']),
    paymentMethod: r['payment_method'] as String,
    cashReceived: r['cash_received'] == null ? null : _d(r['cash_received']),
    poolStartedAt: _dt(r['pool_started_at']),
    poolEndedAt: _dt(r['pool_ended_at']),
    poolPlayedMinutes: _i(r['pool_played_minutes']),
    poolBilledMinutes: _i(r['pool_billed_minutes']),
    poolBookedMinutes: r['pool_booked_minutes'] == null ? null : _i(r['pool_booked_minutes']),
    poolRate: _d(r['pool_rate']),
    poolAmount: _d(r['pool_amount']),
    poolCost: _d(r['pool_cost']),
    itemsSubtotal: _d(r['items_subtotal']),
    itemsCost: _d(r['items_cost']),
    discountPercent: _d(r['discount_percent']),
    discountAmount: _d(r['discount_amount']),
    gstPool: _d(r['gst_pool']),
    gstFood: _d(r['gst_food']),
    gstPoolRate: _d(r['gst_pool_rate']),
    gstFoodRate: _d(r['gst_food_rate']),
    roundOff: _d(r['round_off']),
    total: _d(r['total']),
    netRevenue: _d(r['net_revenue']),
    totalCost: _d(r['total_cost']),
    business: BusinessSnapshot.fromJson(
      (jsonDecode((r['business'] as String?) ?? '{}') as Map).cast<String, Object?>(),
    ),
    paidAt: _dt(r['paid_at'])!,
  );
}
