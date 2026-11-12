<?php

namespace Database\Seeders;

use App\Models\BusinessSetting;
use App\Models\Category;
use App\Models\RestaurantTable;
use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        User::query()->firstOrCreate(
            ['email' => 'admin@cuebill.local'],
            ['name' => 'Admin', 'password' => 'password'], // change after first login
        );

        BusinessSetting::current()->update([
            'name' => 'Your Restaurant Name',
            'address' => 'Street, Locality',
            'city' => 'Aizawl',
            'state' => 'Mizoram',
            'pin' => '796001',
            'invoice_prefix' => 'INV-',
            'invoice_footer' => 'Thank you! Come back for another frame.',
        ]);

        $menu = [
            ['Food', 'food', [
                ['Chicken momo (8 pc)', 46, 120], ['Pork chowmein', 72, 150], ['Veg thali', 98, 180],
                ['Pork ribs', 243, 320], ['Grilled fish platter', 312, 380],
            ]],
            ['Snacks', 'snacks', [
                ['French fries', 29, 90], ['Loaded nachos', 70, 160], ['Chicken wings (6)', 118, 220], ['Veg club sandwich', 77, 130],
            ]],
            ['Drinks', 'drinks', [
                ['Cold coffee', 30, 100], ['Fresh lime soda', 16, 60], ['Coke (300 ml)', 30, 40],
                ['Masala tea', 8, 30], ['Oreo shake', 55, 140], ['Energy drink (can)', 99, 125], ['Hot chocolate', 54, 120],
            ]],
        ];

        foreach ($menu as $i => [$name, $type, $items]) {
            $category = Category::query()->firstOrCreate(['name' => $name], ['type' => $type, 'sort' => $i]);
            foreach ($items as [$item, $cost, $price]) {
                $category->menuItems()->firstOrCreate(['name' => $item], ['cost_price' => $cost, 'price' => $price]);
            }
        }

        $tables = [
            ['Pool Table 1', 'pool'], ['Pool Table 2', 'pool'],
            ['Table 1', 'dining'], ['Table 2', 'dining'], ['Table 3', 'dining'], ['Table 4', 'dining'], ['Table 5', 'dining'],
            ['Takeaway', 'takeaway'],
        ];
        foreach ($tables as $sort => [$name, $type]) {
            RestaurantTable::query()->firstOrCreate(['name' => $name], ['type' => $type, 'sort' => $sort]);
        }
    }
}
