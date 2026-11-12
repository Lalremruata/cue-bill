import 'dart:convert';
import 'dart:math' as math;

import '../core/billing.dart';
import 'models.dart';
import 'store.dart';

/// Optional: fills the last 45 days with sample sales so the dashboard and
/// reports have something to show. Port of DemoSalesSeeder.php.
class DemoSales {
  DemoSales._();

  static Future<int> generate(AppStore store, {int days = 45, int seed = 42}) async {
    final rnd = math.Random(seed);
    int rand(int min, int max) => min + rnd.nextInt(max - min + 1);
    T pick<T>(List<T> list) => list[rnd.nextInt(list.length)];
    K weighted<K>(Map<K, int> weights) {
      var r = rand(1, weights.values.fold(0, (a, b) => a + b));
      for (final e in weights.entries) {
        r -= e.value;
        if (r <= 0) return e.key;
      }
      return weights.keys.first;
    }

    final settings = store.settings;
    final cats = store.categoryById;
    final items = store.menu.where((m) => m.isActive).toList();
    if (items.isEmpty) return 0;
    const unpopular = {'Grilled fish platter', 'Veg club sandwich', 'Hot chocolate'};
    final popular = items.where((m) => !unpopular.contains(m.name)).toList();
    final pool = store.tables.where((t) => t.isPool).toList();
    final dining = store.tables.where((t) => !t.isPool).toList();
    final now = DateTime.now();
    final business = jsonEncode(settings.snapshot().toJson());

    var n = settings.nextInvoiceNumber;
    var created = 0;

    await store.db.transaction((txn) async {
      // Start after the highest number already used.
      while (true) {
        final used = await txn.rawQuery('SELECT 1 FROM invoices WHERE number = ?', [settings.invoiceNumber(n)]);
        if (used.isEmpty) break;
        n++;
      }

      for (var day = days - 1; day >= 0; day--) {
        final date = DateTime(now.year, now.month, now.day - day);
        final weekend = date.weekday >= DateTime.friday;
        final bills = rand(14, 22) + (weekend ? 10 : 0);

        for (var b = 0; b < bills; b++) {
          final isPool = pool.isNotEmpty && rand(1, 100) <= 40;
          if (!isPool && dining.isEmpty) continue;
          final hour = isPool
              ? weighted({12: 1, 13: 1, 14: 2, 15: 2, 16: 4, 17: 6, 18: 8, 19: 10, 20: 10, 21: 8, 22: 5})
              : weighted({12: 6, 13: 7, 14: 4, 15: 3, 16: 3, 17: 4, 18: 6, 19: 8, 20: 7, 21: 4, 22: 2});
          final start = DateTime(date.year, date.month, date.day, hour, rand(0, 59));
          if (start.isAfter(now)) continue;
          final table = isPool ? pick(pool) : pick(dining);

          final played = isPool ? rand(25, 150) : 0;
          final billed = isPool
              ? Billing.billedMinutes(played * 60, settings.billingBlockMinutes, settings.minimumMinutes)
              : 0;
          final rate = isPool ? settings.poolRatePerHour : 0.0;
          final poolAmount = Billing.poolAmount(billed, rate);

          final lines = <int, InvoiceItem>{};
          final count = isPool ? rand(0, 3) : rand(1, 5);
          for (var i = 0; i < count; i++) {
            final m = rand(1, 100) <= 92 && popular.isNotEmpty ? pick(popular) : pick(items);
            final c = cats[m.categoryId];
            final line = lines.putIfAbsent(
              m.id!,
              () => InvoiceItem(
                menuItemId: m.id,
                name: m.name,
                categoryName: c?.name,
                categoryType: c?.type,
                qty: 0,
                unitPrice: m.price,
                unitCost: m.costPrice,
                amount: 0,
              ),
            );
            line.qty += rand(1, 2);
            line.amount = line.qty * m.price;
          }
          if (!isPool && lines.isEmpty) continue;

          final itemsSubtotal = lines.values.fold(0.0, (s, l) => s + l.amount);
          final itemsCost = lines.values.fold(0.0, (s, l) => s + l.qty * l.unitCost);
          final discount = rand(1, 100) <= 8 ? 10.0 : 0.0;
          final t = Billing.totals(
            poolAmount: poolAmount,
            itemsSubtotal: itemsSubtotal,
            discountPercent: discount,
            gstPoolRate: settings.gstPoolRate,
            gstFoodRate: settings.gstFoodRate,
          );
          final poolCost = roundTo(played / 60 * settings.poolCostPerHour, 2);
          var paidAt = start.add(Duration(minutes: math.max(played, rand(20, 50))));
          if (paidAt.isAfter(now)) paidAt = now;
          final payment = weighted({'upi': 60, 'cash': 30, 'card': 8, 'split': 2});

          final invoiceId = await txn.insert('invoices', {
            'number': settings.invoiceNumber(n++),
            'table_name': table.name,
            'payment_method': payment,
            'pool_started_at': isPool ? start.millisecondsSinceEpoch : null,
            'pool_ended_at': isPool ? start.add(Duration(minutes: played)).millisecondsSinceEpoch : null,
            'pool_played_minutes': played,
            'pool_billed_minutes': billed,
            'pool_rate': rate,
            'pool_amount': poolAmount,
            'pool_cost': poolCost,
            'items_subtotal': itemsSubtotal,
            'items_cost': itemsCost,
            'discount_percent': discount,
            'discount_amount': t.discount,
            'gst_pool': t.gstPool,
            'gst_food': t.gstFood,
            'gst_pool_rate': settings.gstPoolRate,
            'gst_food_rate': settings.gstFoodRate,
            'round_off': t.roundOff,
            'total': t.total,
            'net_revenue': t.netRevenue,
            'total_cost': roundTo(poolCost + itemsCost, 2),
            'business': business,
            'paid_at': paidAt.millisecondsSinceEpoch,
            'created_at': now.millisecondsSinceEpoch,
          });
          final batch = txn.batch();
          for (final l in lines.values) {
            l.invoiceId = invoiceId;
            batch.insert('invoice_items', l.toRow()..remove('id'));
          }
          await batch.commit(noResult: true);
          created++;
        }
      }

      settings.nextInvoiceNumber = n;
      await txn.update('settings', {'data': jsonEncode(settings.toJson())}, where: 'id = 1');
    });
    return created;
  }
}
