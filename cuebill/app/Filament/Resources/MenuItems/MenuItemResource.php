<?php

namespace App\Filament\Resources\MenuItems;

use App\Filament\Resources\MenuItems\Pages\ManageMenuItems;
use App\Models\MenuItem;
use BackedEnum;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteAction;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Columns\TextInputColumn;
use Filament\Tables\Columns\ToggleColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Table;
use UnitEnum;

class MenuItemResource extends Resource
{
    protected static ?string $model = MenuItem::class;

    protected static string|BackedEnum|null $navigationIcon = 'heroicon-o-book-open';

    protected static string|UnitEnum|null $navigationGroup = 'Menu & Tables';

    protected static ?string $navigationLabel = 'Menu & costs';

    protected static ?int $navigationSort = 1;

    public static function form(Schema $schema): Schema
    {
        return $schema->columns(2)->components([
            TextInput::make('name')->required()->maxLength(120)->columnSpanFull(),
            Select::make('category_id')->relationship('category', 'name')->required()->preload()->searchable(),
            Toggle::make('is_active')->label('Available on the menu')->default(true)->inline(false),
            TextInput::make('cost_price')->label('Your cost')->helperText('Ingredients + packaging for one serving')
                ->numeric()->minValue(0)->prefix('₹')->required()->default(0),
            TextInput::make('price')->label('Selling price (without GST)')->numeric()->minValue(0)->prefix('₹')->required(),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('name')
            ->columns([
                TextColumn::make('name')->searchable()->sortable()->weight('medium'),
                TextColumn::make('category.name')->badge()->color('gray')->sortable(),
                TextInputColumn::make('cost_price')->label('Your cost (₹)')->type('number')->rules(['required', 'numeric', 'min:0'])->sortable()->alignEnd(),
                TextInputColumn::make('price')->label('Price (₹)')->type('number')->rules(['required', 'numeric', 'min:0'])->sortable()->alignEnd(),
                TextColumn::make('profit')->label('Profit / unit')
                    ->state(fn (MenuItem $record) => $record->price - $record->cost_price)->money('INR')->alignEnd(),
                TextColumn::make('margin')->label('Margin')
                    ->state(fn (MenuItem $record) => $record->marginPercent())
                    ->formatStateUsing(fn ($state) => round($state).'%')
                    ->badge()->color(fn ($state) => $state < 30 ? 'danger' : ($state < 50 ? 'warning' : 'success'))->alignEnd(),
                ToggleColumn::make('is_active')->label('On menu'),
            ])
            ->filters([
                SelectFilter::make('category_id')->relationship('category', 'name')->label('Category'),
                TernaryFilter::make('is_active')->label('On menu'),
            ])
            ->recordActions([EditAction::make(), DeleteAction::make()])
            ->toolbarActions([BulkActionGroup::make([DeleteBulkAction::make()])]);
    }

    public static function getPages(): array
    {
        return ['index' => ManageMenuItems::route('/')];
    }
}
