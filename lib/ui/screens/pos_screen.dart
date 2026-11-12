import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/billing.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
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
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 32.0;

    final header = PageHeader(
      title: 'Tables & Orders',
      subtitle: 'Pick a table, start the pool timer, add food and drinks.',
      actions: [
        const LegendItem(label: 'In play', dot: DotState.running),
        const LegendItem(label: 'Paused / ordering', dot: DotState.busy),
        const LegendItem(label: 'Free', dot: DotState.free),
        LegendItem(label: 'Time up', color: context.cb.red),
      ],
    );
    const alerts = _BookingStrip();
    final grid = _TableGrid(selectedId: table?.id);
    final menu = _MenuPicker(table: table);

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1080) {
          // Tall enough: the panel's header and totals stay put and only the order lines scroll.
          final fill = c.maxHeight >= 600;
          final panel = _OrderPanel(key: ValueKey('panel-${table?.id}'), table: table, fill: fill);
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
                    children: [header, alerts, grid, const SizedBox(height: 24), menu],
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
        // Phones and tablets: tables, then the menu; the order is a bar that opens a sheet.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, pad - 4, pad, pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, alerts, grid, const SizedBox(height: 20), menu],
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

/// Asks how long the table is booked for, then starts the timer.
Future<void> _startTimer(BuildContext context, RestaurantTable table) async {
  final store = context.read<AppStore>();
  final minutes = await showDialog<int>(
    context: context,
    builder: (_) => _StartTimerDialog(table: table, settings: store.settings),
  );
  if (minutes != null) await store.startTimer(table, bookedMinutes: minutes);
}

Future<void> _stopTimer(BuildContext context, RestaurantTable table) async {
  final store = context.read<AppStore>();
  final ok = await confirmDialog(
    context,
    title: 'Stop the timer?',
    message: 'The pool time for ${table.name} is billed up to now. You cannot restart this timer.',
    confirm: 'Stop timer',
    danger: true,
  );
  if (ok) await store.stopTimer(table);
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
/// whichever screen is open. Wraps the app shell.
class BookingAlerts extends StatefulWidget {
  const BookingAlerts({super.key, required this.child});

  final Widget child;

  @override
  State<BookingAlerts> createState() => _BookingAlertsState();
}

class _BookingAlertsState extends State<BookingAlerts> {
  final _tracker = BookingAlertTracker();

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
    final open = <int>{};
    for (final (table, s) in store.openTables) {
      if (!table.isPool || s.id == null) continue;
      open.add(s.id!);
      final state = s.bookingState(settings.bookingWarnMinutes, now);
      final left = s.remainingSeconds(now) ?? 0;
      final alert = _tracker.check(s.id!, state, left, repeatMinutes: settings.overtimeRepeatMinutes);
      if (alert == null) continue;
      final overMinutes = -left ~/ 60;
      final message = switch (alert) {
        BookingAlert.timeUp => '${table.name}: booked time is up.',
        BookingAlert.stillOver => '${table.name}: time up, $overMinutes min over. Stop or extend the timer.',
        BookingAlert.warning => '${table.name}: ${(left / 60).ceil()} min left.',
      };
      final over = alert != BookingAlert.warning;
      if (over) {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
      }
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: over ? const Color(0xFFB42318) : const Color(0xFF8A4B08),
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
    _tracker.forgetExcept(open);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum BookingAlert { warning, timeUp, stillOver }

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
        final subtitle = table.isPool ? 'Pool table · ${Fmt.inr(rate)}/hr' : table.typeLabel;
        final booking = session?.bookingState(store.settings.bookingWarnMinutes, now) ?? BookingState.none;

        String value;
        String sub;
        if (session == null) {
          value = 'Free';
          sub = 'Tap to open';
        } else {
          final calc = store.calcFor(table, now: now)!;
          final left = session.remainingSeconds(now);
          if (table.isPool && session.timerStartedAt != null && left != null) {
            value = _countdown(left);
            final paused = session.timerState == TimerState.paused ? 'Paused · ' : '';
            sub = switch (booking) {
              BookingState.over => 'Time up · ${Fmt.inr(calc.totals.total)}',
              _ => '$paused${left > 0 ? 'left' : 'done'} · ${Fmt.inr(calc.totals.total)}',
            };
          } else if (table.isPool && session.timerStartedAt != null) {
            value = Fmt.timer(session.elapsedSeconds(now));
            sub = '${Fmt.inr(calc.totals.total)} so far';
          } else if (session.items.isNotEmpty) {
            value = Fmt.inr(calc.totals.total);
            final n = session.itemCount;
            sub = '$n item${n == 1 ? '' : 's'}';
          } else {
            value = 'Open';
            sub = table.isPool ? 'Timer not started' : 'No items yet';
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
          label: '${table.name}, ${dot == DotState.free ? 'free' : value}$stateLabel',
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
                onTap: () => context.read<Nav>().selectTable(table.id),
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
  const _OrderPanel({super.key, required this.table, this.fill = false, this.inSheet = false});

  final RestaurantTable? table;
  final bool fill;

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
                const Text(
                  'No table selected',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap a table to open it, start the pool timer or add food.',
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
            '${table.typeLabel} · ${s == null ? 'Free' : '$n item${n == 1 ? '' : 's'}'}',
            style: TextStyle(color: dim, fontSize: 13.5),
          ),
        ],
      );
    }

    final booked = s?.bookedMinutes;
    final bookedText = booked == null ? 'open play' : 'booked ${Billing.duration(booked)}';
    final statusText = switch (state) {
      TimerState.idle => s == null ? 'Free' : 'Timer not started',
      TimerState.running => 'In play · $bookedText',
      TimerState.paused => 'Paused · $bookedText',
      TimerState.stopped => 'Timer stopped',
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
                ? FilledButton(style: dense, onPressed: () => store.extendBooking(table, m), child: Text(label))
                : OutlinedButton(
                    style: darkOutline,
                    onPressed: () => store.extendBooking(table, m),
                    child: Text(label),
                  ),
        ];

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

        return _DarkHeader(
          compact: compact,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table.name,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text('Pool table · $statusText', style: TextStyle(color: dim, fontSize: 13.5)),
                    ],
                  ),
                ),
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
            SizedBox(height: compact ? 12 : 14),
            Wrap(
              spacing: compact ? 8 : 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: switch (state) {
                TimerState.idle => [
                  FilledButton.icon(
                    onPressed: () => _startTimer(context, table),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Start timer'),
                  ),
                ],
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
                    child: const Text('Stop timer'),
                  ),
                ],
                TimerState.paused => [
                  FilledButton(style: dense, onPressed: () => store.resumeTimer(table), child: const Text('Resume')),
                  if (s!.isBooked) ...extend(),
                  OutlinedButton(
                    style: stopStyle,
                    onPressed: () => _stopTimer(context, table),
                    child: const Text('Stop timer'),
                  ),
                ],
                TimerState.stopped => [
                  Text(
                    'Stopped at ${Fmt.time(s!.timerStoppedAt!)}. Ready for checkout.',
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
                                title: 'Clear ${table.name}?',
                                message:
                                    'This removes the order and the timer without billing. Use it for a table opened by mistake.',
                                confirm: 'Clear table',
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
                              nav.openCheckout(table.id!);
                            },
                      child: Text(
                        table.isPool && session?.timerState != TimerState.stopped && session?.timerStartedAt != null
                            ? 'Stop & checkout'
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
          status = table.isPool ? 'Free · start the timer' : 'Free · tap a menu item to add it';
        } else if (table.isPool && s.timerStartedAt != null) {
          final left = s.remainingSeconds(now);
          final paused = s.timerState == TimerState.paused ? ' · paused' : '';
          final stopped = s.timerState == TimerState.stopped ? ' · stopped' : '';
          status = left == null
              ? '${Fmt.timer(s.elapsedSeconds(now))} played$paused$stopped'
              : left > 0
              ? '${Fmt.timer(left)} left$paused$stopped'
              : 'Time up · ${_countdown(left)}$stopped';
        } else {
          status = table.isPool ? 'Timer not started' : '$n item${n == 1 ? '' : 's'}';
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
                    FilledButton(onPressed: () => _startTimer(context, table), child: const Text('Start'))
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

/// `[–] 1h 15m [+]`
class _MinuteStepper extends StatelessWidget {
  const _MinuteStepper({
    required this.value,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.format,
    required this.label,
  });

  final int value;
  final int step;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String Function(int) format;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Less $label',
          onPressed: value - step >= min ? () => onChanged(value - step) : (value > min ? () => onChanged(min) : null),
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(
          width: 96,
          child: Text(
            format(value),
            textAlign: TextAlign.center,
            style: CbText.num(context, size: 15, weight: FontWeight.w600, color: cb.ink),
          ),
        ),
        IconButton.outlined(
          tooltip: 'More $label',
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

const _bookingPresets = [0, 30, 60, 90, 120];

String _bookingLabel(int m) => m == 0 ? 'Open play' : Billing.duration(m);

/// Pick a booking (or open play) before the timer starts. Pops the minutes; 0 = open play.
class _StartTimerDialog extends StatefulWidget {
  const _StartTimerDialog({required this.table, required this.settings});

  final RestaurantTable table;
  final BusinessSettings settings;

  @override
  State<_StartTimerDialog> createState() => _StartTimerDialogState();
}

class _StartTimerDialogState extends State<_StartTimerDialog> {
  late int _minutes = widget.settings.defaultBookingMinutes;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final st = widget.settings;
    final rate = st.poolRateFor(widget.table, DateTime.now());
    final m = _minutes;
    final info = m == 0
        ? 'Counts up until you stop it. Billed for time played, '
              'in ${st.billingBlockMinutes}-min blocks, minimum ${st.minimumMinutes} min.'
        : 'Counts down from ${Billing.duration(m)} and warns you when time is up; it keeps running until stopped. '
              '${st.bookedIsMinimum ? 'The full ${Billing.duration(m)} is charged' : 'Charged for time played, up to ${Billing.duration(m)}'}'
              ' (${Fmt.inr(Billing.poolAmount(math.max(m, st.minimumMinutes), rate))} + GST at ${Fmt.inr(rate)}/hr). '
              'Add time later with +30 min or +1 hour.';

    return AlertDialog(
      title: Text('Start ${widget.table.name}', style: CbText.cardTitle(context)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('How long is the table booked for?', style: CbText.muted(context, 14)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _bookingPresets)
                    CbChip(label: _bookingLabel(p), selected: m == p, onTap: () => setState(() => _minutes = p)),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  Text(
                    'Other time',
                    style: TextStyle(color: cb.ink, fontWeight: FontWeight.w500),
                  ),
                  _MinuteStepper(
                    value: m,
                    step: 15,
                    min: 0,
                    max: 12 * 60,
                    label: 'time',
                    format: _bookingLabel,
                    onChanged: (v) => setState(() => _minutes = v),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(info, style: CbText.muted(context, 13).copyWith(height: 1.4)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_minutes),
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: const Text('Start timer'),
        ),
      ],
    );
  }
}

String _eventText(SessionEvent e) {
  final m = e.minutes ?? 0;
  final text = switch (e.type) {
    'start' => m > 0 ? 'Started, booked ${Billing.duration(m)}' : 'Started, open play',
    'pause' => 'Paused',
    'resume' => 'Resumed',
    'extend' => 'Added ${Billing.duration(m)}',
    'booking' => m > 0 ? 'Booking set to ${Billing.duration(m)}' : 'Changed to open play',
    'adjust' => '${m > 0 ? 'Added' : 'Removed'} ${Billing.duration(m.abs())} of played time',
    'stop' => 'Stopped',
    _ => e.type,
  };
  return e.note == null ? text : '$text: ${e.note}';
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
        content: const Text('This table has no timer running.'),
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
                  _MinuteStepper(
                    value: booked,
                    step: 15,
                    min: 0,
                    max: 12 * 60,
                    label: 'booked time',
                    format: _bookingLabel,
                    onChanged: (v) => setState(() => _booked = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Correct played time', style: bold),
              const SizedBox(height: 2),
              Text('If the timer was started late or left running by mistake.', style: CbText.muted(context, 12.5)),
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
                  _MinuteStepper(
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
                  hintText: 'e.g. timer started 10 min late',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (s.events.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Timer history', style: bold),
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
  const _MenuPicker({required this.table});

  final RestaurantTable? table;

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
              child: Text('Pick a table first, then tap an item to add it.', style: CbText.muted(context, 13.5)),
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
                        toast(context, 'Pick a table first.');
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
