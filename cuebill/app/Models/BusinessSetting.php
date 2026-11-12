<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class BusinessSetting extends Model
{
    protected $guarded = ['id'];

    protected $casts = [
        'show_upi_qr' => 'boolean',
        'happy_hour_enabled' => 'boolean',
        'pool_rate_per_hour' => 'float',
        'pool_cost_per_hour' => 'float',
        'happy_hour_rate' => 'float',
        'gst_food_rate' => 'float',
        'gst_pool_rate' => 'float',
        'billing_block_minutes' => 'integer',
        'minimum_minutes' => 'integer',
        'next_invoice_number' => 'integer',
    ];

    /** The one settings row (created on first use). */
    public static function current(): self
    {
        return static::query()->first() ?? static::query()->create([]);
    }

    /** Details printed on every invoice; copied onto the invoice when it is saved. */
    public function snapshot(): array
    {
        return [
            'name' => $this->name,
            'address' => $this->address,
            'city' => $this->city,
            'state' => $this->state,
            'pin' => $this->pin,
            'phone' => $this->phone,
            'email' => $this->email,
            'gstin' => $this->gstin,
            'fssai' => $this->fssai,
            'logo_path' => $this->logo_path,
            'footer' => $this->invoice_footer,
            'upi_id' => $this->upi_id,
            'upi_payee_name' => $this->upi_payee_name ?: $this->name,
            'show_upi_qr' => (bool) $this->show_upi_qr,
        ];
    }

    /** Hourly rate for a pool table timer that starts at $at. */
    public function poolRateFor(?RestaurantTable $table, \DateTimeInterface $at): float
    {
        if ($this->happy_hour_enabled) {
            $t = $at->format('H:i:s');
            if ($t >= $this->happy_hour_start && $t < $this->happy_hour_end) {
                return (float) $this->happy_hour_rate;
            }
        }

        return (float) ($table?->hourly_rate ?: $this->pool_rate_per_hour);
    }
}
