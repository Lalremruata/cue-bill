<?php

namespace Database\Seeders;

use App\Models\BusinessSetting;
use App\Models\Invoice;
use App\Models\MenuItem;
use App\Models\RestaurantTable;
use App\Support\Billing;
use Illuminate\Database\Seeder;

/**
 * Optional: fills the last 45 days with sample sales so the dashboard and reports have something to show.
 * php artisan db:seed --class=DemoSalesSeeder      (remove later with: php artisan migrate:fresh --seed)
 */
class DemoSalesSeeder extends Seeder
{
    public function run(): void
    {
        mt_srand(42);
        $settings = BusinessSetting::current();
        $items = MenuItem::query()->with('category')->get();
        $popular = $items->whereNotIn('name', ['Grilled fish platter', 'Veg club sandwich', 'Hot chocolate'])->values();
        $tables = RestaurantTable::query()->get();
        $pool = $tables->where('type', 'pool')->values();
        $dining = $tables->where('type', '!=', 'pool')->values();
        $n = $settings->next_invoice_number;

        for ($day = 44; $day >= 0; $day--) {
            $date = now()->subDays($day)->startOfDay();
            $weekend = $date->isFriday() || $date->isSaturday() || $date->isSunday();
            $bills = mt_rand(14, 22) + ($weekend ? 10 : 0);

            for ($b = 0; $b < $bills; $b++) {
                $isPool = mt_rand(1, 100) <= 40;
                $hour = $isPool ? $this->weighted([12 => 1, 13 => 1, 14 => 2, 15 => 2, 16 => 4, 17 => 6, 18 => 8, 19 => 10, 20 => 10, 21 => 8, 22 => 5])
                    : $this->weighted([12 => 6, 13 => 7, 14 => 4, 15 => 3, 16 => 3, 17 => 4, 18 => 6, 19 => 8, 20 => 7, 21 => 4, 22 => 2]);
                $start = $date->copy()->setTime($hour, mt_rand(0, 59));
                if ($start->isFuture()) {
                    continue;
                }
                $table = $isPool ? $pool->random() : $dining->random();

                $played = $isPool ? mt_rand(25, 150) : 0;
                $billed = $isPool ? Billing::billedMinutes($played * 60, $settings->billing_block_minutes, $settings->minimum_minutes) : 0;
                $rate = $isPool ? $settings->pool_rate_per_hour : 0;
                $poolAmount = Billing::poolAmount($billed, $rate);

                $lines = [];
                $count = $isPool ? mt_rand(0, 3) : mt_rand(1, 5);
                for ($i = 0; $i < $count; $i++) {
                    $m = mt_rand(1, 100) <= 92 ? $popular->random() : $items->random();
                    $lines[$m->id] ??= ['menu_item_id' => $m->id, 'name' => $m->name, 'category_name' => $m->category->name,
                        'category_type' => $m->category->type, 'qty' => 0, 'unit_price' => $m->price, 'unit_cost' => $m->cost_price, 'amount' => 0];
                    $lines[$m->id]['qty'] += mt_rand(1, 2);
                    $lines[$m->id]['amount'] = $lines[$m->id]['qty'] * $m->price;
                }
                if (! $isPool && ! $lines) {
                    continue;
                }

                $itemsSubtotal = array_sum(array_column($lines, 'amount'));
                $itemsCost = array_sum(array_map(fn ($l) => $l['qty'] * $l['unit_cost'], $lines));
                $discount = mt_rand(1, 100) <= 8 ? 10 : 0;
                $t = Billing::totals($poolAmount, $itemsSubtotal, $discount, $settings->gst_pool_rate, $settings->gst_food_rate);
                $poolCost = round($played / 60 * $settings->pool_cost_per_hour, 2);
                $paidAt = $start->copy()->addMinutes(max($played, mt_rand(20, 50)));
                $payment = $this->weighted(['upi' => 60, 'cash' => 30, 'card' => 8, 'split' => 2]);

                $invoice = Invoice::create([
                    'number' => $settings->invoice_prefix.str_pad((string) $n++, 5, '0', STR_PAD_LEFT),
                    'table_name' => $table->name,
                    'payment_method' => $payment,
                    'pool_started_at' => $isPool ? $start : null,
                    'pool_ended_at' => $isPool ? $start->copy()->addMinutes($played) : null,
                    'pool_played_minutes' => $played,
                    'pool_billed_minutes' => $billed,
                    'pool_rate' => $rate,
                    'pool_amount' => $poolAmount,
                    'pool_cost' => $poolCost,
                    'items_subtotal' => $itemsSubtotal,
                    'items_cost' => $itemsCost,
                    'discount_percent' => $discount,
                    'discount_amount' => $t['discount'],
                    'gst_pool' => $t['gst_pool'],
                    'gst_food' => $t['gst_food'],
                    'gst_pool_rate' => $settings->gst_pool_rate,
                    'gst_food_rate' => $settings->gst_food_rate,
                    'round_off' => $t['round_off'],
                    'total' => $t['total'],
                    'net_revenue' => $t['net_revenue'],
                    'total_cost' => round($poolCost + $itemsCost, 2),
                    'business' => $settings->snapshot(),
                    'paid_at' => $paidAt->isFuture() ? now() : $paidAt,
                ]);
                $invoice->items()->createMany(array_values($lines));
            }
        }

        $settings->update(['next_invoice_number' => $n]);
    }

    private function weighted(array $weights): int|string
    {
        $r = mt_rand(1, array_sum($weights));
        foreach ($weights as $key => $w) {
            if (($r -= $w) <= 0) {
                return $key;
            }
        }

        return array_key_first($weights);
    }
}
