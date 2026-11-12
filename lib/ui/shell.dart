import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../services/drive_sync.dart';
import 'screens/checkout_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';

enum Section { dashboard, pos, invoices, reports, menu, settings }

extension SectionInfo on Section {
  String get label => switch (this) {
    Section.dashboard => 'Dashboard',
    Section.pos => 'Tables & Orders',
    Section.invoices => 'Invoices',
    Section.reports => 'Reports',
    Section.menu => 'Menu & Tables',
    Section.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    Section.dashboard => Icons.space_dashboard_outlined,
    Section.pos => Icons.table_restaurant_outlined,
    Section.invoices => Icons.receipt_long_outlined,
    Section.reports => Icons.bar_chart_outlined,
    Section.menu => Icons.restaurant_menu_outlined,
    Section.settings => Icons.settings_outlined,
  };
}

/// Which screen is showing, the selected table on Tables & Orders, and an open checkout.
class Nav extends ChangeNotifier {
  Section section = Section.pos;
  int? selectedTableId;
  int? checkoutTableId;

  void go(Section s) {
    section = s;
    if (s != Section.pos) checkoutTableId = null;
    notifyListeners();
  }

  void selectTable(int? id) {
    selectedTableId = id;
    notifyListeners();
  }

  void openCheckout(int tableId) {
    section = Section.pos;
    selectedTableId = tableId;
    checkoutTableId = tableId;
    notifyListeners();
  }

  void closeCheckout() {
    checkoutTableId = null;
    notifyListeners();
  }
}

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.light);

  void toggle(Brightness current) => value = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<Nav>();
    final wide = MediaQuery.sizeOf(context).width >= 1024;

    final Widget page = switch (nav.section) {
      Section.dashboard => const DashboardScreen(),
      Section.pos =>
        nav.checkoutTableId != null
            ? CheckoutScreen(key: ValueKey('checkout-${nav.checkoutTableId}'), tableId: nav.checkoutTableId!)
            : const PosScreen(),
      Section.invoices => const InvoicesScreen(),
      Section.reports => const ReportsScreen(),
      Section.menu => const MenuScreen(),
      Section.settings => const SettingsScreen(),
    };

    // Booking alerts sit above both layouts, so they keep their state when the window is resized.
    return BookingAlerts(
      child: wide
          ? Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 232, child: Sidebar()),
                  Expanded(child: page),
                ],
              ),
            )
          : Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: Row(
                  children: [
                    const _BallLogo(size: 28),
                    const SizedBox(width: 10),
                    Text(nav.section.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                  ],
                ),
              ),
              drawer: const Drawer(
                width: 260,
                backgroundColor: Color(0xFF14201A),
                child: SafeArea(child: Sidebar()),
              ),
              body: SafeArea(top: false, child: page),
            ),
    );
  }
}

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<Nav>();
    final store = context.watch<AppStore>();
    final theme = context.read<ThemeController>();
    final brightness = Theme.of(context).brightness;
    final backup = store.settings.lastBackupAt;
    final drive = context.watch<DriveSync>();
    final driveLast = store.settings.driveLastBackupAt;

    return Container(
      color: const Color(0xFF14201A),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const _BallLogo(size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CueBill',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        store.settings.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFA3B0A9), fontSize: 11.5, letterSpacing: 0.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          for (final s in Section.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _NavItem(
                section: s,
                selected: nav.section == s,
                onTap: () {
                  nav.go(s);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.of(context).pop();
                },
              ),
            ),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFCFD8D3),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: () => theme.toggle(brightness),
            icon: Icon(brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 18),
            label: Text(brightness == Brightness.dark ? 'Light theme' : 'Dark theme'),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1E2C25), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Saved locally',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'All sales stored on this device.\n'
                  '${backup == null ? 'No backup yet.' : 'Last backup ${Fmt.relativeDay(backup)}.'}'
                  '${drive.connected ? '\nGoogle Drive: ${driveLast == null ? 'not backed up yet' : 'backed up ${Fmt.relativeDay(driveLast)}'}.' : ''}',
                  style: const TextStyle(color: Color(0xFFA3B0A9), fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, required this.onTap});

  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? context.cb.green : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(section.icon, size: 19, color: selected ? Colors.white : const Color(0xFFCFD8D3)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFDDE4E0),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pool "8 ball" mark.
class _BallLogo extends StatelessWidget {
  const _BallLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Color(0xFF0E6B4A), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.5,
        height: size * 0.5,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          '8',
          style: TextStyle(
            fontSize: size * 0.3,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF14201A),
            height: 1,
          ),
        ),
      ),
    );
  }
}
