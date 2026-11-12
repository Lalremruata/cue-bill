<?php

namespace App\Filament\Widgets;

use App\Services\SalesAnalytics;
use Filament\Widgets\ChartWidget;

class BusyHoursChart extends ChartWidget
{
    protected static ?int $sort = 4;

    public ?string $filter = '7';

    public function getHeading(): ?string
    {
        return 'Pool table busy hours';
    }

    public function getDescription(): ?string
    {
        return 'Average occupancy by hour — fill quiet hours with a happy-hour rate.';
    }

    protected function getFilters(): ?array
    {
        return ['7' => 'Last 7 days', '30' => 'Last 30 days'];
    }

    protected function getType(): string
    {
        return 'bar';
    }

    protected function getData(): array
    {
        $hours = SalesAnalytics::lastDays((int) ($this->filter ?: 7))->busyHours();

        return [
            'datasets' => [[
                'label' => 'Occupancy %',
                'data' => array_values($hours),
                'backgroundColor' => array_map(fn ($v) => $v >= 75 ? '#0E6B4A' : ($v >= 40 ? '#5FA383' : '#C4DCCF'), array_values($hours)),
                'borderRadius' => 3,
            ]],
            'labels' => array_map(fn ($h) => date('g A', mktime($h, 0)), array_keys($hours)),
        ];
    }

    protected function getOptions(): array
    {
        return [
            'scales' => ['y' => ['beginAtZero' => true, 'max' => 100], 'x' => ['grid' => ['display' => false]]],
            'plugins' => ['legend' => ['display' => false]],
        ];
    }
}
