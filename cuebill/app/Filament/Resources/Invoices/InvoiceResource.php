<?php

namespace App\Filament\Resources\Invoices;

use App\Filament\Resources\Invoices\Pages\ListInvoices;
use App\Models\Invoice;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Actions\ActionGroup;
use Filament\Resources\Resource;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use UnitEnum;

class InvoiceResource extends Resource
{
    protected static ?string $model = Invoice::class;

    protected static string|BackedEnum|null $navigationIcon = 'heroicon-o-receipt-percent';

    protected static string|UnitEnum|null $navigationGroup = 'Sales';

    protected static ?int $navigationSort = 2;

    protected static ?string $recordTitleAttribute = 'number';

    public static function canCreate(): bool
    {
        return false; // invoices are only created by checking out a table
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('paid_at', 'desc')
            ->columns([
                TextColumn::make('number')->searchable()->sortable()->weight('medium'),
                TextColumn::make('paid_at')->label('Date')->dateTime('d M Y, g:i A')->sortable(),
                TextColumn::make('table_name')->label('Table')->searchable(),
                TextColumn::make('customer_name')->label('Customer')->searchable()->toggleable()->placeholder('—'),
                TextColumn::make('payment_method')->label('Paid by')->badge()
                    ->formatStateUsing(fn ($state) => Invoice::PAYMENT_METHODS[$state] ?? $state),
                TextColumn::make('total')->money('INR')->sortable()->alignEnd(),
                TextColumn::make('profit')->state(fn (Invoice $record) => $record->profit())->money('INR')->alignEnd()->toggleable(),
            ])
            ->filters([
                SelectFilter::make('payment_method')->label('Paid by')->options(Invoice::PAYMENT_METHODS),
            ])
            ->recordUrl(fn (Invoice $record) => route('invoices.print', ['invoice' => $record, 'format' => '80mm', 'auto' => 0]))
            ->openRecordUrlInNewTab()
            ->recordActions([
                ActionGroup::make([
                    Action::make('receipt')->label('Print 80 mm receipt')->icon('heroicon-m-printer')
                        ->url(fn (Invoice $record) => route('invoices.print', ['invoice' => $record, 'format' => '80mm']))->openUrlInNewTab(),
                    Action::make('a4')->label('Print A4 invoice')->icon('heroicon-m-document-text')
                        ->url(fn (Invoice $record) => route('invoices.print', ['invoice' => $record, 'format' => 'a4']))->openUrlInNewTab(),
                    Action::make('pdf')->label('Save as PDF')->icon('heroicon-m-arrow-down-tray')
                        ->url(fn (Invoice $record) => route('invoices.pdf', ['invoice' => $record])),
                ]),
            ]);
    }

    public static function getPages(): array
    {
        return ['index' => ListInvoices::route('/')];
    }
}
