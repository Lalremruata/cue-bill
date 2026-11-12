<?php

namespace App\Filament\Widgets;

use App\Services\SalesAnalytics;
use Filament\Widgets\ChartWidget;

class RevenueChart extends ChartWidget
{
    protected static ?int $sort = 2;

    protected int|string|array $columnSpan = 'full';

    public ?string $filter = '14';

    public function getHeading(): ?string
    {
        return 'Revenue by day';
    }

    public function getDescription(): ?string
    {
        return 'After discounts, before GST — pool time vs food, drinks and snacks.';
    }

    protected function getFilters(): ?array
    {
        return ['7' => 'Last 7 days', '14' => 'Last 14 days', '30' => 'Last 30 days', '90' => 'Last 90 days'];
    }

    protected function getType(): string
    {
        return 'bar';
    }

    protected function getData(): array
    {
        $days = SalesAnalytics::lastDays((int) ($this->filter ?: 14))->daily();
        $set = fn (string $label, string $key, string $color) => [
            'label' => $label,
            'data' => $days->pluck($key)->all(),
            'backgroundColor' => $color,
            'borderColor' => $color,
            'borderRadius' => 3,
            'stack' => 'revenue',
        ];

        return [
            'datasets' => [
                $set('Pool table', 'pool', '#0E6B4A'),
                $set('Food', 'food', '#D08A2E'),
                $set('Drinks', 'drinks', '#9CC5B0'),
                $set('Snacks', 'snacks', '#E9C98F'),
            ],
            'labels' => $days->map(fn ($d) => $d['date']->format('d M'))->all(),
        ];
    }

    protected function getOptions(): array
    {
        return [
            'scales' => [
                'x' => ['stacked' => true, 'grid' => ['display' => false]],
                'y' => ['stacked' => true, 'beginAtZero' => true],
            ],
            'plugins' => ['legend' => ['position' => 'bottom']],
        ];
    }
}
