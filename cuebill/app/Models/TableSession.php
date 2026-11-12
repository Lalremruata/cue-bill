<?php

namespace App\Models;

use App\Support\Billing;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class TableSession extends Model
{
    protected $guarded = ['id'];

    protected $casts = [
        'timer_started_at' => 'datetime',
        'timer_paused_at' => 'datetime',
        'timer_stopped_at' => 'datetime',
        'paused_seconds' => 'integer',
        'hourly_rate' => 'float',
    ];

    public function table(): BelongsTo
    {
        return $this->belongsTo(RestaurantTable::class, 'restaurant_table_id');
    }

    public function items(): HasMany
    {
        return $this->hasMany(SessionItem::class);
    }

    public function timerState(): string
    {
        if (! $this->timer_started_at) {
            return 'idle';
        }
        if ($this->timer_stopped_at) {
            return 'stopped';
        }

        return $this->timer_paused_at ? 'paused' : 'running';
    }

    public function elapsedSeconds(?\DateTimeInterface $now = null): int
    {
        return Billing::elapsedSeconds(
            $this->timer_started_at?->getTimestamp(),
            $this->paused_seconds,
            $this->timer_paused_at?->getTimestamp(),
            $this->timer_stopped_at?->getTimestamp(),
            ($now ?? now())->getTimestamp(),
        );
    }

    public function itemsSubtotal(): float
    {
        return (float) $this->items->sum(fn (SessionItem $i) => $i->qty * $i->menuItem->price);
    }
}
