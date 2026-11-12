import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/billing.dart';
import '../../core/format.dart';
import '../../core/upi.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/checkout.dart';
import '../../services/drive_backup.dart';
import '../../services/drive_sync.dart';
import '../files.dart';
import '../receipt_view.dart';
import '../theme.dart';
import '../widgets.dart';

const indianStates = [
  'Andaman and Nicobar Islands',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Ladakh',
  'Lakshadweep',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Puducherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

final _decimal = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];
final _digits = [FilteringTextInputFormatter.digitsOnly];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _c = <String, TextEditingController>{};
  late String _state;
  late bool _showQr;
  late int _block;
  late int _minimum;
  late int _defaultBooking;
  late int _grace;
  late int _warn;
  late int _repeat;
  late bool _bookedIsMinimum;
  late bool _happy;
  late String _happyStart;
  late String _happyEnd;
  String? _logoPath;
  bool _dirty = false;
  bool _busy = false;

  static const _textFields = [
    'name',
    'address',
    'city',
    'pin',
    'phone',
    'email',
    'gstin',
    'fssai',
    'prefix',
    'next',
    'footer',
    'gst_food',
    'gst_pool',
    'upi_id',
    'upi_payee',
    'pool_rate',
    'pool_cost',
    'happy_rate',
  ];

  @override
  void initState() {
    super.initState();
    for (final f in _textFields) {
      _c[f] = TextEditingController()..addListener(_changed);
    }
    _fill(context.read<AppStore>().settings);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _filling = false;

  void _changed() {
    if (_filling || !mounted) return;
    setState(() => _dirty = true);
  }

  void _fill(BusinessSettings s) {
    String n(double v) => Fmt.trim(v);
    final values = {
      'name': s.name,
      'address': s.address ?? '',
      'city': s.city ?? '',
      'pin': s.pin ?? '',
      'phone': s.phone ?? '',
      'email': s.email ?? '',
      'gstin': s.gstin ?? '',
      'fssai': s.fssai ?? '',
      'prefix': s.invoicePrefix,
      'next': '${s.nextInvoiceNumber}',
      'footer': s.invoiceFooter ?? '',
      'gst_food': n(s.gstFoodRate),
      'gst_pool': n(s.gstPoolRate),
      'upi_id': s.upiId ?? '',
      'upi_payee': s.upiPayeeName ?? '',
      'pool_rate': n(s.poolRatePerHour),
      'pool_cost': n(s.poolCostPerHour),
      'happy_rate': n(s.happyHourRate),
    };
    _filling = true;
    for (final e in values.entries) {
      _c[e.key]!.value = TextEditingValue(text: e.value);
    }
    _filling = false;
    _state = s.state;
    _showQr = s.showUpiQr;
    _block = s.billingBlockMinutes;
    _minimum = s.minimumMinutes;
    _defaultBooking = s.defaultBookingMinutes;
    _grace = s.overtimeGraceMinutes;
    _warn = s.bookingWarnMinutes;
    _repeat = s.overtimeRepeatMinutes;
    _bookedIsMinimum = s.bookedIsMinimum;
    _happy = s.happyHourEnabled;
    _happyStart = s.happyHourStart;
    _happyEnd = s.happyHourEnd;
    _logoPath = s.logoPath;
    _dirty = false;
  }

  String _t(String f) => _c[f]!.text.trim();
  String? _opt(String f) => _t(f).isEmpty ? null : _t(f);
  double _num(String f, double fallback) => double.tryParse(_t(f)) ?? fallback;

  BusinessSettings _draft(BusinessSettings base) => BusinessSettings(
    name: _t('name').isEmpty ? base.name : _t('name'),
    address: _opt('address'),
    city: _opt('city'),
    state: _state,
    pin: _opt('pin'),
    phone: _opt('phone'),
    email: _opt('email'),
    gstin: _opt('gstin')?.toUpperCase(),
    fssai: _opt('fssai'),
    logoPath: _logoPath,
    invoicePrefix: _t('prefix'),
    nextInvoiceNumber: int.tryParse(_t('next')) ?? base.nextInvoiceNumber,
    invoiceFooter: _opt('footer'),
    upiId: _opt('upi_id'),
    upiPayeeName: _opt('upi_payee'),
    showUpiQr: _showQr,
    poolRatePerHour: _num('pool_rate', base.poolRatePerHour),
    billingBlockMinutes: _block,
    minimumMinutes: _minimum,
    defaultBookingMinutes: _defaultBooking,
    overtimeGraceMinutes: _grace,
    bookingWarnMinutes: _warn,
    overtimeRepeatMinutes: _repeat,
    bookedIsMinimum: _bookedIsMinimum,
    poolCostPerHour: _num('pool_cost', base.poolCostPerHour),
    happyHourEnabled: _happy,
    happyHourRate: _num('happy_rate', base.happyHourRate),
    happyHourStart: _happyStart,
    happyHourEnd: _happyEnd,
    gstFoodRate: _num('gst_food', base.gstFoodRate),
    gstPoolRate: _num('gst_pool', base.gstPoolRate),
    savedAt: base.savedAt,
    lastBackupAt: base.lastBackupAt,
    driveAutoBackup: base.driveAutoBackup,
    driveLastBackupAt: base.driveLastBackupAt,
    driveFolderId: base.driveFolderId,
  );

  String? _validate() {
    if (_t('name').isEmpty) return 'Enter the restaurant name.';
    if (_t('gstin').isNotEmpty && !Upi.isValidGstin(_t('gstin').toUpperCase())) return 'The GSTIN format is not valid.';
    if (_t('upi_id').isNotEmpty && !Upi.isValidUpiId(_t('upi_id'))) return 'The UPI ID format is not valid.';
    if ((int.tryParse(_t('next')) ?? 0) < 1) return 'Next invoice number must be 1 or more.';
    for (final f in ['gst_food', 'gst_pool']) {
      final v = double.tryParse(_t(f));
      if (v == null || v < 0 || v > 40) return 'GST rates must be between 0 and 40%.';
    }
    if ((double.tryParse(_t('pool_rate')) ?? 0) <= 0) return 'Enter the pool table rate per hour.';
    if (_happy && _happyStart.compareTo(_happyEnd) >= 0) return 'Happy hour must end after it starts.';
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      toast(context, error, error: true);
      return;
    }
    final store = context.read<AppStore>();
    await store.saveSettings(_draft(store.settings));
    if (!mounted) return;
    setState(() => _dirty = false);
    toast(context, 'Settings saved. New invoices use these details.');
  }

  void _discard() => setState(() => _fill(context.read<AppStore>().settings));

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;
    final ext = (file.extension ?? 'png').toLowerCase();
    final path = await context.read<AppStore>().storeLogo(file.bytes!, ext);
    setState(() {
      _logoPath = path;
      _dirty = true;
    });
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _happyStart : _happyEnd;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 12, minute: int.tryParse(parts[1]) ?? 0),
    );
    if (picked == null) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        _happyStart = v;
      } else {
        _happyEnd = v;
      }
      _dirty = true;
    });
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final bytes = await context.read<AppStore>().backupBytes();
      if (!mounted) return;
      await Files.save(
        context,
        bytes: bytes,
        fileName: 'cuebill-backup-${Fmt.isoDate(DateTime.now())}.sqlite',
        extension: 'sqlite',
        done: 'Backup saved. Keep a copy on a USB drive or Google Drive.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await confirmDialog(
      context,
      title: 'Restore from a backup?',
      message:
          'All sales, menu, tables and settings on this device are replaced by the backup. '
          'Make a fresh backup first if you may need today\'s data.',
      confirm: 'Choose backup file',
      danger: true,
    );
    if (!ok || !mounted) return;
    final result = await FilePicker.pickFiles(type: FileType.any, withData: true);
    final file = result?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final store = context.read<AppStore>();
      await store.restore(file!.bytes!);
      if (!mounted) return;
      setState(() => _fill(store.settings));
      toast(context, 'Backup restored.');
    } on CueBillException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (e) {
      if (mounted) toast(context, 'Could not restore: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sample() async {
    final ok = await confirmDialog(
      context,
      title: 'Load sample sales?',
      message:
          'Adds about 45 days of made-up sales so you can try the dashboard and reports. '
          'They count as real invoices and cannot be deleted one by one. Use this on a test install, or restore a backup afterwards.',
      confirm: 'Load sample sales',
    );
    if (!ok || !mounted) return;
    if (_dirty) await _save();
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final store = context.read<AppStore>();
      final n = await store.loadSampleSales();
      if (!mounted) return;
      setState(() => _fill(store.settings));
      toast(context, 'Added $n sample invoices.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final draft = _draft(store.settings);
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 32.0;
    final saved = store.settings.savedAt;

    final header = PageHeader(
      title: 'Business settings',
      subtitle: 'Saved on this device. Every new invoice prints these details and UPI QR.',
      actions: [
        if (saved != null && !_dirty) Text('Saved ${Fmt.relativeDay(saved)}', style: CbText.muted(context)),
        if (_dirty)
          Text(
            'Unsaved changes',
            style: TextStyle(color: context.cb.amber, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        OutlinedButton(onPressed: _dirty ? _discard : null, child: const Text('Discard changes')),
        FilledButton(onPressed: _save, child: const Text('Save changes')),
      ],
    );

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _restaurantCard(context),
        const SizedBox(height: 16),
        _taxCard(context, draft),
        const SizedBox(height: 16),
        _upiCard(context),
        const SizedBox(height: 16),
        _poolCard(context),
        const SizedBox(height: 16),
        _backupCard(context, store),
        const SizedBox(height: 16),
        _DriveCard(onRestored: () => setState(() => _fill(context.read<AppStore>().settings))),
      ],
    );

    final preview = _Preview(draft: draft);

    final body = LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1100) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, pad - 4, 12, pad + 60),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, form]),
                ),
              ),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(12, pad + 78, pad, pad), child: preview),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, pad - 4, pad, pad + 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, form, const SizedBox(height: 20), preview],
          ),
        );
      },
    );

    return Stack(
      children: [
        Positioned.fill(
          child: AbsorbPointer(absorbing: _busy, child: body),
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_dirty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SaveBar(onDiscard: _discard, onSave: _save),
          ),
      ],
    );
  }

  Widget _field(
    String label,
    String key, {
    List<TextInputFormatter>? formatters,
    TextInputType? keyboard,
    Widget? helper,
    String? prefix,
    String? suffix,
    TextCapitalization caps = TextCapitalization.none,
    int? maxLength,
  }) {
    return FieldLabel(
      label,
      helper: helper,
      child: TextField(
        controller: _c[key],
        inputFormatters: formatters,
        keyboardType: keyboard,
        textCapitalization: caps,
        maxLength: maxLength,
        decoration: InputDecoration(prefixText: prefix, suffixText: suffix, counterText: ''),
      ),
    );
  }

  Widget _restaurantCard(BuildContext context) {
    final cb = context.cb;
    final logo = _logoPath != null && File(_logoPath!).existsSync() ? File(_logoPath!) : null;
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Restaurant details'),
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cb.soft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cb.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: logo == null
                    ? Icon(Icons.image_outlined, color: cb.muted)
                    : Image.file(logo, fit: BoxFit.contain, semanticLabel: 'Logo'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(onPressed: _pickLogo, child: Text(logo == null ? 'Upload logo' : 'Change logo')),
                        if (logo != null)
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: cb.red),
                            onPressed: () => setState(() {
                              _logoPath = null;
                              _dirty = true;
                            }),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('PNG or JPG, printed in black and white on receipts.', style: CbText.muted(context, 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _field('Restaurant name', 'name', caps: TextCapitalization.words),
          const SizedBox(height: 14),
          _field('Address', 'address'),
          const SizedBox(height: 14),
          FieldRow(
            children: [
              _field('City', 'city', caps: TextCapitalization.words),
              FieldLabel(
                'State',
                child: DropdownButtonFormField<String>(
                  value: indianStates.contains(_state) ? _state : null,
                  isExpanded: true,
                  items: [
                    for (final s in indianStates)
                      DropdownMenuItem(
                        value: s,
                        child: Text(s, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _state = v ?? _state;
                    _dirty = true;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FieldRow(
            children: [
              _field('PIN code', 'pin', formatters: _digits, keyboard: TextInputType.number, maxLength: 6),
              _field('Phone', 'phone', keyboard: TextInputType.phone),
            ],
          ),
          const SizedBox(height: 14),
          _field('Email (optional)', 'email', keyboard: TextInputType.emailAddress),
        ],
      ),
    );
  }

  Widget _taxCard(BuildContext context, BusinessSettings draft) {
    final gstin = _t('gstin').toUpperCase();
    Widget? gstinNote;
    if (gstin.isNotEmpty) {
      gstinNote = Upi.isValidGstin(gstin)
          ? ValidationNote(ok: true, text: 'Valid format · state code ${gstin.substring(0, 2)}')
          : const ValidationNote(
              ok: false,
              text: 'Format: 2 digits, 5 letters, 4 digits, letter, digit/letter, Z, digit/letter',
            );
    }
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Tax & invoice'),
          FieldRow(
            children: [
              _field('GSTIN', 'gstin', caps: TextCapitalization.characters, maxLength: 15, helper: gstinNote),
              _field(
                'FSSAI licence no. (optional)',
                'fssai',
                formatters: _digits,
                keyboard: TextInputType.number,
                maxLength: 14,
              ),
            ],
          ),
          const SizedBox(height: 14),
          FieldRow(
            children: [
              _field(
                'Invoice number prefix',
                'prefix',
                maxLength: 20,
                helper: Text('Next invoice: ${draft.invoiceNumber()}', style: CbText.muted(context, 12.5)),
              ),
              _field('Next invoice number', 'next', formatters: _digits, keyboard: TextInputType.number),
            ],
          ),
          const SizedBox(height: 14),
          _field('Footer message', 'footer'),
          const SizedBox(height: 14),
          FieldRow(
            children: [
              _field(
                'GST on food & drinks',
                'gst_food',
                formatters: _decimal,
                keyboard: TextInputType.number,
                suffix: '%',
              ),
              _field(
                'GST on pool table time',
                'gst_pool',
                formatters: _decimal,
                keyboard: TextInputType.number,
                suffix: '%',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Prices on the menu exclude GST. Confirm the rates for your business with your CA.',
            style: CbText.muted(context, 12.5),
          ),
        ],
      ),
    );
  }

  Widget _upiCard(BuildContext context) {
    final cb = context.cb;
    final id = _t('upi_id');
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('UPI payments', bottom: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Print UPI QR on invoices'),
            value: _showQr,
            onChanged: (v) => setState(() {
              _showQr = v ?? true;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 8),
          FieldRow(
            children: [
              _field(
                'UPI ID (VPA)',
                'upi_id',
                keyboard: TextInputType.emailAddress,
                helper: id.isEmpty
                    ? null
                    : ValidationNote(
                        ok: Upi.isValidUpiId(id),
                        text: Upi.isValidUpiId(id) ? 'Looks like a valid UPI ID' : 'Use the format name@bank',
                      ),
              ),
              _field('Payee name shown in UPI apps', 'upi_payee', caps: TextCapitalization.words),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cb.soft, borderRadius: BorderRadius.circular(10)),
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: cb.muted, fontSize: 13.5, height: 1.5),
                children: [
                  const TextSpan(text: 'Each invoice gets its own QR with the '),
                  TextSpan(
                    text: 'exact bill amount',
                    style: TextStyle(fontWeight: FontWeight.w700, color: cb.ink),
                  ),
                  const TextSpan(
                    text:
                        ' and invoice number filled in, so the customer only has to scan and confirm. No payment gateway needed. '
                        'The QR prints for UPI and Split payments.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _poolCard(BuildContext context) {
    final cb = context.cb;
    Widget select(String label, int value, List<int> options, ValueChanged<int> onChanged, String Function(int) text) =>
        FieldLabel(
          label,
          child: DropdownButtonFormField<int>(
            value: options.contains(value) ? value : null,
            isExpanded: true,
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(text(o)))],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                onChanged(v);
                _dirty = true;
              });
            },
          ),
        );

    Widget timeButton(String label, String value, bool start) => FieldLabel(
      label,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(double.infinity, 46),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, fontFamily: 'Inter'),
        ),
        onPressed: _happy ? () => _pickTime(start) : null,
        child: Text(Fmt.clock(value)),
      ),
    );

    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Pool table rates'),
          FieldRow(
            children: [
              _field('Rate per hour', 'pool_rate', formatters: _decimal, keyboard: TextInputType.number, prefix: '₹ '),
              select(
                'Bill in blocks of',
                _block,
                const [1, 5, 10, 15, 30, 60],
                (v) => _block = v,
                (v) => v == 1 ? 'Exact minutes' : '$v minutes',
              ),
            ],
          ),
          const SizedBox(height: 14),
          FieldRow(
            children: [
              select(
                'Minimum charge',
                _minimum,
                const [0, 15, 30, 45, 60],
                (v) => _minimum = v,
                (v) => v == 0 ? 'No minimum' : '$v minutes',
              ),
              _field(
                'Running cost / hour',
                'pool_cost',
                formatters: _decimal,
                keyboard: TextInputType.number,
                prefix: '₹ ',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Running cost (electricity, cloth, cues) is used to work out pool table profit.',
            style: CbText.muted(context, 12.5),
          ),
          const SizedBox(height: 20),
          Text('Booked time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: cb.ink)),
          const SizedBox(height: 4),
          Text(
            'When a timer starts, staff pick how long the table is booked for, or open play. '
            'The timer counts down and the table is flagged when time is up. It keeps running until stopped, '
            'and the alert sounds again while it runs over.',
            style: CbText.muted(context, 12.5),
          ),
          const SizedBox(height: 12),
          FieldRow(
            breakpoint: 560,
            children: [
              select(
                'Booking picked first',
                _defaultBooking,
                const [0, 30, 60, 90, 120],
                (v) => _defaultBooking = v,
                (v) => v == 0 ? 'Open play' : Billing.duration(v),
              ),
              select(
                'Warn before end',
                _warn,
                const [0, 5, 10, 15],
                (v) => _warn = v,
                (v) => v == 0 ? 'No warning' : '$v minutes',
              ),
            ],
          ),
          const SizedBox(height: 14),
          FieldRow(
            breakpoint: 560,
            children: [
              select(
                'Free overtime',
                _grace,
                const [0, 2, 5, 10, 15],
                (v) => _grace = v,
                (v) => v == 0 ? 'None' : '$v minutes',
              ),
              select(
                'Repeat time-up alert',
                _repeat,
                const [0, 2, 5, 10, 15],
                (v) => _repeat = v,
                (v) => v == 0 ? 'Once only' : 'Every $v minutes',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Checkbox(
                value: _bookedIsMinimum,
                onChanged: (v) => setState(() {
                  _bookedIsMinimum = v ?? true;
                  _dirty = true;
                }),
              ),
              const Expanded(child: Text('Charge the full booking even if the table finishes early')),
            ],
          ),
          Text(
            'Overtime past the free minutes is billed in ${_block == 1 ? 'exact minutes' : '$_block-minute blocks'} '
            'on top of the booking.',
            style: CbText.muted(context, 12.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cb.greenSoft, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _happy,
                      onChanged: (v) => setState(() {
                        _happy = v ?? false;
                        _dirty = true;
                      }),
                    ),
                    const Text('Happy-hour rate', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                if (_happy) ...[
                  const SizedBox(height: 8),
                  FieldRow(
                    breakpoint: 560,
                    children: [
                      _field(
                        'Rate per hour',
                        'happy_rate',
                        formatters: _decimal,
                        keyboard: TextInputType.number,
                        prefix: '₹ ',
                      ),
                      timeButton('From', _happyStart, true),
                      timeButton('To', _happyEnd, false),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Applies when a timer starts inside this window. The rate is fixed for the whole game.',
                    style: CbText.muted(context, 12.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _backupCard(BuildContext context, AppStore store) {
    final cb = context.cb;
    final f = File(store.dbPath);
    final mb = f.existsSync() ? f.lengthSync() / (1024 * 1024) : 0;
    final last = store.settings.lastBackupAt;
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Data & backup'),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: cb.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Works offline. Sales are saved on this device.')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${Fmt.count(store.invoiceCount)} invoices · ${mb.toStringAsFixed(1)} MB · '
            '${last == null ? 'no backup yet' : 'last backup ${Fmt.relativeDay(last)}'}',
            style: CbText.muted(context, 13.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _backup,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download backup'),
              ),
              OutlinedButton(onPressed: _busy ? null : _restore, child: const Text('Restore')),
              OutlinedButton(onPressed: _busy ? null : _sample, child: const Text('Load sample sales')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Keep a copy on a USB drive, or connect Google Drive below. To restore a file, tap Restore and choose it: '
            'it replaces everything on this device.',
            style: CbText.muted(context, 12.5).copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.draft});

  final BusinessSettings draft;

  @override
  Widget build(BuildContext context) {
    final receipt = Checkout.sample(draft);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Receipt preview', style: CbText.cardTitle(context))),
            Text('Updates as you type', style: CbText.muted(context)),
          ],
        ),
        const SizedBox(height: 12),
        ReceiptTray(child: ReceiptView(data: receipt, compact: true)),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('What the QR contains', style: CbText.label(context)),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                receipt.upiUri ?? 'No QR: add a valid UPI ID and turn on "Print UPI QR on invoices".',
                style: CbText.num(context, size: 12.5, color: context.cb.muted),
              ),
              const SizedBox(height: 6),
              Text(
                'UPI apps read the payee, the exact amount and the bill number from it.',
                style: CbText.muted(context, 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onDiscard, required this.onSave});

  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Container(
      decoration: BoxDecoration(
        color: cb.card,
        border: Border(top: BorderSide(color: cb.line)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'You have unsaved changes.',
                style: TextStyle(color: cb.ink, fontWeight: FontWeight.w500),
              ),
            ),
            OutlinedButton(onPressed: onDiscard, child: const Text('Discard')),
            const SizedBox(width: 10),
            FilledButton(onPressed: onSave, child: const Text('Save changes')),
          ],
        ),
      ),
    );
  }
}

/// Google Drive: connect, back up now, daily backup switch, restore from Drive.
class _DriveCard extends StatelessWidget {
  const _DriveCard({required this.onRestored});

  final VoidCallback onRestored;

  static String _size(int bytes) =>
      bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

  Future<void> _guard(BuildContext context, Future<void> Function() task, {String? done}) async {
    try {
      await task();
      if (done != null && context.mounted) toast(context, done);
    } catch (e) {
      if (context.mounted) toast(context, DriveSync.friendlyError(e), error: true);
    }
  }

  Future<void> _restore(BuildContext context, DriveSync drive) async {
    final picked = await showDialog<DriveFile>(
      context: context,
      builder: (_) => _DriveBackupsDialog(drive: drive),
    );
    if (picked == null || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Restore this backup?',
      message:
          'Backup from ${Fmt.date(picked.createdTime)}, ${Fmt.time(picked.createdTime)}. All sales, menu, tables and settings '
          'on this device are replaced by it. Make a fresh backup first if you may need today\'s data.',
      confirm: 'Restore',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await _guard(context, () async {
      await drive.restoreFrom(picked);
      onRestored();
    }, done: 'Backup restored from Google Drive.');
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveSync>();
    final settings = context.watch<AppStore>().settings;
    final cb = context.cb;
    final last = settings.driveLastBackupAt;

    final children = <Widget>[
      CardHeader('Google Drive', trailing: drive.connected ? const CbBadge('Connected', tone: Tone.green) : null),
    ];

    if (!drive.available) {
      children.add(
        Text(
          'Google Drive is not set up in this build. See "Google Drive backups" in the README to add your Google sign-in keys.',
          style: CbText.muted(context, 13.5).copyWith(height: 1.45),
        ),
      );
    } else if (!drive.connected) {
      children.addAll([
        Text(
          'Connect a Google account and CueBill uploads a backup to a "CueBill backups" folder in its Drive once a day, '
          'and whenever you tap Back up now. CueBill can only see the files it creates.',
          style: CbText.muted(context, 13.5).copyWith(height: 1.45),
        ),
        if (drive.lastError != null) ...[const SizedBox(height: 10), ValidationNote(ok: false, text: drive.lastError!)],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: drive.busy ? null : () => _guard(context, drive.connect, done: 'Google Drive connected.'),
            icon: const Icon(Icons.add_to_drive_outlined, size: 18),
            label: Text(drive.busy ? 'Waiting for Google…' : 'Connect Google Drive'),
          ),
        ),
      ]);
    } else {
      children.addAll([
        Text('Connected as ${drive.email}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          drive.busy
              ? 'Working with Google Drive…'
              : last == null
              ? 'No Drive backup yet.'
              : 'Last Drive backup ${Fmt.relativeDay(last)}. The newest ${DriveSync.keep} are kept.',
          style: CbText.muted(context, 13.5),
        ),
        if (drive.lastError != null) ...[
          const SizedBox(height: 8),
          ValidationNote(ok: false, text: 'Last try failed: ${drive.lastError}'),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Back up daily'),
          subtitle: const Text('Once a day while CueBill is open and online'),
          value: settings.driveAutoBackup,
          onChanged: (v) => drive.setAutoBackup(v),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: drive.busy
                  ? null
                  : () => _guard(context, drive.backupNow, done: 'Backup uploaded to Google Drive.'),
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Back up to Drive now'),
            ),
            OutlinedButton(
              onPressed: drive.busy ? null : () => _restore(context, drive),
              child: const Text('Restore from Drive…'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: cb.red),
              onPressed: drive.busy
                  ? null
                  : () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Disconnect Google Drive?',
                        message: 'Daily backups stop. Backups already in Drive stay there.',
                        confirm: 'Disconnect',
                      );
                      if (ok && context.mounted) {
                        await _guard(context, drive.disconnect, done: 'Google Drive disconnected.');
                      }
                    },
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ]);
    }

    return CbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _DriveBackupsDialog extends StatefulWidget {
  const _DriveBackupsDialog({required this.drive});

  final DriveSync drive;

  @override
  State<_DriveBackupsDialog> createState() => _DriveBackupsDialogState();
}

class _DriveBackupsDialogState extends State<_DriveBackupsDialog> {
  late final Future<List<DriveFile>> _files = widget.drive.listBackups();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Restore from Google Drive', style: CbText.cardTitle(context)),
      content: SizedBox(
        width: 440,
        height: 360,
        child: FutureBuilder<List<DriveFile>>(
          future: _files,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text(DriveSync.friendlyError(snap.error!), textAlign: TextAlign.center));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final files = snap.data!;
            if (files.isEmpty) {
              return Center(child: Text('No backups in Google Drive yet.', style: CbText.muted(context, 14)));
            }
            return ListView.separated(
              itemCount: files.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final f = files[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.backup_outlined),
                  title: Text('${Fmt.date(f.createdTime)}, ${Fmt.time(f.createdTime)}'),
                  subtitle: Text('${_DriveCard._size(f.size)}${i == 0 ? ' · newest' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, f),
                );
              },
            );
          },
        ),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
