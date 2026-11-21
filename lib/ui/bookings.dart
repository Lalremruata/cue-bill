import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/billing.dart';
import '../core/format.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pool booking dialog, booking rows and their actions, shared by Tables & Orders and Bookings.

const bookingPresets = [30, 60, 90, 120];

String bookingLabel(int m) => m == 0 ? 'Open play' : Billing.duration(m);

/// `[–] 1h 15m [+]`
class MinuteStepper extends StatelessWidget {
  const MinuteStepper({
    super.key,
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

/// `6:00 – 7:30 PM`
String bookingSlot(DateTime from, DateTime to) => '${Fmt.time(from)} – ${Fmt.time(to)}';

DateTime _roundUp(DateTime t, [int minutes = 15]) {
  final base = DateTime(t.year, t.month, t.day, t.hour);
  final m = ((t.minute + (t.second > 0 ? 1 : 0)) / minutes).ceil() * minutes;
  return base.add(Duration(minutes: m));
}

/// The first start from [from] (in 15-minute steps) where [minutes] on [tableId] clashes with nothing.
DateTime suggestStart(AppStore store, int tableId, int minutes, DateTime from) {
  var t = _roundUp(from);
  for (var i = 0; i < 40; i++) {
    final clash = store.bookingConflicts(
      Booking(tableId: tableId, customerName: '-', startAt: t, minutes: math.max(minutes, 15)),
    );
    if (clash.isEmpty) return t;
    t = _roundUp(clash.map((c) => c.to).reduce((a, b) => a.isAfter(b) ? a : b));
  }
  return _roundUp(from);
}

/// New booking ([table] or the first pool table, on [day]), edit a booking ([edit]), or a walk-in
/// on [table] that starts now ([walkIn]). Returns true once saved or started.
Future<bool> showBookingDialog(
  BuildContext context, {
  RestaurantTable? table,
  Booking? edit,
  bool walkIn = false,
  DateTime? day,
  DateTime? start,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => BookingDialog(table: table, edit: edit, walkIn: walkIn, day: day, start: start),
  );
  return ok ?? false;
}

class BookingDialog extends StatefulWidget {
  const BookingDialog({super.key, this.table, this.edit, this.walkIn = false, this.day, this.start});

  final RestaurantTable? table;
  final Booking? edit;
  final bool walkIn;
  final DateTime? day;
  final DateTime? start;

  @override
  State<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<BookingDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  int? _customerId;
  late int? _tableId;
  late DateTime _start;
  late int _minutes;
  String _lookup = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    final pools = store.activeTables.where((t) => t.isPool).toList();
    final e = widget.edit;
    _tableId = e?.tableId ?? widget.table?.id ?? pools.firstOrNull?.id;
    final preset = store.settings.defaultBookingMinutes;
    _minutes = e?.minutes ?? (widget.walkIn ? preset : (preset > 0 ? preset : 60));
    if (e != null) {
      _name.text = e.customerName;
      _phone.text = e.customerPhone ?? '';
      _note.text = e.note ?? '';
      _customerId = e.customerId;
      _start = e.startAt;
    } else if (widget.start != null) {
      _start = widget.start!;
    } else {
      final now = DateTime.now();
      final d = widget.day;
      final from = d == null || DateUtils.isSameDay(d, now) || d.isBefore(now)
          ? now
          : DateTime(d.year, d.month, d.day, 10);
      _start = _tableId == null ? _roundUp(from) : suggestStart(store, _tableId!, _minutes, from);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Booking _draft() => Booking(
    id: widget.edit?.id,
    tableId: _tableId ?? 0,
    customerName: _name.text,
    customerPhone: _phone.text,
    customerId: _customerId,
    note: _note.text,
    startAt: widget.walkIn ? DateTime.now() : _start,
    minutes: _minutes,
    createdAt: widget.edit?.createdAt,
  );

  void _typed(String value) {
    final c = context.read<AppStore>().customerById(_customerId);
    setState(() {
      // Editing the details away from the regular's means it is someone else.
      if (c != null && (_name.text.trim() != c.name || Customer.normalisePhone(_phone.text) != c.phone)) {
        _customerId = null;
      }
      _lookup = value;
      _error = null;
    });
  }

  void _pick(Customer c) => setState(() {
    _customerId = c.id;
    _name.text = c.name;
    _phone.text = c.phone ?? '';
    _lookup = '';
    _error = null;
  });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t != null) setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final store = context.read<AppStore>();
    final table = store.tableById(_tableId);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Clashes are shown above the button, so pressing it means staff accept them.
      if (widget.walkIn) {
        if (table == null) throw CueBillException('Pick a pool table.');
        await store.startWalkIn(
          table,
          name: _name.text,
          phone: _phone.text,
          customerId: _customerId,
          minutes: _minutes,
          note: _note.text,
          allowOverlap: true,
        );
      } else {
        await store.saveBooking(_draft(), allowOverlap: true);
      }
      if (mounted) Navigator.of(context).pop(true);
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
    final store = context.watch<AppStore>();
    final cb = context.cb;
    final st = store.settings;
    final pools = store.activeTables.where((t) => t.isPool).toList();
    final table = store.tableById(_tableId);
    final draft = _draft();
    final conflicts = _tableId == null ? <BookingConflict>[] : store.bookingConflicts(draft);
    final m = _minutes;
    final start = draft.startAt;
    final rate = st.poolRateFor(table, start);
    final bold = TextStyle(color: cb.ink, fontWeight: FontWeight.w600, fontSize: 14.5);
    final matches = store.searchCustomers(_lookup, limit: 4).where((c) => c.id != _customerId).toList();
    final linked = store.customerById(_customerId);
    final presets = [if (widget.walkIn) 0, ...bookingPresets];

    final String info;
    if (m == 0) {
      info =
          'Counts up until you end the game. Billed for time played, '
          'in ${st.billingBlockMinutes}-min blocks, minimum ${st.minimumMinutes} min.';
    } else {
      final price = Fmt.inr(Billing.poolAmount(math.max(m, st.minimumMinutes), rate));
      info =
          '${widget.walkIn ? 'Ends' : 'Until'} ${Fmt.time(start.add(Duration(minutes: m)))}. '
          '${st.bookedIsMinimum ? 'The full ${Billing.duration(m)} is charged' : 'Charged for time played, up to ${Billing.duration(m)}'}'
          ' ($price + GST at ${Fmt.inr(rate)}/hr). Add time later with +30 min or +1 hour.';
    }

    final title = widget.walkIn
        ? 'Walk-in · ${table?.name ?? 'Pool table'}'
        : (widget.edit != null ? 'Edit booking' : 'New booking');
    final String action;
    if (widget.walkIn) {
      action = conflicts.isEmpty ? 'Start now' : 'Start anyway';
    } else {
      action = conflicts.isEmpty ? (widget.edit != null ? 'Save' : 'Book') : 'Book anyway';
    }

    return AlertDialog(
      title: Text(title, style: CbText.cardTitle(context)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pools.length > 1 && !widget.walkIn) ...[
                FieldLabel(
                  'Pool table',
                  child: DropdownButtonFormField<int>(
                    initialValue: _tableId,
                    items: [for (final t in pools) DropdownMenuItem(value: t.id, child: Text(t.name))],
                    onChanged: (v) => setState(() => _tableId = v),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              FieldLabel(
                'Customer name',
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Who is playing?'),
                  onChanged: _typed,
                ),
              ),
              const SizedBox(height: 14),
              FieldLabel(
                'Phone (optional)',
                child: TextField(controller: _phone, keyboardType: TextInputType.phone, onChanged: _typed),
              ),
              if (linked != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 16, color: cb.greenText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        linked.discountPercent > 0
                            ? 'Regular customer · ${Fmt.trim(linked.discountPercent)}% off at checkout'
                            : 'Regular customer',
                        style: TextStyle(color: cb.greenText, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
              for (final c in matches)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _pick(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 18, color: cb.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${c.name}  ${c.phone ?? ''}'.trim(),
                            style: TextStyle(color: cb.ink, fontSize: 14),
                          ),
                        ),
                        if (c.discountPercent > 0) CbBadge('${Fmt.trim(c.discountPercent)}% off', tone: Tone.green),
                      ],
                    ),
                  ),
                ),
              if (!widget.walkIn) ...[
                const SizedBox(height: 18),
                Text('When', style: bold),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        DateUtils.isSameDay(_start, DateTime.now()) ? 'Today, ${Fmt.date(_start)}' : Fmt.date(_start),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(Fmt.time(_start)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Text('How long?', style: bold),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in presets)
                    CbChip(label: bookingLabel(p), selected: m == p, onTap: () => setState(() => _minutes = p)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  Text(
                    'Other time',
                    style: TextStyle(color: cb.ink, fontWeight: FontWeight.w500),
                  ),
                  MinuteStepper(
                    value: m,
                    step: 15,
                    min: widget.walkIn ? 0 : 15,
                    max: 12 * 60,
                    label: 'time',
                    format: bookingLabel,
                    onChanged: (v) => setState(() => _minutes = v),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FieldLabel(
                'Note (optional)',
                child: TextField(
                  controller: _note,
                  decoration: const InputDecoration(hintText: 'e.g. paid ₹100 advance'),
                ),
              ),
              const SizedBox(height: 14),
              Text(info, style: CbText.muted(context, 13).copyWith(height: 1.4)),
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cb.amberSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cb.amber.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in conflicts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 17, color: cb.amber),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  AppStore.describeConflict(c),
                                  style: TextStyle(color: cb.amber, fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        widget.walkIn
                            ? 'You can still start, but the table may not be free in time.'
                            : 'You can still book it if you have agreed this with the customers.',
                        style: TextStyle(color: cb.amber, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
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
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy || _name.text.trim().isEmpty ? null : _save,
          icon: Icon(widget.walkIn ? Icons.play_arrow_rounded : Icons.event_available_outlined, size: 20),
          label: Text(action),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ actions

/// Starts the game for [b], asking first when it is well before the booked time.
Future<bool> startBookingFlow(BuildContext context, Booking b) async {
  final store = context.read<AppStore>();
  final early = b.startAt.difference(DateTime.now()).inMinutes;
  if (early > 30) {
    final ok = await confirmDialog(
      context,
      title: 'Start ${b.customerName} early?',
      message:
          'This booking is for ${Fmt.date(b.startAt)} at ${Fmt.time(b.startAt)}. '
          'Starting now bills from now, for ${bookingLabel(b.minutes)}.',
      confirm: 'Start now',
    );
    if (!ok || !context.mounted) return false;
  }
  try {
    await store.startBooking(b);
    return true;
  } on CueBillException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return false;
  }
}

Future<void> cancelBookingFlow(BuildContext context, Booking b) async {
  final store = context.read<AppStore>();
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Cancel ${b.customerName}\'s booking?', style: CbText.cardTitle(c)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${Fmt.date(b.startAt)}, ${bookingSlot(b.startAt, b.endAt)}. '
              'The slot becomes free. You can restore it from Bookings.',
              style: TextStyle(color: c.cb.muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. phoned to cancel'),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep booking')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Cancel booking'),
        ),
      ],
    ),
  );
  final text = reason.text;
  reason.dispose();
  if (ok != true) return;
  try {
    await store.cancelBooking(b, reason: text);
  } on CueBillException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
}

Future<void> noShowFlow(BuildContext context, Booking b) async {
  final ok = await confirmDialog(
    context,
    title: 'Mark ${b.customerName} as no-show?',
    message: 'The slot becomes free. You can restore it from Bookings.',
    confirm: 'No-show',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  await context.read<AppStore>().markNoShow(b);
}

// ------------------------------------------------------------------ rows

Tone bookingTone(Booking b, DateTime now) => switch (b.status) {
  'booked' when !now.isBefore(b.startAt) => Tone.amber,
  'playing' => Tone.green,
  'cancelled' => Tone.red,
  'no_show' => Tone.amber,
  _ => Tone.neutral,
};

/// `Late 12 min`, `Due now`, or the status.
String bookingBadge(Booking b, DateTime now) {
  if (!b.isUpcoming) return b.statusLabel;
  final late = now.difference(b.startAt).inMinutes;
  if (late >= 1) return 'Late $late min';
  if (!now.isBefore(b.startAt)) return 'Due now';
  return b.statusLabel;
}

/// One booking: time, customer, phone and note, status, and what staff can do with it.
class BookingTile extends StatelessWidget {
  const BookingTile({super.key, required this.booking, this.showTable = false, this.compact = false});

  final Booking booking;
  final bool showTable;

  /// Inside the order panel: smaller, no divider.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;
    final b = booking;
    final table = store.tableById(b.tableId);
    final session = table == null ? null : store.sessionFor(table);
    final tableBusy = session != null && session.timerStartedAt != null;

    return Ticking(
      builder: (context, now) {
        // A game in play shows when it really started and when its booked time runs out.
        var from = b.startAt;
        DateTime? to = b.endAt;
        if (b.isPlaying && session?.bookingId == b.id && session?.timerStartedAt != null) {
          from = session!.timerStartedAt!;
          to = session.expectedEnd(now);
        }
        if (b.minutes == 0 && !b.isPlaying) to = null;
        final details = [
          if (showTable && table != null) table.name,
          if (b.customerPhone != null) b.customerPhone!,
          if (b.note != null) b.note!,
          if (b.cancelReason != null) b.cancelReason!,
        ].join(' · ');
        final muted = b.status == 'cancelled' || b.status == 'no_show';

        final actions = <Widget>[
          if (b.isUpcoming) ...[
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: tableBusy
                  ? null
                  : () async {
                      final nav = context.read<Nav>();
                      final started = await startBookingFlow(context, b);
                      if (started) {
                        nav.go(Section.pos);
                        nav.selectTable(b.tableId);
                      }
                    },
              child: const Text('Start'),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert, color: cb.muted),
              onSelected: (v) => switch (v) {
                'edit' => showBookingDialog(context, edit: b.copy()),
                'cancel' => cancelBookingFlow(context, b),
                _ => noShowFlow(context, b),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'cancel', child: Text('Cancel booking')),
                PopupMenuItem(value: 'no_show', child: Text('No-show')),
              ],
            ),
          ],
          if (b.isPlaying)
            TextButton(
              onPressed: () {
                final nav = context.read<Nav>();
                nav.go(Section.pos);
                nav.selectTable(b.tableId);
              },
              child: const Text('Open table'),
            ),
          if (muted)
            TextButton(
              onPressed: () async {
                try {
                  await store.restoreBooking(b);
                } on CueBillException catch (e) {
                  if (context.mounted) toast(context, e.message, error: true);
                }
              },
              child: const Text('Restore'),
            ),
        ];

        final timeStyle = CbText.num(
          context,
          size: compact ? 13.5 : 14.5,
          weight: FontWeight.w600,
          color: muted ? cb.muted : cb.ink,
        );
        return Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 10),
          child: Row(
            children: [
              SizedBox(
                width: compact ? 84 : 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.time(from), style: timeStyle),
                    Text(
                      to == null ? 'open play' : 'to ${Fmt.time(to)}',
                      style: CbText.muted(context, 12.5).copyWith(fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          b.customerName,
                          style: TextStyle(
                            color: muted ? cb.muted : cb.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: compact ? 14 : 15,
                            decoration: muted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        CbBadge(bookingBadge(b, now), tone: bookingTone(b, now)),
                      ],
                    ),
                    if (details.isNotEmpty)
                      Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: CbText.muted(context, 12.5)),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        );
      },
    );
  }
}
