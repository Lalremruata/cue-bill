<?php

namespace App\Filament\Pages;

use App\Models\Invoice;
use App\Services\SalesAnalytics;
use App\Support\Billing;
use BackedEnum;
use Carbon\CarbonImmutable;
use Filament\Pages\Page;
use Livewire\Attributes\Url;
use UnitEnum;

class Reports extends Page
{
    protected string $view = 'filament.pages.reports';

    protected static string|BackedEnum|null $navigationIcon = 'heroicon-o-chart-bar';

    protected static ?string $navigationLabel = 'Reports';

    protected static string|UnitEnum|null $navigationGroup = 'Sales';

    protected static ?int $navigationSort = 3;

    #[Url]
    public string $from = '';

    #[Url]
    public string $to = '';

    #[Url]
    public string $category = '';

    #[Url]
    public string $payment = '';

    #[Url]
    public string $tab = 'items';

    public string $sort = 'profit';

    public function getTitle(): string
    {
        return 'Sales reports';
    }

    public function mount(): void
    {
        $this->from = $this->from ?: now()->subDays(29)->toDateString();
        $this->to = $this->to ?: now()->toDateString();
    }

    public function preset(int $days): void
    {
        $this->to = now()->toDateString();
        $this->from = now()->subDays($days - 1)->toDateString();
    }

    protected function analytics(): SalesAnalytics
    {
        $from = rescue(fn () => CarbonImmutable::parse($this->from), CarbonImmutable::now()->subDays(29), false);
        $to = rescue(fn () => CarbonImmutable::parse($this->to), CarbonImmutable::now(), false);
        if ($to < $from) {
            [$from, $to] = [$to, $from];
        }

        return new SalesAnalytics($from, $to, $this->payment ?: null);
    }

    protected function getViewData(): array
    {
        $a = $this->analytics();
        $query = array_filter(['from' => $a->from->toDateString(), 'to' => $a->to->toDateString(), 'payment' => $this->payment, 'category' => $this->category, 'sort' => $this->sort]);

        return [
            'summary' => $a->summary(),
            'rows' => $this->tab === 'items' ? $a->items($this->category ?: null, in_array($this->sort, ['profit', 'revenue', 'qty', 'margin']) ? $this->sort : 'profit') : collect(),
            'daily' => $this->tab === 'daily' ? $a->daily()->reverse()->values() : collect(),
            'invoices' => $this->tab === 'invoices' ? $a->invoices()->latest('paid_at')->limit(300)->get() : collect(),
            'exportUrl' => route(match ($this->tab) { 'daily' => 'exports.daily', 'invoices' => 'exports.invoices', default => 'exports.items' }, $query),
            'inr' => fn ($v) => Billing::inr((float) $v),
            'payments' => Invoice::PAYMENT_METHODS,
        ];
    }
}
