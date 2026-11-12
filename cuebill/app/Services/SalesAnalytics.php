<?php

namespace App\Services;

use App\Models\BusinessSetting;
use App\Models\Invoice;
use App\Models\MenuItem;
use App\Models\RestaurantTable;
use Carbon\CarbonImmutable;
use Carbon\CarbonPeriod;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * All dashboard and report numbers. Revenue = after discount, before GST.
 * "Collected" = what the customer paid (incl. GST).
 */
class SalesAnalytics
{
    public function __construct(
        public CarbonImmutable $from,
        public CarbonImmutable $to,
        public ?string $payment = null,
    ) {
        $this->from = $from->startOfDay();
        $this->to = $to->endOfDay();
    }

    public static function lastDays(int $days, ?CarbonImmutable $end = null): self
    {
        $end = ($end ?? CarbonImmutable::now())->endOfDay();

        return new self($end->subDays($days - 1)->startOfDay(), $end);
    }

    public function previousPeriod(): self
    {
        $days = (int) $this->from->diffInDays($this->to) + 1;

        return new self($this->from->subDays($days), $this->from->subDay(), $this->payment);
    }

    public function invoices(): Builder
    {
        return Invoice::query()
            ->whereBetween('paid_at', [$this->from, $this->to])
            ->when($this->payment, fn (Builder $q) => $q->where('payment_method', $this->payment));
    }

    /** @return array{collected: float, revenue: float, cost: float, profit: float, margin: float, invoices: int, pool_hours: float, gst: float, discount: float} */
    public function summary(): array
    {
        $row = $this->invoices()->selectRaw('
            COUNT(*) as invoices,
            COALESCE(SUM(total), 0) as collected,
            COALESCE(SUM(net_revenue), 0) as revenue,
            COALESCE(SUM(total_cost), 0) as cost,
            COALESCE(SUM(gst_pool + gst_food), 0) as gst,
            COALESCE(SUM(discount_amount), 0) as discount,
            COALESCE(SUM(pool_played_minutes), 0) as pool_minutes
        ')->toBase()->first();

        $revenue = (float) $row->revenue;
        $profit = $revenue - (float) $row->cost;

        return [
            'collected' => (float) $row->collected,
            'revenue' => $revenue,
            'cost' => (float) $row->cost,
            'profit' => $profit,
            'margin' => $revenue > 0 ? round($profit / $revenue * 100, 1) : 0.0,
            'invoices' => (int) $row->invoices,
            'pool_hours' => round($row->pool_minutes / 60, 1),
            'gst' => (float) $row->gst,
            'discount' => (float) $row->discount,
        ];
    }

    /** Pool table occupancy % over the period (all pool tables, opening hours from 12 PM to midnight). */
    public function poolOccupancy(int $openHoursPerDay = 12): float
    {
        $tables = max(1, RestaurantTable::query()->where('type', 'pool')->where('is_active', true)->count());
        $days = (int) $this->from->diffInDays($this->to) + 1;
        $minutes = (float) $this->invoices()->sum('pool_played_minutes');

        return round(min(100, $minutes / ($tables * $days * $openHoursPerDay * 60) * 100), 1);
    }

    /** One row per day with pool / food / drinks / snacks revenue and profit. */
    public function daily(): Collection
    {
        $invoiceRows = $this->invoices()
            ->selectRaw('DATE(paid_at) as day, COUNT(*) as invoices, SUM(total) as collected, SUM(net_revenue) as revenue,
                SUM(total_cost) as cost, SUM(pool_played_minutes) as pool_minutes,
                SUM(pool_amount * (1 - discount_percent / 100)) as pool_revenue')
            ->groupByRaw('DATE(paid_at)')
            ->toBase()->get()->keyBy('day');

        $typeRows = $this->itemLines()
            ->selectRaw('DATE(invoices.paid_at) as day, invoice_items.category_type as type,
                SUM(invoice_items.amount * (1 - invoices.discount_percent / 100)) as revenue')
            ->groupByRaw('DATE(invoices.paid_at), invoice_items.category_type')
            ->get()->groupBy('day');

        return collect(CarbonPeriod::create($this->from, '1 day', $this->to->startOfDay()))->map(function ($date) use ($invoiceRows, $typeRows) {
            $key = $date->format('Y-m-d');
            $r = $invoiceRows->get($key);
            $types = ($typeRows->get($key) ?? collect())->pluck('revenue', 'type');
            $revenue = (float) ($r->revenue ?? 0);
            $profit = $revenue - (float) ($r->cost ?? 0);

            return [
                'date' => $date->toImmutable(),
                'invoices' => (int) ($r->invoices ?? 0),
                'pool_hours' => round(($r->pool_minutes ?? 0) / 60, 1),
                'pool' => round((float) ($r->pool_revenue ?? 0), 2),
                'food' => round((float) ($types['food'] ?? 0), 2),
                'drinks' => round((float) ($types['drinks'] ?? 0), 2),
                'snacks' => round((float) ($types['snacks'] ?? 0), 2),
                'revenue' => $revenue,
                'collected' => (float) ($r->collected ?? 0),
                'profit' => round($profit, 2),
                'margin' => $revenue > 0 ? round($profit / $revenue * 100, 1) : 0.0,
            ];
        })->values();
    }

    /** Revenue and profit for pool time and each menu category type. */
    public function mix(): Collection
    {
        $pool = $this->invoices()->selectRaw('COALESCE(SUM(pool_amount * (1 - discount_percent / 100)), 0) as revenue, COALESCE(SUM(pool_cost), 0) as cost')->toBase()->first();

        $rows = collect([['key' => 'pool', 'name' => 'Pool table time', 'revenue' => (float) $pool->revenue, 'cost' => (float) $pool->cost]]);

        $types = $this->itemLines()
            ->selectRaw('invoice_items.category_type as type,
                SUM(invoice_items.amount * (1 - invoices.discount_percent / 100)) as revenue,
                SUM(invoice_items.qty * invoice_items.unit_cost) as cost')
            ->groupBy('invoice_items.category_type')->get()->keyBy('type');

        foreach (\App\Models\Category::TYPES as $key => $label) {
            $t = $types->get($key);
            $rows->push(['key' => $key, 'name' => $label, 'revenue' => (float) ($t->revenue ?? 0), 'cost' => (float) ($t->cost ?? 0)]);
        }

        return $rows->map(function ($r) {
            $r['profit'] = round($r['revenue'] - $r['cost'], 2);
            $r['margin'] = $r['revenue'] > 0 ? round($r['profit'] / $r['revenue'] * 100, 1) : 0.0;

            return $r;
        });
    }

    /**
     * Item performance with a rating: Star, Steady, Slow or Loss risk.
     * Item revenue here is the menu price × qty (before bill discounts).
     */
    public function items(?string $categoryType = null, string $sort = 'profit'): Collection
    {
        $rows = collect();

        if (! $categoryType || $categoryType === 'pool') {
            $p = $this->invoices()->selectRaw('COALESCE(SUM(pool_billed_minutes), 0) as minutes, COALESCE(SUM(pool_amount), 0) as revenue, COALESCE(SUM(pool_cost), 0) as cost')->toBase()->first();
            if ($p->minutes > 0) {
                $rows->push(['name' => 'Pool table (per hour)', 'category' => 'Pool table', 'type' => 'pool',
                    'qty' => round($p->minutes / 60, 1), 'unit' => 'h', 'revenue' => (float) $p->revenue, 'cost' => (float) $p->cost]);
            }
        }

        if ($categoryType !== 'pool') {
            $sold = $this->itemLines()
                ->when($categoryType, fn ($q) => $q->where('invoice_items.category_type', $categoryType))
                ->selectRaw('invoice_items.menu_item_id, invoice_items.name, invoice_items.category_name, invoice_items.category_type,
                    SUM(invoice_items.qty) as qty, SUM(invoice_items.amount) as revenue, SUM(invoice_items.qty * invoice_items.unit_cost) as cost')
                ->groupBy('invoice_items.menu_item_id', 'invoice_items.name', 'invoice_items.category_name', 'invoice_items.category_type')
                ->get();

            foreach ($sold as $s) {
                $rows->push(['name' => $s->name, 'category' => $s->category_name, 'type' => $s->category_type,
                    'qty' => (int) $s->qty, 'unit' => '', 'revenue' => (float) $s->revenue, 'cost' => (float) $s->cost]);
            }

            // Active items that did not sell at all in the period.
            MenuItem::query()->with('category')->where('is_active', true)
                ->whereNotIn('id', $sold->pluck('menu_item_id')->filter())
                ->when($categoryType, fn ($q) => $q->whereHas('category', fn ($c) => $c->where('type', $categoryType)))
                ->get()
                ->each(fn (MenuItem $m) => $rows->push(['name' => $m->name, 'category' => $m->category?->name, 'type' => $m->category?->type,
                    'qty' => 0, 'unit' => '', 'revenue' => 0.0, 'cost' => 0.0, 'list_margin' => $m->marginPercent()]));
        }

        $avgQty = max(1, (float) $rows->where('unit', '')->avg('qty'));

        return $rows->map(function ($r) use ($avgQty) {
            $r['profit'] = round($r['revenue'] - $r['cost'], 2);
            $r['margin'] = $r['revenue'] > 0 ? round($r['profit'] / $r['revenue'] * 100, 1) : ($r['list_margin'] ?? 0.0);
            $isPool = $r['unit'] === 'h';
            $r['rating'] = match (true) {
                $r['margin'] < 30 => 'Loss risk',
                ! $isPool && $r['qty'] < max(5, $avgQty * 0.2) => 'Slow',
                $r['margin'] >= 60 && ($isPool || $r['qty'] >= $avgQty) => 'Star',
                default => 'Steady',
            };

            return $r;
        })->sortByDesc($sort)->values();
    }

    /** Average pool table occupancy % by hour of day (12 PM – 11 PM). */
    public function busyHours(int $fromHour = 12, int $toHour = 23): array
    {
        $minutesByHour = array_fill(0, 24, 0.0);

        $this->invoices()->whereNotNull('pool_started_at')->get(['pool_started_at', 'pool_ended_at'])
            ->each(function (Invoice $inv) use (&$minutesByHour) {
                $cursor = CarbonImmutable::parse($inv->pool_started_at);
                $end = CarbonImmutable::parse($inv->pool_ended_at ?? $inv->pool_started_at);
                while ($cursor < $end) {
                    $next = min($end, $cursor->startOfHour()->addHour());
                    $minutesByHour[(int) $cursor->format('G')] += $cursor->diffInSeconds($next, true) / 60;
                    $cursor = $next;
                }
            });

        $tables = max(1, RestaurantTable::query()->where('type', 'pool')->where('is_active', true)->count());
        $days = (int) $this->from->diffInDays($this->to) + 1;
        $out = [];
        for ($h = $fromHour; $h <= $toHour; $h++) {
            $out[$h] = round(min(100, $minutesByHour[$h] / ($tables * $days * 60) * 100), 1);
        }

        return $out;
    }

    private function itemLines()
    {
        return DB::table('invoice_items')
            ->join('invoices', 'invoices.id', '=', 'invoice_items.invoice_id')
            ->whereBetween('invoices.paid_at', [$this->from, $this->to])
            ->when($this->payment, fn ($q) => $q->where('invoices.payment_method', $this->payment));
    }
}
