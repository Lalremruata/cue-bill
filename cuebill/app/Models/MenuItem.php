<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MenuItem extends Model
{
    protected $guarded = ['id'];

    protected $casts = ['cost_price' => 'float', 'price' => 'float', 'is_active' => 'boolean'];

    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    public function marginPercent(): float
    {
        return $this->price > 0 ? round(($this->price - $this->cost_price) / $this->price * 100, 1) : 0.0;
    }
}
