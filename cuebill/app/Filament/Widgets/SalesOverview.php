<?php

namespace App\Filament\Widgets;

use App\Services\SalesAnalytics;
use App\Support\Billing;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class SalesOverview extends StatsOverviewWidget
{
    protected static ?int $sort = 1;

    protected function getColumns(): int
    {
        return 4;
    }

    protected function getStats(): array
    {
        $now = SalesAnalytics::lastDays(7);
        $prev = $now->previousPeriod();
        $a = $now->summary();
        $b = $prev->summary();
        $daily = $now->daily();

        $delta = function (float $cur, float $old, string $suffix = '%') {
            if ($old == 0.0) {
                return [$cur > 0 ? 'New this week' : 'No sales yet', 'heroicon-m-minus', 'gray'];
            }
            $pct = round(($cur - $old) / abs($old) * 100, 1);

            return [($pct >= 0 ? '+' : '').$pct.$suffix.' vs previous 7 days', $pct >= 0 ? 'heroicon-m-arrow-trending-up' : 'heroicon-m-arrow-trending-down', $pct >= 0 ? 'success' : 'danger'];
        };

        [$d1, $i1, $c1] = $delta($a['collected'], $b['collected']);
        [$d2, $i2, $c2] = $delta($a['profit'], $b['profit']);
        $marginDiff = round($a['margin'] - $b['margin'], 1);
        [$d4, $i4, $c4] = $delta($a['pool_hours'], $b['pool_hours']);

        return [
            Stat::make('Sales (last 7 days)', Billing::inr($a['collected']))
                ->description($d1)->descriptionIcon($i1)->color($c1)
                ->chart($daily->pluck('collected')->all()),
            Stat::make('Gross profit', Billing::inr($a['profit']))
                ->description($d2)->descriptionIcon($i2)->color($c2)
                ->chart($daily->pluck('profit')->all()),
            Stat::make('Profit margin', $a['margin'].'%')
                ->description(($marginDiff >= 0 ? '+' : '').$marginDiff.' pts vs previous 7 days')
                ->descriptionIcon($marginDiff >= 0 ? 'heroicon-m-arrow-trending-up' : 'heroicon-m-arrow-trending-down')
                ->color($marginDiff >= 0 ? 'success' : 'danger'),
            Stat::make('Pool table hours', $a['pool_hours'].' h')
                ->description($now->poolOccupancy().'% occupancy · '.$d4)->descriptionIcon($i4)->color($c4)
                ->chart($daily->pluck('pool_hours')->all()),
        ];
    }
}
