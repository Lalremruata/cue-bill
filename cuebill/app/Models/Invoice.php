<?php

namespace App\Models;

use App\Support\UpiQr;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Invoice extends Model
{
    public const PAYMENT_METHODS = ['cash' => 'Cash', 'upi' => 'UPI', 'card' => 'Card', 'split' => 'Split'];

    protected $guarded = ['id'];

    protected $casts = [
        'business' => 'array',
        'paid_at' => 'datetime',
        'pool_started_at' => 'datetime',
        'pool_ended_at' => 'datetime',
        'pool_rate' => 'float', 'pool_amount' => 'float', 'pool_cost' => 'float',
        'items_subtotal' => 'float', 'items_cost' => 'float',
        'discount_percent' => 'float', 'discount_amount' => 'float',
        'gst_pool' => 'float', 'gst_food' => 'float', 'gst_pool_rate' => 'float', 'gst_food_rate' => 'float',
        'round_off' => 'float', 'total' => 'float', 'net_revenue' => 'float', 'total_cost' => 'float',
        'cash_received' => 'float',
    ];

    public function items(): HasMany
    {
        return $this->hasMany(InvoiceItem::class);
    }

    public function profit(): float
    {
        return round($this->net_revenue - $this->total_cost, 2);
    }

    /** Data for resources/views/invoices/partials/receipt.blade.php */
    public function toReceipt(): array
    {
        $lines = [];
        if ($this->pool_billed_minutes > 0) {
            $lines[] = [
                'name' => 'Pool table time',
                'note' => $this->pool_started_at?->format('g:i A').' – '.$this->pool_ended_at?->format('g:i A')
                    .' · played '.\App\Support\Billing::duration($this->pool_played_minutes)
                    .', billed '.\App\Support\Billing::duration($this->pool_billed_minutes),
                'qty' => rtrim(rtrim(number_format($this->pool_billed_minutes / 60, 2), '0'), '.').' h',
                'rate' => $this->pool_rate,
                'amount' => $this->pool_amount,
            ];
        }
        foreach ($this->items as $item) {
            $lines[] = ['name' => $item->name, 'note' => null, 'qty' => $item->qty, 'rate' => $item->unit_price, 'amount' => $item->amount];
        }

        $business = $this->business ?? [];
        $showQr = ($business['show_upi_qr'] ?? false) && ! empty($business['upi_id']) && in_array($this->payment_method, ['upi', 'split'], true);

        return [
            'business' => $business,
            'number' => $this->number,
            'date' => $this->paid_at,
            'table' => $this->table_name,
            'customer' => $this->customer_name,
            'phone' => $this->customer_phone,
            'payment' => self::PAYMENT_METHODS[$this->payment_method] ?? $this->payment_method,
            'lines' => $lines,
            'subtotal' => $this->pool_amount + $this->items_subtotal,
            'discount_percent' => $this->discount_percent,
            'discount' => $this->discount_amount,
            'gst_pool' => $this->gst_pool,
            'gst_food' => $this->gst_food,
            'gst_pool_rate' => $this->gst_pool_rate,
            'gst_food_rate' => $this->gst_food_rate,
            'round_off' => $this->round_off,
            'total' => $this->total,
            'cash_received' => $this->cash_received,
            'qr_svg' => $showQr ? UpiQr::svg($business['upi_id'], $business['upi_payee_name'] ?? '', $this->total, 'Bill '.$this->number) : null,
            'upi_id' => $business['upi_id'] ?? null,
            'draft' => false,
        ];
    }
}
