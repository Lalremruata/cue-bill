<?php

namespace App\Filament\Widgets;

use App\Services\SalesAnalytics;
use Filament\Widgets\Widget;

class NeedsAttention extends Widget
{
    protected static ?int $sort = 6;

    protected string $view = 'filament.widgets.item-list';

    protected function getViewData(): array
    {
        $rows = SalesAnalytics::lastDays(30)->items()
            ->filter(fn ($r) => in_array($r['rating'], ['Loss risk', 'Slow']))
            ->sortBy([['rating', 'asc'], ['margin', 'asc']])
            ->take(6)->values();

        return [
            'heading' => 'Needs attention',
            'description' => 'Thin margin or slow sales, last 30 days',
            'rows' => $rows->map(fn ($r) => [
                'name' => $r['name'],
                'meta' => $r['rating'] === 'Loss risk' ? 'Thin margin — raise the price or cut cost' : ($r['qty'] ? 'Only '.$r['qty'].' sold' : 'Not sold at all'),
                'badge' => round($r['margin']).'%',
                'tone' => $r['rating'] === 'Loss risk' ? 'bad' : 'warn',
            ]),
            'empty' => 'Nothing to worry about.',
        ];
    }
}
