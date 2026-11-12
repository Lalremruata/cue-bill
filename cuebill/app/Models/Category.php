<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Category extends Model
{
    public const TYPES = ['food' => 'Food', 'drinks' => 'Drinks', 'snacks' => 'Snacks'];

    protected $guarded = ['id'];

    public function menuItems(): HasMany
    {
        return $this->hasMany(MenuItem::class);
    }
}
