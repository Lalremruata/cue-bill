import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/billing.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../alert_sounds.dart';
import '../bookings.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

/// Booking colours on the dark order-panel header and the phone order bar.
const _warnOnDark = Color(0xFFF2B766);
const _overOnDark = Color(0xFFFF8A80);
const _okOnDark = Color(0xFF4ADE80);

Color _accentOnDark(BookingState b) => switch (b) {
  BookingState.over => _overOnDark,
  BookingState.warning => _warnOnDark,
  _ => Colors.white,
};

/// `6:00 PM` today, or `22 Nov 6:00 PM` on another day.
String _when(DateTime t, DateTime now) =>
    DateUtils.isSameDay(t, now) ? Fmt.time(t) : '${Fmt.shortDate(t)} ${Fmt.time(t)}';

/// `18:22` left, or `+03:12` over.
String _countdown(int left) => left > 0 ? Fmt.timer(left) : '+${Fmt.timer(-left)}';

/// Tables & Orders: table grid and menu on the left, the live order panel on the right.
/// Below 1080 px the menu sits under the tables and the order is a bar along the bottom.
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final nav = context.watch<Nav>();
    final table = store.tableById(nav.selectedTableId);

    final header = PageHeader(
      title: 'Tables & Orders',
      subtitle: 'Pick a table, start a pool booking or a walk-in, add food and drinks.',
      actions: [
        const LegendItem(label: 'In play', dot: DotState.running),
        const LegendItem(label: 'Paused / ordering', dot: DotState.busy),
        const LegendItem(label: 'Free', dot: DotState.free),
        LegendItem(label: 'Time up', color: context.cb.red),
      ],
    );
    return _OrderingLayout(
      table: table,
      top: [
        header,
        const _BookingStrip(),
        _TableGrid(selectedId: table?.id),
      ],
    );
  }
}

/// Takeaway: open takeaway orders and the menu on the left, the order panel on the right.
/// No tables and no pool timer; each order is for a named customer and billed on its own.
class TakeawayScreen extends StatelessWidget {
  const TakeawayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final nav = context.watch<Nav>();
    final order = store.tableById(nav.selectedTakeawayId);
    final orders = store.takeawayOrders;

    final header = PageHeader(
      title: 'Takeaway',
      subtitle: 'Orders to take away. No table and no pool timer.',
      actions: [
        FilledButton.icon(
          onPressed: () async {
            final created = await showNewTakeawayDialog(context);
            if (created != null) nav.selectTakeaway(created.id);
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New takeaway'),
        ),
      ],
    );
    final list = orders.isEmpty
        ? CbCard(
            child: Text('No takeaway orders open. Tap New takeaway to start one.', style: CbText.muted(context, 14)),
          )
        : ResponsiveGrid(
            minWidth: 160,
            spacing: 12,
            maxColumns: 4,
            children: [for (final t in orders) _TableCard(table: t, selected: t.id == order?.id)],
          );
    return _OrderingLayout(table: order, takeaway: true, top: [header, list]);
  }
}

/// Asks who the takeaway order is for, then starts it. Returns the order, or null if cancelled.
Future<RestaurantTable?> showNewTakeawayDialog(BuildContext context) =>
    showDialog<RestaurantTable>(context: context, builder: (_) => const _NewTakeawayDialog());

class _NewTakeawayDialog extends StatefulWidget {
  const _NewTakeawayDialog();

  @override
  State<_NewTakeawayDialog> createState() => _NewTakeawayDialogState();
}

class _NewTakeawayDialogState extends State<_NewTakeawayDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  int? _customerId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await context.read<AppStore>().newTakeaway(
        name: _name.text,
        phone: _phone.text,
        customerId: _customerId,
      );
      if (mounted) Navigator.of(context).pop(order);
    } on CueBillException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return AlertDialog(
      title: Text('New takeaway', style: CbText.cardTitle(context)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomerFields(
                name: _name,
                phone: _phone,
                customerId: _customerId,
                hint: 'Who is the order for?',
                onChanged: (id) => setState(() {
                  _customerId = id;
                  _error = null;
                }),
                onSubmitted: _start,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: cb.red, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy || _name.text.trim().isEmpty ? null : _start,
          icon: const Icon(Icons.takeout_dining_outlined, size: 20),
          label: const Text('Start order'),
        ),
      ],
    );
  }
}

/// Shared by Tables & Orders and Takeaway: [top] then the menu on the left, the order panel on
/// the right. Below 1080 px the menu sits under [top] and the order is a bar along the bottom.
class _OrderingLayout extends StatelessWidget {
  const _OrderingLayout({required this.table, required this.top, this.takeaway = false});

  final RestaurantTable? table;
  final List<Widget> top;
  final bool takeaway;

  @override
  Widget build(BuildContext context) {
    final table = this.table;
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 32.0;
    final menu = _MenuPicker(table: table, takeaway: takeaway);

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1080) {
          // Tall enough: the panel's header and totals stay put and only the order lines scroll.
          final fill = c.maxHeight >= 600;
          final panel = _OrderPanel(key: ValueKey('panel-${table?.id}'), table: table, fill: fill, takeaway: takeaway);
          final panelPad = EdgeInsets.fromLTRB(12, pad - 4, pad, pad);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, pad - 4, 12, pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [...top, const SizedBox(height: 24), menu],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: fill
                    ? Padding(
                        padding: panelPad,
                        child: Align(alignment: Alignment.topCenter, child: panel),
                      )
                    : SingleChildScrollView(padding: panelPad, child: panel),
              ),
            ],
          );
        }
        // Phones and tablets: [top], then the menu; the order is a bar that opens a sheet.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, pad - 4, pad, pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...top, const SizedBox(height: 20), menu],
                ),
              ),
            ),
            if (table != null) _OrderBar(table: table),
          ],
        );
      },
    );
  }
}

DotState dotFor(TableSession? s, RestaurantTable t) {
  if (s == null) return DotState.free;
  if (t.isPool && s.timerState == TimerState.running) return DotState.running;
  return DotState.busy;
}

// ------------------------------------------------------------------ timer actions

/// A walk-in: asks who is playing and for how long, then starts the game.
Future<void> _startWalkIn(BuildContext context, RestaurantTable table) =>
    showBookingDialog(context, table: table, walkIn: true);

/// Ends the game in play; the time is billed up to now.
Future<void> _stopTimer(BuildContext context, RestaurantTable table) async {
  final store = context.read<AppStore>();
  final who = store.sessionFor(table)?.customerName;
  final ok = await confirmDialog(
    context,
    title: 'End the game?',
    message:
        'The pool time for ${who ?? table.name} is billed up to now. '
        'You cannot restart this game; check out to free the table.',
    confirm: 'End game',
    danger: true,
  );
  if (ok) await store.stopTimer(table);
}

/// Adds time, asking first if the game would then run into a booking.
Future<void> _extend(BuildContext context, RestaurantTable table, int minutes) async {
  final store = context.read<AppStore>();
  final before = store.bookingsHitBy(table).map((b) => b.id).toSet();
  final hit = store.bookingsHitBy(table, extraMinutes: minutes).where((b) => !before.contains(b.id)).toList();
  if (hit.isNotEmpty) {
    final b = hit.first;
    final ok = await confirmDialog(
      context,
      title: 'Run into ${b.customerName}\'s booking?',
      message:
          '${b.customerName} has booked ${table.name} at ${Fmt.time(b.startAt)}. '
          'Adding ${Billing.duration(minutes)} keeps the table busy until '
          '${Fmt.time(store.sessionFor(table)!.expectedEnd()!.add(Duration(minutes: minutes)))}.',
      confirm: 'Add time anyway',
    );
    if (!ok) return;
  }
  await store.extendBooking(table, minutes);
}

Future<void> _adjustTimer(BuildContext context, RestaurantTable table) => showDialog<void>(
  context: context,
  builder: (_) => _AdjustDialog(table: table),
);

void _openOrderSheet(BuildContext context, RestaurantTable table) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.92),
            child: _OrderPanel(table: table, fill: true, inSheet: true),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ booking alerts

/// Plays a sound and shows a message when a booked pool table is nearly or fully out of time,
/// or a booking is coming up or due, whichever screen is open. A chime for the warning and
/// the early reminder (5 s), an alarm for time up and a booking that is due (30 s). Wraps the app shell.
class BookingAlerts extends StatefulWidget {
  const BookingAlerts({super.key, required this.child});

  final Widget child;

  @override
  State<BookingAlerts> createState() => _BookingAlertsState();
}

class _BookingAlertsState extends State<BookingAlerts> {
  final _tracker = BookingAlertTracker();
  final _reminders = BookingReminderTracker();

  @override
  void initState() {
    super.initState();
    Clock.now.addListener(_tick);
  }

  @override
  void dispose() {
    Clock.now.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final store = context.read<AppStore>();
    final settings = store.settings;
    final now = Clock.now.value;
    store.pauseFinishedBookings(now);
    final open = <int>{};
    AlertTone? tone;
    void sound(AlertTone t) {
      if (tone == null || t.index > tone!.index) tone = t;
    }

    for (final (table, s) in store.openTables) {
      if (!table.isPool || s.id == null) continue;
      open.add(s.id!);
      final state = s.bookingState(settings.bookingWarnMinutes, now);
      final left = s.remainingSeconds(now) ?? 0;
      final alert = _tracker.check(s.id!, state, left, repeatMinutes: settings.overtimeRepeatMinutes);
      if (alert == null) continue;
      final overMinutes = -left ~/ 60;
      final message = switch (alert) {
        BookingAlert.timeUp =>
          s.timerState == TimerState.paused
              ? '${table.name}: booked time is up. The game is paused: add time to carry on, or end it.'
              : '${table.name}: booked time is up.',
        BookingAlert.stillOver => '${table.name}: time up, $overMinutes min over. End the game or add time.',
        BookingAlert.warning => '${table.name}: ${(left / 60).ceil()} min left.',
      };
      final over = alert != BookingAlert.warning;
      sound(over ? AlertTone.timeUp : AlertTone.warning);
      if (over) HapticFeedback.heavyImpact();
      _show(message, table, urgent: over);
    }
    _tracker.forgetExcept(open);

    // Bookings coming up or due now.
    final waiting = <int>{};
    for (final table in store.activeTables.where((t) => t.isPool)) {
      for (final b in store.todayFor(table, now)) {
        waiting.add(b.id!);
        final r = _reminders.check(b, now, remindMinutes: settings.bookingReminderMinutes);
        if (r == null) continue;
        final busy = store.sessionFor(table)?.timerStartedAt != null;
        final message = switch (r) {
          BookingReminder.soon =>
            '${b.customerName}\'s booking on ${table.name} at ${Fmt.time(b.startAt)}'
                '${busy ? '. The table is still in play.' : '.'}',
          BookingReminder.due =>
            busy
                ? '${b.customerName} is due now on ${table.name}, but the table is still in play.'
                : '${b.customerName}\'s booking on ${table.name} starts now. Start it or mark a no-show.',
        };
        sound(r == BookingReminder.due ? AlertTone.timeUp : AlertTone.warning);
        _show(message, table, urgent: r == BookingReminder.due && busy);
      }
    }
    _reminders.forgetExcept(waiting);

    // One sound per tick, however many tables alerted.
    if (tone != null) AlertSounds.instance.play(tone!);
  }

  void _show(String message, RestaurantTable table, {required bool urgent}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: urgent ? const Color(0xFFB42318) : const Color(0xFF8A4B08),
          width: MediaQuery.sizeOf(context).width > 700 ? 420 : null,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Show',
            textColor: Colors.white,
            onPressed: () {
              final nav = context.read<Nav>();
              nav.go(Section.pos);
              nav.selectTable(table.id);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum BookingAlert { warning, timeUp, stillOver }

enum BookingReminder { soon, due }

/// Decides when a booking not yet started should remind staff: once when it is
/// [remindMinutes] away (0 = no reminder), and once when it is due. Nothing fires once the
/// booked slot is over.
class BookingReminderTracker {
  final _fired = <int, BookingReminder>{};

  BookingReminder? check(Booking b, DateTime now, {required int remindMinutes}) {
    final id = b.id;
    if (id == null || !b.isUpcoming || !now.isBefore(b.endAt)) return null;
    final last = _fired[id];
    if (!now.isBefore(b.startAt)) {
      if (last == BookingReminder.due) return null;
      _fired[id] = BookingReminder.due;
      return BookingReminder.due;
    }
    if (remindMinutes > 0 && last == null && !now.isBefore(b.startAt.subtract(Duration(minutes: remindMinutes)))) {
      _fired[id] = BookingReminder.soon;
      return BookingReminder.soon;
    }
    return null;
  }

  /// Drops bookings that are no longer waiting.
  void forgetExcept(Set<int> waiting) => _fired.removeWhere((id, _) => !waiting.contains(id));
}

/// Decides when a booked table should alert, one call per table per clock tick.
///
/// The warning and the first time-up alert fire once, when the table gets worse;
/// extending the booking resets them quietly. While a table stays over time, the
/// time-up alert repeats every `repeatMinutes` of overtime (e.g. at 5, 10, 15 min
/// over); 0 = once only. Overtime is played time, so a paused table stops repeating.
class BookingAlertTracker {
  final _seen = <int, BookingState>{};
  final _overBucket = <int, int>{};

  /// [leftSeconds] is negative once over time. Returns the alert to show, if any.
  BookingAlert? check(int sessionId, BookingState state, int leftSeconds, {required int repeatMinutes}) {
    final before = _seen[sessionId] ?? BookingState.none;
    _seen[sessionId] = state;

    if (state != BookingState.over) {
      _overBucket.remove(sessionId);
      if (state == BookingState.warning && before.index < BookingState.warning.index) return BookingAlert.warning;
      return null;
    }

    final bucket = repeatMinutes > 0 ? (-leftSeconds ~/ 60) ~/ repeatMinutes : 0;
    final last = _overBucket[sessionId];
    if (before != BookingState.over || last == null) {
      _overBucket[sessionId] = bucket;
      return BookingAlert.timeUp;
    }
    if (bucket > last) {
      _overBucket[sessionId] = bucket;
      return BookingAlert.stillOver;
    }
    // Played time was corrected down: count the next repeat from here.
    if (bucket < last) _overBucket[sessionId] = bucket;
    return null;
  }

  /// Drops tables that are no longer open.
  void forgetExcept(Set<int> openSessionIds) {
    _seen.removeWhere((id, _) => !openSessionIds.contains(id));
    _overBucket.removeWhere((id, _) => !openSessionIds.contains(id));
  }
}

/// One line per pool table that is nearly or fully out of booked time; tap to select it.
class _BookingStrip extends StatelessWidget {
  const _BookingStrip();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    return Ticking(
      builder: (context, now) {
        final warn = store.settings.bookingWarnMinutes;
        final flagged = [
          for (final (t, s) in store.openTables)
            if (t.isPool && s.bookingState(warn, now).index >= BookingState.warning.index) (t, s),
        ];
        if (flagged.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (t, s) in flagged)
                Builder(
                  builder: (context) {
                    final over = s.bookingState(warn, now) == BookingState.over;
                    final left = s.remainingSeconds(now)!;
                    final fg = over ? cb.red : cb.amber;
                    return Material(
                      color: over ? cb.redSoft : cb.amberSoft,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: fg.withValues(alpha: 0.5)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => context.read<Nav>().selectTable(t.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(over ? Icons.alarm_on_rounded : Icons.schedule_rounded, size: 17, color: fg),
                              const SizedBox(width: 8),
                              Text(
                                over
                                    ? '${t.name} · time up, ${math.max(1, -left ~/ 60)} min over'
                                    : '${t.name} · ${(left / 60).ceil()} min left',
                                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ table grid

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.selected});

  final RestaurantTable table;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    final session = store.sessionFor(table);

    return Ticking(
      builder: (context, now) {
        final dot = dotFor(session, table);
        final rate = session?.hourlyRate ?? store.settings.poolRateFor(table, now);
        final phone = table.isTakeaway ? session?.customerPhone : null;
        final subtitle = table.isPool ? 'Pool table · ${Fmt.inr(rate)}/hr' : (phone ?? table.typeLabel);
        final booking = session?.bookingState(store.settings.bookingWarnMinutes, now) ?? BookingState.none;

        final next = table.isPool ? store.nextBookingFor(table, now) : null;
        final nextText = next == null ? null : 'Next ${next.customerName} ${_when(next.startAt, now)}';
        final who = session?.customerName;
        String value;
        String sub;
        if (session == null) {
          value = 'Free';
          sub = table.isPool ? (nextText ?? 'No bookings') : 'Tap to open';
        } else {
          final calc = store.calcFor(table, now: now)!;
          final left = session.remainingSeconds(now);
          final whoText = who == null ? '' : '$who · ';
          if (table.isPool && session.timerStartedAt != null && left != null) {
            value = _countdown(left);
            final paused = session.timerState == TimerState.paused ? 'Paused · ' : '';
            sub = switch (booking) {
              BookingState.over => '${whoText}Time up · ${Fmt.inr(calc.totals.total)}',
              _ => '$whoText$paused${left > 0 ? 'left' : 'done'} · ${Fmt.inr(calc.totals.total)}',
            };
          } else if (table.isPool && session.timerStartedAt != null) {
            value = Fmt.timer(session.elapsedSeconds(now));
            sub = '$whoText${Fmt.inr(calc.totals.total)} so far';
          } else if (session.items.isNotEmpty) {
            value = Fmt.inr(calc.totals.total);
            final n = session.itemCount;
            sub = '$n item${n == 1 ? '' : 's'}${table.isPool ? ' · no game yet' : ''}';
          } else {
            value = 'Open';
            sub = table.isPool ? (nextText ?? 'No game yet') : 'No items yet';
          }
        }

        final alert = switch (booking) {
          BookingState.over => cb.red,
          BookingState.warning => cb.amber,
          _ => null,
        };
        final bg = table.isPool ? cb.poolCard : cb.card;
        final stateLabel = switch (booking) {
          BookingState.over => ', time up',
          BookingState.warning => ', almost out of time',
          _ => '',
        };
        return Semantics(
          button: true,
          selected: selected,
          label:
              '${table.name}, ${dot == DotState.free ? 'free' : value}${who == null ? '' : ', $who playing'}$stateLabel',
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected ? [BoxShadow(color: cb.greenSoft, spreadRadius: 4)] : null,
            ),
            child: Material(
              color: booking == BookingState.over ? Color.alphaBlend(cb.redSoft, bg) : bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: alert ?? (selected ? cb.green : cb.line),
                  width: (selected || alert != null) ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  final nav = context.read<Nav>();
                  table.isTakeaway ? nav.selectTakeaway(table.id) : nav.selectTable(table.id);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              table.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cb.ink),
                            ),
                          ),
                          StatusDot(dot),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: CbText.muted(context, 12.5)),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: CbText.big(context, size: 22, color: alert)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: alert == null
                            ? CbText.muted(context, 13)
                            : TextStyle(color: alert, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ order panel

/// The open table: timer header, order lines and totals.
///
/// With [fill], the panel takes at most the height it is given: the header and totals
/// stay in view and only the order lines scroll, however long the order gets.
class _OrderPanel extends StatefulWidget {
  const _OrderPanel({super.key, required this.table, this.fill = false, this.inSheet = false, this.takeaway = false});

  final RestaurantTable? table;
  final bool fill;

  /// On the Takeaway page: the empty panel asks for a takeaway order, not a table.
  final bool takeaway;

  /// Shown in the phone bottom sheet: checkout and clear close the sheet first.
  final bool inSheet;

  @override
  State<_OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends State<_OrderPanel> {
  final _keys = <int, GlobalKey>{};
  final _scroll = ScrollController();
  int? _seenSerial;
  int? _flashId;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Highlights the line just added or changed, and scrolls it into view.
  void _noticeTouched(AppStore store) {
    final t = store.lastTouched;
    if (t == null || t.serial == _seenSerial) return;
    final first = _seenSerial == null;
    _seenSerial = t.serial;
    if (first || t.tableId != widget.table?.id) return;
    _flashId = t.menuItemId;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flashId = null);
    });
    if (!widget.fill) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[t.menuItemId]?.currentContext;
      if (ctx == null || !_scroll.hasClients) return;
      const d = Duration(milliseconds: 250);
      Scrollable.ensureVisible(ctx, duration: d, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      Scrollable.ensureVisible(ctx, duration: d, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final table = widget.table;
    if (table == null) {
      return CbCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DarkHeader(
              children: [
                Text(
                  widget.takeaway ? 'No order selected' : 'No table selected',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.takeaway
                      ? 'Tap New takeaway to start an order, or tap an open one.'
                      : 'Tap a table to open it, start a pool booking or add food.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13.5),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('The order and running total show here.', style: CbText.muted(context, 14)),
            ),
          ],
        ),
      );
    }

    final store = context.watch<AppStore>();
    _noticeTouched(store);
    final session = store.sessionFor(table);
    final menu = store.menuById;

    final lines = <Widget>[
      for (final line in session?.items ?? <SessionItem>[])
        if (menu[line.menuItemId] != null)
          _OrderLine(
            key: _keys.putIfAbsent(line.menuItemId, GlobalKey.new),
            table: table,
            item: menu[line.menuItemId]!,
            qty: line.qty,
            flash: _flashId == line.menuItemId,
          ),
    ];

    final Widget body;
    if (lines.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Text(
          widget.inSheet
              ? 'No food or drinks yet. Close this and tap a menu item to add it.'
              : 'No food or drinks yet. Tap an item to add it.',
          style: CbText.muted(context, 14),
        ),
      );
    } else if (widget.fill) {
      body = Flexible(
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: lines.length > 6,
          child: ListView(controller: _scroll, shrinkWrap: true, padding: EdgeInsets.zero, children: lines),
        ),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: lines);
    }

    final n = session?.itemCount ?? 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: cb.card,
          border: Border.all(color: cb.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(table: table, session: session, compact: widget.inSheet),
            if (table.isPool) _TodayBookings(table: table),
            if (lines.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cb.line)),
                ),
                child: Text(
                  'Order · ${lines.length} line${lines.length == 1 ? '' : 's'}, $n item${n == 1 ? '' : 's'}',
                  style: CbText.muted(context, 12.5),
                ),
              ),
            body,
            _PanelFooter(table: table, session: session, inSheet: widget.inSheet),
          ],
        ),
      ),
    );
  }
}

/// Under the pool table header: the rest of today's bookings, so nobody needs a paper list.
class _TodayBookings extends StatelessWidget {
  const _TodayBookings({required this.table});

  final RestaurantTable table;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    final list = store.todayFor(table);
    final more = list.length - _shown;
    final nav = context.read<Nav>();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
      decoration: BoxDecoration(
        color: cb.soft,
        border: Border(bottom: BorderSide(color: cb.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  list.isEmpty ? 'No more bookings today' : "Today's bookings · ${list.length}",
                  style: TextStyle(color: cb.ink, fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 32), visualDensity: VisualDensity.compact),
                onPressed: () => nav.go(Section.bookings),
                child: Text(more > 0 ? 'All bookings (+$more)' : 'All bookings'),
              ),
            ],
          ),
          for (final b in list.take(_shown)) BookingTile(booking: b, compact: true),
        ],
      ),
    );
  }
}

class _DarkHeader extends StatelessWidget {
  const _DarkHeader({required this.children, this.compact = false});

  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.cb.dark,
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.table, required this.session, this.compact = false});

  final RestaurantTable table;
  final TableSession? session;

  /// Phone sheet: smaller clock and buttons, so more order lines fit.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final settings = context.watch<AppStore>().settings;
    final s = session;
    final dim = Colors.white.withValues(alpha: 0.72);
    final state = s?.timerState ?? TimerState.idle;

    if (!table.isPool) {
      final n = s?.itemCount ?? 0;
      return _DarkHeader(
        children: [
          Text(
            table.name,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            [
              table.typeLabel,
              if (table.isTakeaway && s?.customerPhone != null) s!.customerPhone!,
              s == null ? 'Free' : '$n item${n == 1 ? '' : 's'}',
            ].join(' · '),
            style: TextStyle(color: dim, fontSize: 13.5),
          ),
        ],
      );
    }

    final booked = s?.bookedMinutes;
    final bookedText = booked == null ? 'open play' : 'booked ${Billing.duration(booked)}';
    final statusText = switch (state) {
      TimerState.idle => s == null ? 'Free' : 'No game yet',
      TimerState.running => 'In play · $bookedText',
      TimerState.paused => 'Paused · $bookedText',
      TimerState.stopped => 'Game ended',
    };

    // Compact: tighter buttons so the four timer buttons fit one row on a phone.
    final dense = compact
        ? const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
            minimumSize: WidgetStatePropertyAll(Size(0, 40)),
            visualDensity: VisualDensity.compact,
          )
        : const ButtonStyle();
    final darkOutline = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
    ).merge(dense);
    final stopStyle = OutlinedButton.styleFrom(
      foregroundColor: _overOnDark,
      backgroundColor: Colors.transparent,
      side: const BorderSide(color: Color(0x99FF8A80)),
    ).merge(dense);
    final adjust = TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: dim,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 32),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => _adjustTimer(context, table),
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: const Text('Adjust'),
    );

    return Ticking(
      builder: (context, now) {
        final elapsed = s?.elapsedSeconds(now) ?? 0;
        final rate = s?.hourlyRate ?? settings.poolRateFor(table, now);
        final calc = s == null ? null : store.calcFor(table, now: now);
        final left = s?.remainingSeconds(now);
        final booking = s?.bookingState(settings.bookingWarnMinutes, now) ?? BookingState.none;
        final accent = _accentOnDark(booking);
        final urgent = booking == BookingState.over || booking == BookingState.warning;

        // Extend buttons: filled once time is nearly or fully up, so they are the obvious next tap.
        List<Widget> extend() => [
          for (final (m, label) in const [(30, '+30 min'), (60, '+1 hour')])
            urgent
                ? FilledButton(style: dense, onPressed: () => _extend(context, table, m), child: Text(label))
                : OutlinedButton(style: darkOutline, onPressed: () => _extend(context, table, m), child: Text(label)),
        ];
        final next = store.nextBookingFor(table, now);
        final clash = store.bookingsHitBy(table, now: now).firstOrNull;

        final billable = calc != null && calc.billedMinutes > 0
            ? ' · billable ${Billing.duration(calc.billedMinutes)}'
            : '';
        final String rules;
        if (left != null) {
          final grace = settings.overtimeGraceMinutes;
          rules =
              '${Fmt.inr(rate)}/hr · ${grace > 0 ? '$grace free min, then ' : 'overtime in '}'
              '${settings.billingBlockMinutes}-min blocks$billable';
        } else {
          rules =
              '${Fmt.inr(rate)}/hr · billed in ${settings.billingBlockMinutes}-min blocks, '
              'min ${settings.minimumMinutes} min$billable';
        }

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              table.name,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text('Pool table · $statusText', style: TextStyle(color: dim, fontSize: 13.5)),
          ],
        );

        if (state == TimerState.idle) {
          // No game: who is booked next, and start a walk-in or take a booking.
          final due = next != null && !now.isBefore(next.startAt.subtract(const Duration(minutes: 15)));
          final String freeText;
          if (next == null) {
            freeText = 'No more bookings. Free for walk-ins.';
          } else if (!DateUtils.isSameDay(next.startAt, now)) {
            freeText = 'No more bookings today. Next: ${next.customerName}, ${_when(next.startAt, now)}.';
          } else if (!now.isBefore(next.startAt)) {
            freeText = '${next.customerName} is booked now (${bookingSlot(next.startAt, next.endAt)}).';
          } else {
            final gap = next.startAt.difference(now).inMinutes;
            freeText = 'Free until ${Fmt.time(next.startAt)} (${Billing.duration(gap)}). Next: ${next.customerName}.';
          }
          return _DarkHeader(
            compact: compact,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              Text(
                freeText,
                style: TextStyle(
                  color: due ? _warnOnDark : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${Fmt.inr(rate)}/hr · billed in ${settings.billingBlockMinutes}-min blocks',
                style: TextStyle(color: dim, fontSize: 13, fontFeatures: tabular),
              ),
              SizedBox(height: compact ? 12 : 14),
              Wrap(
                spacing: compact ? 8 : 10,
                runSpacing: 10,
                children: [
                  if (due)
                    FilledButton.icon(
                      style: dense,
                      onPressed: () => startBookingFlow(context, next),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text('Start ${next.customerName}'),
                    ),
                  if (due)
                    OutlinedButton(
                      style: darkOutline,
                      onPressed: () => _startWalkIn(context, table),
                      child: const Text('Walk-in'),
                    )
                  else
                    FilledButton.icon(
                      style: dense,
                      onPressed: () => _startWalkIn(context, table),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Walk-in'),
                    ),
                  OutlinedButton.icon(
                    style: darkOutline,
                    onPressed: () => showBookingDialog(context, table: table),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: const Text('Book'),
                  ),
                ],
              ),
            ],
          );
        }

        final nextText = next == null
            ? null
            : 'Next: ${next.customerName} at ${_when(next.startAt, now)}'
                  '${clash != null ? ' · this game runs into it' : ''}';

        return _DarkHeader(
          compact: compact,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleBlock),
                if (s?.timerStartedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Started ${Fmt.time(s!.timerStartedAt!)}', style: TextStyle(color: dim, fontSize: 12.5)),
                        adjust,
                      ],
                    ),
                  ),
              ],
            ),
            if (s?.customerName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      [s!.customerName!, if (s.customerPhone != null) s.customerPhone!].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Semantics(
              liveRegion: false,
              label: left == null
                  ? 'Time played ${Fmt.timer(elapsed)}'
                  : left > 0
                  ? 'Time left ${Fmt.timer(left)}'
                  : 'Over booked time by ${Fmt.timer(-left)}',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        left == null ? Fmt.timer(elapsed) : _countdown(left),
                        style: TextStyle(
                          fontFamily: CbText.heading,
                          fontSize: compact ? 36 : 44,
                          fontWeight: FontWeight.w700,
                          color: accent,
                          fontFeatures: tabular,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                  if (left != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      left > 0 ? 'left' : 'over time',
                      style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            if (left != null && booked != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (elapsed / (booked * 60)).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  color: urgent ? accent : _okOnDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Played ${Fmt.timer(elapsed)} of ${Billing.duration(booked)}'
                '${state == TimerState.running && left > 0 ? ' · ends ${Fmt.time(now.add(Duration(seconds: left)))}' : ''}',
                style: TextStyle(color: Colors.white, fontSize: 13.5, fontFeatures: tabular),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              rules,
              style: TextStyle(color: dim, fontSize: 13, fontFeatures: tabular),
            ),
            if (nextText != null && state != TimerState.stopped) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 16, color: clash != null ? _warnOnDark : dim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      nextText,
                      style: TextStyle(
                        color: clash != null ? _warnOnDark : dim,
                        fontSize: 13,
                        fontWeight: clash != null ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: compact ? 12 : 14),
            Wrap(
              spacing: compact ? 8 : 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: switch (state) {
                TimerState.idle => const <Widget>[],
                TimerState.running => [
                  if (s!.isBooked) ...extend(),
                  OutlinedButton(
                    style: darkOutline,
                    onPressed: () => store.pauseTimer(table),
                    child: const Text('Pause'),
                  ),
                  OutlinedButton(
                    style: stopStyle,
                    onPressed: () => _stopTimer(context, table),
                    child: const Text('End game'),
                  ),
                ],
                TimerState.paused => [
                  FilledButton(style: dense, onPressed: () => store.resumeTimer(table), child: const Text('Resume')),
                  if (s!.isBooked) ...extend(),
                  OutlinedButton(
                    style: stopStyle,
                    onPressed: () => _stopTimer(context, table),
                    child: const Text('End game'),
                  ),
                ],
                TimerState.stopped => [
                  Text(
                    'Game ended at ${Fmt.time(s!.timerStoppedAt!)}. Ready for checkout.',
                    style: TextStyle(color: dim, fontSize: 13),
                  ),
                ],
              },
            ),
          ],
        );
      },
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({super.key, required this.table, required this.item, required this.qty, this.flash = false});

  final RestaurantTable table;
  final MenuItem item;
  final int qty;

  /// Just added or changed: briefly highlighted.
  final bool flash;

  Future<void> _typeQty(BuildContext context) async {
    final store = context.read<AppStore>();
    final controller = TextEditingController(text: '$qty');
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    final value = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(item.name, style: CbText.cardTitle(d)),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(labelText: 'Quantity', helperText: '0 removes it from the order'),
            onSubmitted: (t) => Navigator.of(d).pop(int.tryParse(t)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(d).pop(int.tryParse(controller.text)), child: const Text('Set')),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await store.setQty(table, item.id!, value);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final cb = context.cb;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: flash ? cb.greenSoft : cb.card,
        border: Border(bottom: BorderSide(color: cb.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: cb.ink),
                ),
                Text('${Fmt.inr(item.price)} each', style: CbText.muted(context, 12.5)),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            label: qty == 1 ? 'Remove ${item.name}' : 'One less ${item.name}',
            onTap: () => store.changeQty(table, item.id!, -1),
          ),
          Tooltip(
            message: 'Type a quantity',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _typeQty(context),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: CbText.num(
                      context,
                      size: 16,
                      weight: FontWeight.w600,
                    ).copyWith(decoration: TextDecoration.underline, decorationColor: cb.line),
                  ),
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            label: 'One more ${item.name}',
            onTap: () => store.changeQty(table, item.id!, 1),
          ),
          SizedBox(
            width: 76,
            child: Text(
              Fmt.inr(item.price * qty),
              textAlign: TextAlign.right,
              style: CbText.num(context, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelFooter extends StatelessWidget {
  const _PanelFooter({required this.table, required this.session, this.inSheet = false});

  final RestaurantTable table;
  final TableSession? session;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final cb = context.cb;

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: cb.muted, fontSize: 14)),
          ),
          Text(value, style: CbText.num(context)),
        ],
      ),
    );

    return Ticking(
      builder: (context, now) {
        final calc = session == null ? null : store.calcFor(table, now: now);
        final hasBill = calc != null && !calc.isEmpty;
        return Container(
          decoration: BoxDecoration(
            color: cb.soft,
            border: Border(top: BorderSide(color: cb.line)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (table.isPool) row('Pool table time', Fmt.inr(calc?.poolAmount ?? 0)),
              row('Food & drinks', Fmt.inr(calc?.itemsSubtotal ?? 0)),
              row('GST (est.)', Fmt.inr(calc?.totals.gst ?? 0)),
              const SizedBox(height: 8),
              Divider(color: cb.line),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cb.ink),
                    ),
                  ),
                  Text(Fmt.inr(calc?.totals.total ?? 0), style: CbText.big(context, size: 26)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: session == null
                          ? null
                          : () async {
                              final ok = await confirmDialog(
                                context,
                                title: table.isTakeaway ? 'Cancel ${table.name}?' : 'Clear ${table.name}?',
                                message: table.isTakeaway
                                    ? 'This removes the takeaway order without billing.'
                                    : table.isPool && session?.bookingId != null
                                    ? 'This removes the order and the game without billing, and marks the booking cancelled. '
                                          'Use it for a game started by mistake; you can restore the booking from Bookings.'
                                    : 'This removes the order and the game without billing. Use it for a table opened by mistake.',
                                confirm: table.isTakeaway ? 'Cancel order' : 'Clear table',
                                danger: true,
                              );
                              if (!ok) return;
                              await store.clearTable(table);
                              if (inSheet && context.mounted) Navigator.of(context).pop();
                            },
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: !hasBill
                          ? null
                          : () async {
                              final nav = context.read<Nav>();
                              await store.stopTimer(table);
                              if (inSheet && context.mounted) Navigator.of(context).pop();
                              nav.openCheckout(table.id!, takeaway: table.isTakeaway);
                            },
                      child: Text(
                        table.isPool && session?.timerState != TimerState.stopped && session?.timerStartedAt != null
                            ? 'End & checkout'
                            : 'Checkout',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Phones and tablets: the selected table's timer, item count and total along the bottom.
/// Tap it for the full order.
class _OrderBar extends StatelessWidget {
  const _OrderBar({required this.table});

  final RestaurantTable table;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = store.sessionFor(table);
    final cb = context.cb;
    final dim = Colors.white.withValues(alpha: 0.72);

    return Ticking(
      builder: (context, now) {
        final calc = s == null ? null : store.calcFor(table, now: now);
        final booking = s?.bookingState(store.settings.bookingWarnMinutes, now) ?? BookingState.none;
        final accent = booking == BookingState.none || booking == BookingState.ok ? dim : _accentOnDark(booking);
        final n = s?.itemCount ?? 0;
        final idlePool = table.isPool && (s == null || s.timerStartedAt == null);

        final String status;
        if (s == null) {
          final next = table.isPool ? store.nextBookingFor(table, now) : null;
          status = !table.isPool
              ? 'Free · tap a menu item to add it'
              : next == null
              ? 'Free · no bookings'
              : 'Free · next ${next.customerName} ${_when(next.startAt, now)}';
        } else if (table.isPool && s.timerStartedAt != null) {
          final left = s.remainingSeconds(now);
          final paused = s.timerState == TimerState.paused ? ' · paused' : '';
          final stopped = s.timerState == TimerState.stopped ? ' · ended' : '';
          final who = s.customerName == null ? '' : '${s.customerName} · ';
          status = left == null
              ? '$who${Fmt.timer(s.elapsedSeconds(now))} played$paused$stopped'
              : left > 0
              ? '$who${Fmt.timer(left)} left$paused$stopped'
              : '${who}Time up · ${_countdown(left)}$stopped';
        } else {
          status = table.isPool ? 'No game yet' : '$n item${n == 1 ? '' : 's'}';
        }

        return Material(
          color: cb.dark,
          elevation: 8,
          child: InkWell(
            onTap: () => _openOrderSheet(context, table),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          table.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: accent == dim ? FontWeight.w400 : FontWeight.w600,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Fmt.inr(calc?.totals.total ?? 0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: CbText.heading,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          fontFeatures: tabular,
                        ),
                      ),
                      Text('$n item${n == 1 ? '' : 's'}', style: TextStyle(color: dim, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  if (idlePool)
                    FilledButton(onPressed: () => _startWalkIn(context, table), child: const Text('Walk-in'))
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _openOrderSheet(context, table),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                      label: const Text('Order'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ dialogs

String _eventText(SessionEvent e) {
  final m = e.minutes ?? 0;
  final text = switch (e.type) {
    'start' =>
      '${e.note == null ? 'Started' : 'Started for ${e.note}'}, ${m > 0 ? 'booked ${Billing.duration(m)}' : 'open play'}',
    'pause' => 'Paused',
    'resume' => 'Resumed',
    'extend' => 'Added ${Billing.duration(m)}',
    'booking' => m > 0 ? 'Booking set to ${Billing.duration(m)}' : 'Changed to open play',
    'adjust' => '${m > 0 ? 'Added' : 'Removed'} ${Billing.duration(m.abs())} of played time',
    'stop' => 'Stopped',
    _ => e.type,
  };
  return e.note == null || e.type == 'start' ? text : '$text: ${e.note}';
}

/// Change the booking, correct the played time, and see the table's timer history.
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.table});

  final RestaurantTable table;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _reason = TextEditingController();
  int? _booked;
  int _delta = 0;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    final s = store.sessionFor(widget.table);
    if (s == null || s.timerStartedAt == null) {
      return AlertDialog(
        title: Text(widget.table.name, style: CbText.cardTitle(context)),
        content: const Text('This table has no game in play.'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
    }
    final booked = _booked ??= s.bookedMinutes ?? 0;
    final playedMin = (s.elapsedSeconds() / 60).ceil();
    final changed = booked != (s.bookedMinutes ?? 0) || _delta != 0;
    final needsReason = AppStore.adjustNeedsReason(s, bookedMinutes: booked, playedDeltaMinutes: _delta);
    final bold = TextStyle(color: cb.ink, fontWeight: FontWeight.w600, fontSize: 14.5);

    Future<void> save() async {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await store.adjustTimer(widget.table, bookedMinutes: booked, playedDeltaMinutes: _delta, reason: _reason.text);
        if (context.mounted) Navigator.of(context).pop();
      } on CueBillException catch (e) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }

    return AlertDialog(
      title: Text('Adjust ${widget.table.name}', style: CbText.cardTitle(context)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Booked time', style: bold),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CbChip(label: 'Open play', selected: booked == 0, onTap: () => setState(() => _booked = 0)),
                  MinuteStepper(
                    value: booked,
                    step: 15,
                    min: 0,
                    max: 12 * 60,
                    label: 'booked time',
                    format: bookingLabel,
                    onChanged: (v) => setState(() => _booked = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Correct played time', style: bold),
              const SizedBox(height: 2),
              Text('If the game was started late or left running by mistake.', style: CbText.muted(context, 12.5)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  Text(
                    _delta == 0
                        ? 'Played ${Billing.duration(playedMin)}'
                        : 'Played ${Billing.duration(playedMin)} → ${Billing.duration(math.max(0, playedMin + _delta))}',
                    style: CbText.num(context, size: 14, color: cb.ink),
                  ),
                  MinuteStepper(
                    value: _delta,
                    step: 5,
                    min: -playedMin,
                    max: 4 * 60,
                    label: 'played time',
                    format: (v) => v == 0 ? 'No change' : '${v > 0 ? '+' : '−'}${v.abs()} min',
                    onChanged: (v) => setState(() => _delta = v),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _reason,
                decoration: InputDecoration(
                  labelText: needsReason ? 'Reason (required)' : 'Reason (optional)',
                  hintText: 'e.g. game started 10 min late',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (s.events.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Game history', style: bold),
                const SizedBox(height: 6),
                for (final e in s.events.reversed.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(Fmt.time(e.at), style: CbText.num(context, size: 12.5, color: cb.muted)),
                        ),
                        Expanded(
                          child: Text(_eventText(e), style: TextStyle(color: cb.ink, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: !changed || _busy || (needsReason && _reason.text.trim().isEmpty) ? null : save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TableGrid extends StatelessWidget {
  const _TableGrid({required this.selectedId});

  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final tables = store.activeTables;
    if (tables.isEmpty) {
      return CbCard(
        child: Text('No tables yet. Add them in Menu & Tables → Tables.', style: CbText.muted(context, 14)),
      );
    }
    return ResponsiveGrid(
      minWidth: 160,
      spacing: 12,
      maxColumns: 4,
      children: [for (final t in tables) _TableCard(table: t, selected: t.id == selectedId)],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Material(
            color: cb.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: cb.line),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(icon, size: 16, color: cb.ink, semanticLabel: label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuPicker extends StatefulWidget {
  const _MenuPicker({required this.table, this.takeaway = false});

  final RestaurantTable? table;
  final bool takeaway;

  @override
  State<_MenuPicker> createState() => _MenuPickerState();
}

class _MenuPickerState extends State<_MenuPicker> {
  int? _categoryId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    final cats = store.categoryById;
    final q = _query.trim().toLowerCase();
    final items = store.sortedMenu
        .where((m) => m.isActive)
        .where((m) => _categoryId == null || m.categoryId == _categoryId)
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q))
        .toList();
    final table = widget.table;
    final inOrder = {
      for (final l in (table == null ? null : store.sessionFor(table))?.items ?? <SessionItem>[]) l.menuItemId: l.qty,
    };

    final search = SizedBox(
      width: 280,
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Search menu...',
          prefixIcon: Icon(Icons.search, size: 18),
          prefixIconConstraints: BoxConstraints(minWidth: 40),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );

    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final title = Text(
                table == null ? 'Add items' : 'Add items to ${table.name}',
                style: CbText.cardTitle(context),
              );
              if (c.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 12), search],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  search,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CbChip(label: 'All', selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
              for (final c in store.categories)
                CbChip(label: c.name, selected: _categoryId == c.id, onTap: () => setState(() => _categoryId = c.id)),
            ],
          ),
          const SizedBox(height: 16),
          if (table == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.takeaway
                    ? 'Start a takeaway order first, then tap an item to add it.'
                    : 'Pick a table first, then tap an item to add it.',
                style: CbText.muted(context, 13.5),
              ),
            ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No items match.', style: CbText.muted(context, 14))),
            )
          else
            ResponsiveGrid(
              minWidth: 150,
              spacing: 10,
              maxColumns: 5,
              children: [
                for (final m in items)
                  _MenuTile(
                    item: m,
                    category: cats[m.categoryId]?.name ?? '',
                    count: inOrder[m.id] ?? 0,
                    enabled: table != null,
                    onTap: () {
                      if (table == null) {
                        toast(context, widget.takeaway ? 'Start a takeaway order first.' : 'Pick a table first.');
                        return;
                      }
                      store.addItem(table, m);
                    },
                  ),
              ],
            ),
          if (table != null) const SizedBox(height: 2) else SizedBox(height: 0, child: ColoredBox(color: cb.line)),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.category,
    required this.count,
    required this.enabled,
    required this.onTap,
  });

  final MenuItem item;
  final String category;
  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Semantics(
      button: true,
      label: 'Add ${item.name}, ${Fmt.inr(item.price)}${count > 0 ? ', $count in order' : ''}',
      excludeSemantics: true,
      child: Material(
        color: cb.soft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: count > 0 ? cb.green : cb.line, width: count > 0 ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.6,
            child: Container(
              height: 80,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cb.ink, height: 1.25),
                        ),
                      ),
                      if (count > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: cb.green, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(Fmt.inr(item.price), style: CbText.num(context, weight: FontWeight.w700)),
                      const Spacer(),
                      Flexible(
                        child: Text(category, overflow: TextOverflow.ellipsis, style: CbText.muted(context, 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
