import 'dart:async';

import 'package:flutter/material.dart';

import '../services/analytics.dart';
import 'theme.dart';

/// Ticks once a second for live timers.
class Clock {
  Clock._();

  static final ValueNotifier<DateTime> now = ValueNotifier(DateTime.now());
  static Timer? _timer;

  static void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => now.value = DateTime.now());
  }
}

class Ticking extends StatelessWidget {
  const Ticking({super.key, required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DateTime>(valueListenable: Clock.now, builder: (c, now, _) => builder(c, now));
}

class CbCard extends StatelessWidget {
  const CbCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color, this.border});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Container(
      decoration: BoxDecoration(
        color: color ?? cb.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? cb.line),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Card heading with an optional trailing widget (link, note, filter).
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {super.key, this.trailing, this.bottom = 14});

  final String title;
  final Widget? trailing;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        children: [
          Expanded(child: Text(title, style: CbText.cardTitle(context))),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: trailing!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Page title, subtitle and action buttons. Actions wrap below the title on narrow screens.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.above});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? above;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (above != null) above!,
        Text(title, style: CbText.pageTitle(context)),
        if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: CbText.muted(context, 14))],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(
        builder: (context, c) {
          if (actions.isEmpty) return titleBlock;
          if (c.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 16),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
            ],
          );
        },
      ),
    );
  }
}

/// Pill chip: category filter, discount presets, date presets. On = dark fill.
class CbChip extends StatelessWidget {
  const CbChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBg = isDark ? cb.ink : cb.dark;
    final onFg = isDark ? cb.dark : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? onBg : cb.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? onBg : cb.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? onFg : cb.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Payment method button. On = green border + soft green.
class PayButton extends StatelessWidget {
  const PayButton({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? cb.greenSoft : cb.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? cb.green : cb.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, color: selected ? cb.greenText : cb.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-option segmented toggle (80 mm / A4).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? cb.soft : const Color(0xFFE9ECE8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in options.entries)
              Semantics(
                button: true,
                selected: e.key == value,
                child: Material(
                  color: e.key == value ? cb.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onChanged(e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500,
                          color: e.key == value ? cb.ink : cb.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum Tone { green, amber, red, neutral }

class CbBadge extends StatelessWidget {
  const CbBadge(this.text, {super.key, this.tone = Tone.neutral});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final (bg, fg) = switch (tone) {
      Tone.green => (cb.greenSoft, cb.greenText),
      Tone.amber => (cb.amberSoft, cb.amber),
      Tone.red => (cb.redSoft, cb.red),
      Tone.neutral => (Theme.of(context).brightness == Brightness.dark ? cb.soft : const Color(0xFFECEFEB), cb.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        softWrap: false,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, fontFeatures: tabular),
      ),
    );
  }
}

Tone ratingTone(Rating r) => switch (r) {
  Rating.star => Tone.green,
  Rating.steady => Tone.neutral,
  Rating.slow => Tone.amber,
  Rating.lossRisk => Tone.red,
};

/// Good ≥ 50%, mid 30–49%, bad below 30%.
Tone marginTone(double pct) => pct >= 50 ? Tone.green : (pct >= 30 ? Tone.amber : Tone.red);

Color toneColor(BuildContext context, Tone t) => switch (t) {
  Tone.green => context.cb.greenText,
  Tone.amber => context.cb.amber,
  Tone.red => context.cb.red,
  Tone.neutral => context.cb.muted,
};

/// Margin bar: width = margin %.
class MarginBar extends StatelessWidget {
  const MarginBar(this.percent, {super.key, this.width = 110});

  final double percent;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final color = switch (marginTone(percent)) {
      Tone.green => cb.green,
      Tone.amber => const Color(0xFFD08A2E),
      _ => cb.red,
    };
    return Semantics(
      label: 'Margin ${percent.toStringAsFixed(0)}%',
      child: Container(
        width: width,
        height: 6,
        decoration: BoxDecoration(color: cb.line, borderRadius: BorderRadius.circular(3)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (percent.clamp(0, 100)) / 100,
          child: Container(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
    );
  }
}

enum DotState { running, busy, free }

/// Green with a halo / amber / hollow grey ring. Always shown next to a text legend.
class StatusDot extends StatelessWidget {
  const StatusDot(this.state, {super.key, this.size = 10});

  final DotState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    return Container(
      width: size,
      height: size,
      decoration: switch (state) {
        DotState.running => BoxDecoration(
          color: cb.green,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: cb.green.withValues(alpha: 0.25), spreadRadius: 3)],
        ),
        DotState.busy => const BoxDecoration(color: Color(0xFFD08A2E), shape: BoxShape.circle),
        DotState.free => BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: cb.muted, width: 1.5),
        ),
      },
    );
  }
}

class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.label, this.color, this.dot});

  final String label;
  final Color? color;
  final DotState? dot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null)
          StatusDot(dot!, size: 9)
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        const SizedBox(width: 6),
        Text(label, style: CbText.muted(context)),
      ],
    );
  }
}

/// Change vs previous period: ▲ 12.4% (green) or ▼ 1.8 pts (red).
class DeltaPill extends StatelessWidget {
  const DeltaPill({super.key, required this.text, required this.up});

  final String text;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final fg = up ? cb.greenText : cb.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: up ? cb.greenSoft : cb.redSoft, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: fg),
          Text(
            text,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}

class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.delta, this.note, this.valueSize = 28});

  final String label;
  final String value;
  final Widget? delta;
  final String? note;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return CbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: CbText.muted(context)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: CbText.big(context, size: valueSize)),
          ),
          if (delta != null || note != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (delta != null) delta!,
                if (note != null) Text(note!, style: CbText.muted(context)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Lays children out in equal columns that wrap: [minWidth] decides how many fit.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minWidth = 220,
    this.spacing = 16,
    this.maxColumns = 6,
  });

  final List<Widget> children;
  final double minWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = ((c.maxWidth + spacing) / (minWidth + spacing)).floor().clamp(1, maxColumns);
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      },
    );
  }
}

class Col {
  const Col(this.label, {this.flex = 1, this.right = false, this.width});

  final String label;
  final int flex;
  final bool right;

  /// Fixed width instead of flex.
  final double? width;
}

/// Simple data table: uppercase header, row dividers, scrolls sideways below [minWidth].
class CbTable extends StatelessWidget {
  const CbTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 640,
    this.rowHeight = 52,
    this.onTapRow,
    this.empty,
  });

  final List<Col> columns;
  final List<List<Widget>> rows;
  final double minWidth;
  final double rowHeight;
  final void Function(int index)? onTapRow;
  final String? empty;

  Widget _cell(Col col, Widget child) {
    final aligned = Align(alignment: col.right ? Alignment.centerRight : Alignment.centerLeft, child: child);
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: aligned);
    return col.width != null ? SizedBox(width: col.width, child: padded) : Expanded(flex: col.flex, child: padded);
  }

  @override
  Widget build(BuildContext context) {
    final cb = context.cb;
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cb.line)),
          ),
          child: Row(
            children: [
              for (final c in columns) _cell(c, Text(c.label.toUpperCase(), style: CbText.th(context), maxLines: 2)),
            ],
          ),
        ),
        if (rows.isEmpty && empty != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(child: Text(empty!, style: CbText.muted(context, 14))),
          ),
        for (var i = 0; i < rows.length; i++)
          InkWell(
            onTap: onTapRow == null ? null : () => onTapRow!(i),
            child: Container(
              constraints: BoxConstraints(minHeight: rowHeight),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: cb.line)),
              ),
              child: Row(
                children: [
                  for (var c = 0; c < columns.length; c++)
                    _cell(columns[c], c < rows[i].length ? rows[i][c] : const SizedBox()),
                ],
              ),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= minWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: table),
        );
      },
    );
  }
}

/// Text cell with tabular figures.
class NumText extends StatelessWidget {
  const NumText(this.text, {super.key, this.bold = false, this.color, this.size = 14});

  final String text;
  final bool bold;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: CbText.num(context, size: size, weight: bold ? FontWeight.w700 : FontWeight.w400, color: color),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key, required this.child, this.helper});

  final String label;
  final Widget child;
  final Widget? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.cb.ink),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[const SizedBox(height: 6), helper!],
      ],
    );
  }
}

/// Two fields side by side on wide screens, stacked on narrow ones.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.children, this.breakpoint = 520});

  final List<Widget> children;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// ✓ Valid format / ✗ message, shown under a field.
class ValidationNote extends StatelessWidget {
  const ValidationNote({super.key, required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = ok ? context.cb.greenText : context.cb.red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.check : Icons.error_outline, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool danger = false,
}) async {
  final cb = context.cb;
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: CbText.cardTitle(c)),
      content: Text(message, style: TextStyle(color: cb.muted, fontSize: 14, height: 1.4)),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB42318) : null,
        width: MediaQuery.sizeOf(context).width > 700 ? 420 : null,
      ),
    );
}

/// Standard scrolling page body with design padding.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1440});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 600 ? 16.0 : 32.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, pad - 4, pad, pad + 8),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}
