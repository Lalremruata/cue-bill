<?php

namespace App\Filament\Resources\RestaurantTables\Pages;

use App\Filament\Resources\RestaurantTables\RestaurantTableResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ManageRecords;

class ManageRestaurantTables extends ManageRecords
{
    protected static string $resource = RestaurantTableResource::class;

    protected function getHeaderActions(): array
    {
        return [CreateAction::make()->label('Add table')];
    }
}
