<?php

namespace App\Filament\Widgets;

use App\Services\SalesAnalytics;
use Filament\Widgets\ChartWidget;

class ProfitMixChart extends ChartWidget
{
    protected static ?int $sort = 3;

    public ?string $filter = '30';

    public function getHeading(): ?string
    {
        return 'Where profit comes from';
    }

    public function getDescription(): ?string
    {
        $mix = SalesAnalytics::lastDays((int) ($this->filter ?: 30))->mix()->filter(fn ($m) => $m['revenue'] > 0);

        return $mix->map(fn ($m) => $m['name'].' '.round($m['margin']).'% margin')->implode(' · ') ?: 'No sales yet.';
    }

    protected function getFilters(): ?array
    {
        return ['7' => 'Last 7 days', '30' => 'Last 30 days', '90' => 'Last 90 days'];
    }

    protected function getType(): string
    {
        return 'doughnut';
    }

    protected function getData(): array
    {
        $mix = SalesAnalytics::lastDays((int) ($this->filter ?: 30))->mix();

        return [
            'datasets' => [[
                'label' => 'Profit (₹)',
                'data' => $mix->pluck('profit')->map(fn ($v) => max(0, $v))->all(),
                'backgroundColor' => ['#0E6B4A', '#D08A2E', '#9CC5B0', '#E9C98F'],
                'borderWidth' => 0,
            ]],
            'labels' => $mix->pluck('name')->all(),
        ];
    }

    protected function getOptions(): array
    {
        return [
            'scales' => ['x' => ['display' => false], 'y' => ['display' => false]],
            'plugins' => ['legend' => ['position' => 'bottom']],
            'cutout' => '62%',
        ];
    }
}
