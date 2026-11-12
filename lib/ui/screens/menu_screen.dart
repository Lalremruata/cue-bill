import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

final _money = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];

enum _MenuTab { items, categories, tables }

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  _MenuTab _tab = _MenuTab.items;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cb = context.cb;

    final addButton = switch (_tab) {
      _MenuTab.items => FilledButton.icon(
        onPressed: store.categories.isEmpty ? null : () => showMenuItemDialog(context),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add item'),
      ),
      _MenuTab.categories => FilledButton.icon(
        onPressed: () => _showCategoryDialog(context),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add category'),
      ),
      _MenuTab.tables => FilledButton.icon(
        onPressed: () => _showTableDialog(context),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add table'),
      ),
    };

    final tabs = Row(
      children: [
        for (final (t, label) in [
          (_MenuTab.items, 'Menu items'),
          (_MenuTab.categories, 'Categories'),
          (_MenuTab.tables, 'Tables'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CbChip(label: label, selected: _tab == t, onTap: () => setState(() => _tab = t)),
          ),
      ],
    );

    final main = switch (_tab) {
      _MenuTab.items => const _MenuItemsCard(),
      _MenuTab.categories => const _CategoriesCard(),
      _MenuTab.tables => const _TablesCard(),
    };

    return PageBody(
      children: [
        PageHeader(
          title: 'Menu, costs & table rates',
          subtitle: 'Enter what each item costs you. Margins and profit reports are worked out from it.',
          actions: [addButton],
        ),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final side = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RatesCard(cb: cb),
                const SizedBox(height: 16),
                const _GstCard(),
              ],
            );
            if (c.maxWidth >= 1100) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 13, child: main),
                  const SizedBox(width: 24),
                  Expanded(flex: 7, child: side),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [main, const SizedBox(height: 16), side],
            );
          },
        ),
      ],
    );
  }
}

class _MenuItemsCard extends StatelessWidget {
  const _MenuItemsCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.sortedMenu;
    final cats = store.categoryById;
    final active = items.where((m) => m.isActive && m.price > 0).toList();
    final avg = active.isEmpty ? 0.0 : active.fold(0.0, (s, m) => s + m.marginPercent) / active.length;

    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            'Menu items',
            bottom: 6,
            trailing: Text('Average margin ${avg.toStringAsFixed(0)}%', style: CbText.muted(context)),
          ),
          CbTable(
            minWidth: 760,
            rowHeight: 64,
            empty: store.categories.isEmpty ? 'Add a category first, then add items.' : 'No items yet. Tap Add item.',
            columns: const [
              Col('Item', flex: 5),
              Col('Category', flex: 3),
              Col('Your cost (₹)', width: 116, right: true),
              Col('Selling price (₹)', width: 124, right: true),
              Col('Profit / unit', flex: 2, right: true),
              Col('Margin', flex: 2, right: true),
              Col('On menu', width: 84, right: true),
            ],
            rows: [for (final m in items) _menuRow(context, m, cats[m.categoryId])],
          ),
        ],
      ),
    );
  }

  List<Widget> _menuRow(BuildContext context, MenuItem m, MenuCategory? c) {
    final store = context.read<AppStore>();
    final cb = context.cb;
    return [
      InkWell(
        onTap: () => showMenuItemDialog(context, item: m),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  m.name,
                  style: TextStyle(fontWeight: FontWeight.w500, color: m.isActive ? cb.ink : cb.muted),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, size: 14, color: cb.muted, semanticLabel: 'Edit ${m.name}'),
            ],
          ),
        ),
      ),
      Text(c?.name ?? '–', style: CbText.muted(context, 14)),
      _InlineMoney(
        key: ValueKey('cost-${m.id}-${m.costPrice}'),
        value: m.costPrice,
        label: 'Cost of ${m.name}',
        onCommit: (v) => store.saveMenuItem(MenuItem.fromRow(m.toRow())..costPrice = v),
      ),
      _InlineMoney(
        key: ValueKey('price-${m.id}-${m.price}'),
        value: m.price,
        label: 'Price of ${m.name}',
        onCommit: (v) => store.saveMenuItem(MenuItem.fromRow(m.toRow())..price = v),
      ),
      NumText(Fmt.inr(m.profit), bold: true),
      CbBadge(Fmt.percent(m.marginPercent, 0), tone: marginTone(m.marginPercent)),
      Switch(value: m.isActive, onChanged: (v) => store.saveMenuItem(MenuItem.fromRow(m.toRow())..isActive = v)),
    ];
  }
}

/// Number field that saves when you press Enter or leave it.
class _InlineMoney extends StatefulWidget {
  const _InlineMoney({super.key, required this.value, required this.label, required this.onCommit});

  final double value;
  final String label;
  final ValueChanged<double> onCommit;

  @override
  State<_InlineMoney> createState() => _InlineMoneyState();
}

class _InlineMoneyState extends State<_InlineMoney> {
  late final TextEditingController _c = TextEditingController(text: Fmt.trim(widget.value));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    final v = double.tryParse(_c.text.trim());
    if (v == null || v < 0) {
      _c.text = Fmt.trim(widget.value);
      return;
    }
    if ((v - widget.value).abs() > 0.001) widget.onCommit(v);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: SizedBox(
        width: 92,
        child: TextField(
          controller: _c,
          focusNode: _focus,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _money,
          style: CbText.num(context),
          decoration: const InputDecoration(hintText: '0'),
          onSubmitted: (_) => _commit(),
        ),
      ),
    );
  }
}

Future<void> showMenuItemDialog(BuildContext context, {MenuItem? item}) {
  return showDialog(
    context: context,
    builder: (_) => _MenuItemDialog(item: item),
  );
}

class _MenuItemDialog extends StatefulWidget {
  const _MenuItemDialog({this.item});

  final MenuItem? item;

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _cost = TextEditingController(text: widget.item == null ? '' : Fmt.trim(widget.item!.costPrice));
  late final _price = TextEditingController(text: widget.item == null ? '' : Fmt.trim(widget.item!.price));
  late int? _categoryId = widget.item?.categoryId;
  late bool _active = widget.item?.isActive ?? true;

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    _categoryId ??= store.categories.firstOrNull?.id;
    final editing = widget.item != null;
    return AlertDialog(
      title: Text(editing ? 'Edit item' : 'Add item', style: CbText.cardTitle(context)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldLabel(
                'Name',
                child: TextFormField(
                  controller: _name,
                  autofocus: !editing,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
              ),
              const SizedBox(height: 14),
              FieldLabel(
                'Category',
                child: DropdownButtonFormField<int>(
                  value: _categoryId,
                  items: [for (final c in store.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ),
              const SizedBox(height: 14),
              FieldRow(
                breakpoint: 300,
                children: [
                  FieldLabel(
                    'Your cost (₹)',
                    child: TextFormField(
                      controller: _cost,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: _money,
                    ),
                  ),
                  FieldLabel(
                    'Selling price (₹)',
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: _money,
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a price' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('On menu'),
                subtitle: const Text('Off hides it from Tables & Orders'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              Text('Prices exclude GST. GST is added on the bill.', style: CbText.muted(context, 12.5)),
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.cb.red),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Delete ${widget.item!.name}?',
                message:
                    'It is removed from the menu and from any open order. Past invoices keep the item. '
                    'To hide it for now, turn off "On menu" instead.',
                confirm: 'Delete',
                danger: true,
              );
              if (!ok || !context.mounted) return;
              await store.deleteMenuItem(widget.item!);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            if (!_form.currentState!.validate() || _categoryId == null) return;
            final item = MenuItem(
              id: widget.item?.id,
              categoryId: _categoryId!,
              name: _name.text.trim(),
              costPrice: double.tryParse(_cost.text) ?? 0,
              price: double.parse(_price.text),
              isActive: _active,
            );
            await store.saveMenuItem(item);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Categories', bottom: 6),
          CbTable(
            minWidth: 480,
            empty: 'No categories yet.',
            onTapRow: (i) => _showCategoryDialog(context, store.categories[i]),
            columns: const [
              Col('Name', flex: 4),
              Col('Reports as', flex: 3),
              Col('Order', flex: 1, right: true),
              Col('Items', flex: 1, right: true),
            ],
            rows: [
              for (final c in store.categories)
                [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  CbBadge(c.typeLabel),
                  NumText('${c.sort}'),
                  NumText('${store.menu.where((m) => m.categoryId == c.id).length}'),
                ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Each category reports as Food, Drinks or Snacks on the dashboard and in reports. Tap a row to edit it.',
            style: CbText.muted(context),
          ),
        ],
      ),
    );
  }
}

Future<void> _showCategoryDialog(BuildContext context, [MenuCategory? category]) async {
  final store = context.read<AppStore>();
  final name = TextEditingController(text: category?.name);
  final sort = TextEditingController(text: '${category?.sort ?? store.categories.length}');
  var type = category?.type ?? 'food';
  final form = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(category == null ? 'Add category' : 'Edit category', style: CbText.cardTitle(c)),
        content: SizedBox(
          width: 380,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FieldLabel(
                  'Name',
                  child: TextFormField(
                    controller: name,
                    autofocus: category == null,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                ),
                const SizedBox(height: 14),
                FieldRow(
                  breakpoint: 300,
                  children: [
                    FieldLabel(
                      'Reports as',
                      child: DropdownButtonFormField<String>(
                        value: type,
                        items: [
                          for (final e in categoryTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => type = v ?? 'food'),
                      ),
                    ),
                    FieldLabel(
                      'Order',
                      child: TextFormField(
                        controller: sort,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (category != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: c.cb.red),
              onPressed: () async {
                final count = store.menu.where((m) => m.categoryId == category.id).length;
                final ok = await confirmDialog(
                  c,
                  title: 'Delete ${category.name}?',
                  message: count == 0
                      ? 'This category has no items.'
                      : 'This also deletes its $count menu item${count == 1 ? '' : 's'}. Past invoices keep them.',
                  confirm: 'Delete',
                  danger: true,
                );
                if (!ok) return;
                await store.deleteCategory(category);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Delete'),
            ),
          OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final cat = category ?? MenuCategory(name: '');
              cat
                ..name = name.text.trim()
                ..type = type
                ..sort = int.tryParse(sort.text) ?? 0;
              await store.saveCategory(cat);
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  sort.dispose();
}

class _TablesCard extends StatelessWidget {
  const _TablesCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final tables = store.tables;
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Tables', bottom: 6),
          CbTable(
            minWidth: 560,
            empty: 'No tables yet.',
            onTapRow: (i) => _showTableDialog(context, tables[i]),
            columns: const [
              Col('Name', flex: 4),
              Col('Type', flex: 3),
              Col('Hourly rate', flex: 3, right: true),
              Col('Order', flex: 1, right: true),
              Col('Status', flex: 2, right: true),
            ],
            rows: [
              for (final t in tables)
                [
                  Text(t.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(t.typeLabel, style: CbText.muted(context, 14)),
                  NumText(!t.isPool ? '–' : (t.hourlyRate == null ? 'Default' : '${Fmt.inr(t.hourlyRate!)}/hr')),
                  NumText('${t.sort}'),
                  CbBadge(t.isActive ? 'Active' : 'Hidden', tone: t.isActive ? Tone.green : Tone.neutral),
                ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A pool table can have its own hourly rate; otherwise the default rate from Business settings is used.',
            style: CbText.muted(context),
          ),
        ],
      ),
    );
  }
}

Future<void> _showTableDialog(BuildContext context, [RestaurantTable? table]) async {
  final store = context.read<AppStore>();
  final name = TextEditingController(text: table?.name);
  final rate = TextEditingController(text: table?.hourlyRate == null ? '' : Fmt.trim(table!.hourlyRate!));
  final sort = TextEditingController(text: '${table?.sort ?? store.tables.length}');
  var type = table?.type ?? 'dining';
  var active = table?.isActive ?? true;
  final form = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(table == null ? 'Add table' : 'Edit table', style: CbText.cardTitle(c)),
        content: SizedBox(
          width: 400,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FieldLabel(
                  'Name',
                  child: TextFormField(
                    controller: name,
                    autofocus: table == null,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                ),
                const SizedBox(height: 14),
                FieldRow(
                  breakpoint: 300,
                  children: [
                    FieldLabel(
                      'Type',
                      child: DropdownButtonFormField<String>(
                        value: type,
                        items: [
                          for (final e in tableTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => type = v ?? 'dining'),
                      ),
                    ),
                    FieldLabel(
                      'Order',
                      child: TextFormField(
                        controller: sort,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ),
                  ],
                ),
                if (type == 'pool') ...[
                  const SizedBox(height: 14),
                  FieldLabel(
                    'Own hourly rate (₹, optional)',
                    helper: Text(
                      'Leave empty to use ${Fmt.inr(store.settings.poolRatePerHour)}/hr from Business settings.',
                      style: CbText.muted(c, 12.5),
                    ),
                    child: TextFormField(
                      controller: rate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: _money,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Hidden tables do not show on Tables & Orders'),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (table != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: c.cb.red),
              onPressed: () async {
                if (store.sessionFor(table) != null) {
                  toast(c, '${table.name} has an open order. Check it out or clear it first.', error: true);
                  return;
                }
                final ok = await confirmDialog(
                  c,
                  title: 'Delete ${table.name}?',
                  message: 'Past invoices keep the table name. To hide it for now, turn off "Active" instead.',
                  confirm: 'Delete',
                  danger: true,
                );
                if (!ok) return;
                await store.deleteTable(table);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Delete'),
            ),
          OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final t = table ?? RestaurantTable(name: '');
              final r = double.tryParse(rate.text.trim());
              t
                ..name = name.text.trim()
                ..type = type
                ..hourlyRate = type == 'pool' && r != null && r > 0 ? r : null
                ..sort = int.tryParse(sort.text) ?? 0
                ..isActive = active;
              await store.saveTable(t);
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  rate.dispose();
  sort.dispose();
}

class _RatesCard extends StatelessWidget {
  const _RatesCard({required this.cb});

  final CbColors cb;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().settings;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: CbText.muted(context, 14))),
          NumText(value, bold: true),
        ],
      ),
    );
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Pool table rates', bottom: 8),
          row('Rate per hour', Fmt.inr(s.poolRatePerHour)),
          row('Bill in blocks of', '${s.billingBlockMinutes} minutes'),
          row('Minimum charge', '${s.minimumMinutes} minutes'),
          row('Running cost / hour', Fmt.inr(s.poolCostPerHour)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cb.greenSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Icon(
                  s.happyHourEnabled ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: cb.greenText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Happy-hour rate', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        s.happyHourEnabled
                            ? '${Fmt.inr(s.happyHourRate)}/hr · ${Fmt.clock(s.happyHourStart)} – ${Fmt.clock(s.happyHourEnd)}'
                            : 'Off',
                        style: CbText.muted(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Running cost (electricity, cloth, cues) is used to work out pool table profit.',
            style: CbText.muted(context, 12.5),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => context.read<Nav>().go(Section.settings),
              child: const Text('Change in Business settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GstCard extends StatelessWidget {
  const _GstCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().settings;
    final cb = context.cb;
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('GST on invoices', bottom: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cb.line)),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('Food & drinks')),
                NumText(Fmt.percent(s.gstFoodRate, 2), bold: true),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cb.line)),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('Pool table time')),
                NumText(Fmt.percent(s.gstPoolRate, 2), bold: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Editable in Business settings. Confirm the rates for your business with your CA.',
            style: CbText.muted(context, 12.5),
          ),
        ],
      ),
    );
  }
}
