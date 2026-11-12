<?php

namespace App\Http\Controllers;

use App\Models\Invoice;
use App\Services\SalesAnalytics;
use App\Support\SpreadsheetExport;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;

class ExportController extends Controller
{
    private function analytics(Request $request): SalesAnalytics
    {
        $from = CarbonImmutable::parse($request->query('from', now()->subDays(29)->toDateString()));
        $to = CarbonImmutable::parse($request->query('to', now()->toDateString()));

        return new SalesAnalytics($from, $to, $request->query('payment') ?: null);
    }

    private function suffix(SalesAnalytics $a): string
    {
        return $a->from->format('Y-m-d').'_to_'.$a->to->format('Y-m-d');
    }

    public function invoices(Request $request)
    {
        $a = $this->analytics($request);
        $rows = $a->invoices()->orderBy('paid_at')->lazy()->map(fn (Invoice $i) => [
            $i->number, $i->paid_at->format('Y-m-d H:i'), $i->table_name, Invoice::PAYMENT_METHODS[$i->payment_method] ?? $i->payment_method,
            $i->customer_name, $i->customer_phone,
            round($i->pool_billed_minutes / 60, 2), $i->pool_amount, $i->items_subtotal, $i->discount_amount,
            $i->gst_pool, $i->gst_food, $i->round_off, $i->total, $i->net_revenue, $i->total_cost, $i->profit(),
        ]);

        return SpreadsheetExport::download('invoices_'.$this->suffix($a).'.xlsx', [
            'Invoice', 'Date', 'Table', 'Payment', 'Customer', 'Phone',
            'Pool hours billed', 'Pool amount', 'Food & drinks', 'Discount',
            'GST pool', 'GST food', 'Round off', 'Total collected', 'Revenue (ex GST)', 'Cost', 'Profit',
        ], $rows);
    }

    public function items(Request $request)
    {
        $a = $this->analytics($request);
        $rows = $a->items($request->query('category') ?: null, $request->query('sort', 'profit'))->map(fn ($r) => [
            $r['name'], $r['category'], $r['qty'], $r['revenue'], $r['cost'], $r['profit'], $r['margin'], $r['rating'],
        ]);

        return SpreadsheetExport::download('item_performance_'.$this->suffix($a).'.xlsx',
            ['Item', 'Category', 'Qty sold', 'Revenue', 'Cost', 'Profit', 'Margin %', 'Rating'], $rows);
    }

    public function daily(Request $request)
    {
        $a = $this->analytics($request);
        $rows = $a->daily()->map(fn ($d) => [
            $d['date']->format('Y-m-d'), $d['invoices'], $d['pool_hours'], $d['pool'], $d['food'], $d['drinks'], $d['snacks'],
            $d['revenue'], $d['collected'], $d['profit'], $d['margin'],
        ]);

        return SpreadsheetExport::download('daily_sales_'.$this->suffix($a).'.xlsx',
            ['Date', 'Invoices', 'Pool hours', 'Pool revenue', 'Food', 'Drinks', 'Snacks', 'Revenue (ex GST)', 'Collected', 'Profit', 'Margin %'], $rows);
    }

    /** Download a copy of the local SQLite database. */
    public function backup()
    {
        $path = config('database.connections.sqlite.database');
        abort_unless(config('database.default') === 'sqlite' && File::exists($path), 404, 'Backup download works with the SQLite database only.');

        return response()->download($path, 'cuebill-backup-'.now()->format('Y-m-d-His').'.sqlite');
    }
}
