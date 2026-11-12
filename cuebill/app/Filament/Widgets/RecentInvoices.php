<?php

namespace App\Filament\Widgets;

use App\Models\Invoice;
use Filament\Widgets\Widget;

class RecentInvoices extends Widget
{
    protected static ?int $sort = 7;

    protected int|string|array $columnSpan = 'full';

    protected string $view = 'filament.widgets.recent-invoices';

    protected function getViewData(): array
    {
        return ['invoices' => Invoice::query()->latest('paid_at')->limit(8)->get()];
    }
}
