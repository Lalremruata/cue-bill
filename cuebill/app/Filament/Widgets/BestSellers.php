<?php

namespace App\Filament\Widgets;

use App\Services\SalesAnalytics;
use App\Support\Billing;
use Filament\Widgets\Widget;

class BestSellers extends Widget
{
    protected static ?int $sort = 5;

    protected string $view = 'filament.widgets.item-list';

    protected function getViewData(): array
    {
        $rows = SalesAnalytics::lastDays(30)->items()->where('qty', '>', 0)->sortByDesc('profit')->take(6)->values();

        return [
            'heading' => 'Best sellers',
            'description' => 'Top profit earners, last 30 days',
            'rows' => $rows->map(fn ($r) => [
                'name' => $r['name'],
                'meta' => $r['qty'].($r['unit'] ? ' '.$r['unit'] : ' sold').' · '.Billing::inr($r['profit']).' profit',
                'badge' => round($r['margin']).'%',
                'tone' => 'good',
            ]),
            'empty' => 'No sales yet.',
        ];
    }
}
