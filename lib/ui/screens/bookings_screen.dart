import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/billing.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../bookings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pool bookings, one day at a time: who booked, when, and the free slots in between.
/// Replaces the paper booking sheet.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  Future<List<Booking>>? _future;
  (DateTime, int)? _loaded;

  void _load(AppStore store) {
    final key = (_day, store.bookingRevision);
    if (_loaded == key) return;
    _loaded = key;
    _future = store.bookingsOn(_day);
  }

  void _go(DateTime day) => setState(() => _day = DateUtils.dateOnly(day));

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: now.subtract(const Duration(days: 365 * 3)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) _go(d);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    _load(store);
    final cb = context.cb;
    final today = DateUtils.dateOnly(DateTime.now());
    final isToday = _day == today;
    final pools = store.activeTables.where((t) => t.isPool).toList();

    final dateBar = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.outlined(
          tooltip: 'Previous day',
          onPressed: () => _go(_day.subtract(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_left),
        ),
        OutlinedButton.icon(
          onPressed: _pickDay,
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(isToday ? 'Today · ${Fmt.longDate(_day)}' : Fmt.longDate(_day)),
        ),
        IconButton.outlined(
          tooltip: 'Next day',
          onPressed: () => _go(_day.add(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_right),
        ),
        if (!isToday) TextButton(onPressed: () => _go(today), child: const Text('Today')),
      ],
    );

    return PageBody(
      maxWidth: 980,
      children: [
        PageHeader(
          title: 'Pool bookings',
          subtitle: 'Who has booked the pool table, and when it is free. Walk-ins show here too.',
          actions: [
            FilledButton.icon(
              onPressed: pools.isEmpty
                  ? null
                  : () => showBookingDialog(context, day: _day.isBefore(today) ? today : _day),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New booking'),
            ),
          ],
        ),
        dateBar,
        const SizedBox(height: 16),
        if (pools.isEmpty)
          CbCard(child: Text('No pool table yet. Add one in Menu & Tables → Tables.', style: CbText.muted(context, 14)))
        else
          FutureBuilder<List<Booking>>(
            future: _future,
            builder: (context, snap) {
              final list = snap.data;
              if (list == null) {
                return const CbCard(
                  child: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
                );
              }
              // Use the live copies of bookings still on the table, so the list follows the clock.
              final live = [for (final b in list) store.bookingById(b.id) ?? b];
              return _DayList(day: _day, bookings: live, multiTable: pools.length > 1);
            },
          ),
        const SizedBox(height: 12),
        Text(
          'Tap Start when the customer arrives: the game is billed from then for the booked time. '
          'Overlapping bookings are flagged but allowed, so you stay in charge.',
          style: TextStyle(color: cb.muted, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.day, required this.bookings, required this.multiTable});

  final DateTime day;
  final List<Booking> bookings;
  final bool multiTable;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    final holding = bookings.where((b) => b.status != 'cancelled' && b.status != 'no_show').toList();
    final minutes = holding.fold<int>(0, (sum, b) => sum + b.minutes);
    final summary = holding.isEmpty
        ? 'Nothing booked'
        : '${holding.length} booking${holding.length == 1 ? '' : 's'} · ${Billing.duration(minutes)} booked';

    return Ticking(
      builder: (context, now) {
        final rows = <Widget>[];
        DateTime? busyUntil;
        // Free slots are shown between bookings for a single pool table; from now on for today.
        if (!multiTable && DateUtils.isSameDay(day, now)) busyUntil = now;
        for (final b in bookings) {
          final holds = b.status != 'cancelled' && b.status != 'no_show';
          if (!multiTable && holds && busyUntil != null) {
            final gap = b.startAt.difference(busyUntil).inMinutes;
            if (gap >= 15) rows.add(_FreeRow(from: busyUntil, to: b.startAt));
          }
          if (rows.isNotEmpty) rows.add(Divider(height: 1, color: cb.line));
          rows.add(BookingTile(booking: b, showTable: multiTable));
          if (holds) {
            var end = b.endAt;
            if (b.isPlaying) {
              final t = store.tableById(b.tableId);
              end = (t == null ? null : store.sessionFor(t)?.expectedEnd(now)) ?? now;
            }
            if (busyUntil == null || end.isAfter(busyUntil)) busyUntil = end;
          }
        }

        return CbCard(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardHeader(summary, bottom: 6),
              if (bookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No bookings on this day. Tap New booking to add one.', style: CbText.muted(context, 14)),
                )
              else
                ...rows,
            ],
          ),
        );
      },
    );
  }
}

class _FreeRow extends StatelessWidget {
  const _FreeRow({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final gap = to.difference(from).inMinutes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: cb.greenText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Free ${bookingSlot(from, to)} · ${Billing.duration(gap)}',
              style: TextStyle(color: cb.greenText, fontWeight: FontWeight.w500, fontSize: 13.5),
            ),
          ),
          TextButton(
            onPressed: () => showBookingDialog(context, start: suggestStartAfter(from)),
            child: const Text('Book'),
          ),
        ],
      ),
    );
  }
}

/// A gap's start rounded up to the next quarter hour.
DateTime suggestStartAfter(DateTime t) {
  final m = ((t.minute + (t.second > 0 ? 1 : 0)) / 15).ceil() * 15;
  return DateTime(t.year, t.month, t.day, t.hour).add(Duration(minutes: m));
}
