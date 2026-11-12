<?php

namespace App\Filament\Resources\Invoices\Pages;

use App\Filament\Resources\Invoices\InvoiceResource;
use Filament\Actions\Action;
use Filament\Resources\Pages\ListRecords;

class ListInvoices extends ListRecords
{
    protected static string $resource = InvoiceResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Action::make('export')->label('Export last 30 days to Excel')->icon('heroicon-m-table-cells')
                ->url(route('exports.invoices', ['from' => now()->subDays(29)->toDateString(), 'to' => now()->toDateString()])),
        ];
    }
}
