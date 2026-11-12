<?php

namespace App\Services;

use App\Models\BusinessSetting;
use App\Models\Invoice;
use App\Models\SessionItem;
use App\Models\TableSession;
use App\Support\Billing;
use App\Support\UpiQr;
use Illuminate\Support\Facades\DB;

class CheckoutService
{
    /**
     * Work out every figure for a bill without saving anything.
     *
     * @param  array{payment_method?: string, discount_percent?: float|int|string|null}  $options
     */
    public function calculate(TableSession $session, array $options = []): array
    {
        $settings = BusinessSetting::current();
        $session->loadMissing(['table', 'items.menuItem.category']);
        $now = now();

        $isPool = $session->table->isPool() && $session->timer_started_at;
        $playedSeconds = $isPool ? $session->elapsedSeconds($now) : 0;
        $billedMinutes = $isPool ? Billing::billedMinutes($playedSeconds, $settings->billing_block_minutes, $settings->minimum_minutes) : 0;
        $rate = (float) ($session->hourly_rate ?: $settings->poolRateFor($session->table, $session->timer_started_at ?? $now));
        $poolAmount = Billing::poolAmount($billedMinutes, $rate);
        $poolCost = round($playedSeconds / 3600 * $settings->pool_cost_per_hour, 2);

        $items = $session->items->map(fn (SessionItem $line) => [
            'menu_item_id' => $line->menu_item_id,
            'name' => $line->menuItem->name,
            'category_name' => $line->menuItem->category?->name,
            'category_type' => $line->menuItem->category?->type,
            'qty' => $line->qty,
            'unit_price' => (float) $line->menuItem->price,
            'unit_cost' => (float) $line->menuItem->cost_price,
            'amount' => round($line->qty * $line->menuItem->price, 2),
        ])->values()->all();

        $itemsSubtotal = round(array_sum(array_column($items, 'amount')), 2);
        $itemsCost = round(array_sum(array_map(fn ($i) => $i['qty'] * $i['unit_cost'], $items)), 2);
        $discount = (float) ($options['discount_percent'] ?? 0);
        $totals = Billing::totals($poolAmount, $itemsSubtotal, $discount, $settings->gst_pool_rate, $settings->gst_food_rate);

        return [
            'settings' => $settings,
            'is_pool' => (bool) $isPool,
            'pool_started_at' => $session->timer_started_at,
            'pool_ended_at' => $isPool ? ($session->timer_stopped_at ?? $session->timer_paused_at ?? $now) : null,
            'played_minutes' => (int) ceil($playedSeconds / 60),
            'billed_minutes' => $billedMinutes,
            'rate' => $rate,
            'pool_amount' => $poolAmount,
            'pool_cost' => $poolCost,
            'items' => $items,
            'items_subtotal' => $itemsSubtotal,
            'items_cost' => $itemsCost,
            'discount_percent' => $discount,
            'totals' => $totals,
        ];
    }

    /** Receipt data for the checkout preview (same shape as Invoice::toReceipt()). */
    public function preview(TableSession $session, array $options = []): array
    {
        $c = $this->calculate($session, $options);
        $s = $c['settings'];
        $business = $s->snapshot();
        $payment = $options['payment_method'] ?? 'cash';
        $total = $c['totals']['total'];
        $number = $s->invoice_prefix.str_pad((string) $s->next_invoice_number, 5, '0', STR_PAD_LEFT);

        $lines = [];
        if ($c['billed_minutes'] > 0) {
            $lines[] = [
                'name' => 'Pool table time',
                'note' => $c['pool_started_at']->format('g:i A').' – '.$c['pool_ended_at']->format('g:i A')
                    .' · played '.Billing::duration($c['played_minutes']).', billed '.Billing::duration($c['billed_minutes']),
                'qty' => rtrim(rtrim(number_format($c['billed_minutes'] / 60, 2), '0'), '.').' h',
                'rate' => $c['rate'],
                'amount' => $c['pool_amount'],
            ];
        }
        foreach ($c['items'] as $i) {
            $lines[] = ['name' => $i['name'], 'note' => null, 'qty' => $i['qty'], 'rate' => $i['unit_price'], 'amount' => $i['amount']];
        }

        $showQr = $business['show_upi_qr'] && UpiQr::isValidUpiId($business['upi_id']) && in_array($payment, ['upi', 'split'], true) && $total > 0;

        return [
            'business' => $business,
            'number' => $number,
            'date' => now(),
            'table' => $session->table->name,
            'customer' => $options['customer_name'] ?? null,
            'phone' => $options['customer_phone'] ?? null,
            'payment' => Invoice::PAYMENT_METHODS[$payment] ?? $payment,
            'lines' => $lines,
            'subtotal' => $c['totals']['subtotal'],
            'discount_percent' => $c['discount_percent'],
            'discount' => $c['totals']['discount'],
            'gst_pool' => $c['totals']['gst_pool'],
            'gst_food' => $c['totals']['gst_food'],
            'gst_pool_rate' => $s->gst_pool_rate,
            'gst_food_rate' => $s->gst_food_rate,
            'round_off' => $c['totals']['round_off'],
            'total' => $total,
            'cash_received' => isset($options['cash_received']) && $options['cash_received'] !== '' ? (float) $options['cash_received'] : null,
            'qr_svg' => $showQr ? UpiQr::svg($business['upi_id'], $business['upi_payee_name'], $total, 'Bill '.$number) : null,
            'upi_id' => $business['upi_id'],
            'draft' => true,
        ];
    }

    /**
     * Save the sale: create the invoice, close the table and bump the invoice number.
     *
     * @param  array{payment_method: string, discount_percent?: float|int|string|null, customer_name?: ?string, customer_phone?: ?string, cash_received?: float|int|string|null}  $options
     */
    public function complete(TableSession $session, array $options): Invoice
    {
        return DB::transaction(function () use ($session, $options) {
            $session = TableSession::query()->lockForUpdate()->findOrFail($session->id);
            abort_if($session->status !== 'open', 422, 'This table has already been checked out.');

            $c = $this->calculate($session, $options);
            abort_if($c['billed_minutes'] === 0 && $c['items'] === [], 422, 'Nothing to bill yet.');

            $settings = BusinessSetting::query()->lockForUpdate()->findOrFail($c['settings']->id);
            $number = $settings->invoice_prefix.str_pad((string) $settings->next_invoice_number, 5, '0', STR_PAD_LEFT);
            $settings->increment('next_invoice_number');
            $t = $c['totals'];

            $invoice = Invoice::create([
                'number' => $number,
                'table_session_id' => $session->id,
                'table_name' => $session->table->name,
                'customer_name' => $options['customer_name'] ?? null ?: null,
                'customer_phone' => $options['customer_phone'] ?? null ?: null,
                'payment_method' => $options['payment_method'],
                'cash_received' => ($options['cash_received'] ?? '') !== '' ? (float) $options['cash_received'] : null,
                'pool_started_at' => $c['pool_started_at'],
                'pool_ended_at' => $c['pool_ended_at'],
                'pool_played_minutes' => $c['played_minutes'],
                'pool_billed_minutes' => $c['billed_minutes'],
                'pool_rate' => $c['billed_minutes'] ? $c['rate'] : 0,
                'pool_amount' => $c['pool_amount'],
                'pool_cost' => $c['pool_cost'],
                'items_subtotal' => $c['items_subtotal'],
                'items_cost' => $c['items_cost'],
                'discount_percent' => $c['discount_percent'],
                'discount_amount' => $t['discount'],
                'gst_pool' => $t['gst_pool'],
                'gst_food' => $t['gst_food'],
                'gst_pool_rate' => $settings->gst_pool_rate,
                'gst_food_rate' => $settings->gst_food_rate,
                'round_off' => $t['round_off'],
                'total' => $t['total'],
                'net_revenue' => $t['net_revenue'],
                'total_cost' => round($c['pool_cost'] + $c['items_cost'], 2),
                'business' => $settings->snapshot(),
                'paid_at' => now(),
            ]);
            $invoice->items()->createMany($c['items']);

            $session->update([
                'status' => 'closed',
                'timer_stopped_at' => $c['pool_ended_at'] ?? $session->timer_stopped_at,
            ]);

            return $invoice;
        });
    }
}
