<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class RestaurantTable extends Model
{
    public const TYPES = ['pool' => 'Pool table', 'dining' => 'Dining table', 'takeaway' => 'Takeaway'];

    protected $guarded = ['id'];

    protected $casts = ['hourly_rate' => 'float', 'is_active' => 'boolean'];

    public function sessions(): HasMany
    {
        return $this->hasMany(TableSession::class);
    }

    public function openSession(): HasOne
    {
        return $this->hasOne(TableSession::class)->where('status', 'open')->latestOfMany();
    }

    public function isPool(): bool
    {
        return $this->type === 'pool';
    }
}
