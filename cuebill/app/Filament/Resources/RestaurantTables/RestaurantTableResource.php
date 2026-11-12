<?php

namespace App\Filament\Resources\RestaurantTables;

use App\Filament\Resources\RestaurantTables\Pages\ManageRestaurantTables;
use App\Models\RestaurantTable;
use BackedEnum;
use Filament\Actions\DeleteAction;
use Filament\Actions\EditAction;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Columns\ToggleColumn;
use Filament\Tables\Table;
use UnitEnum;

class RestaurantTableResource extends Resource
{
    protected static ?string $model = RestaurantTable::class;

    protected static string|BackedEnum|null $navigationIcon = 'heroicon-o-rectangle-group';

    protected static string|UnitEnum|null $navigationGroup = 'Menu & Tables';

    protected static ?string $navigationLabel = 'Tables';

    protected static ?string $modelLabel = 'table';

    protected static ?int $navigationSort = 3;

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            TextInput::make('name')->required()->maxLength(40)->placeholder('Pool Table 1'),
            Select::make('type')->options(RestaurantTable::TYPES)->required()->default('dining')->live(),
            TextInput::make('hourly_rate')->label('Own hourly rate (optional)')->numeric()->minValue(0)->prefix('₹')
                ->helperText('Leave empty to use the rate from Business settings.')
                ->visible(fn ($get) => $get('type') === 'pool'),
            TextInput::make('sort')->numeric()->default(0),
            Toggle::make('is_active')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('sort')
            ->reorderable('sort')
            ->columns([
                TextColumn::make('name')->searchable()->weight('medium'),
                TextColumn::make('type')->badge()->formatStateUsing(fn ($state) => RestaurantTable::TYPES[$state] ?? $state)
                    ->color(fn ($state) => $state === 'pool' ? 'success' : 'gray'),
                TextColumn::make('hourly_rate')->money('INR')->placeholder('Default rate'),
                ToggleColumn::make('is_active')->label('Active'),
            ])
            ->recordActions([EditAction::make(), DeleteAction::make()]);
    }

    public static function getPages(): array
    {
        return ['index' => ManageRestaurantTables::route('/')];
    }
}
