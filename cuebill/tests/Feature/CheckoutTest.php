<?php

namespace Tests\Feature;

use App\Models\BusinessSetting;
use App\Models\Invoice;
use App\Models\MenuItem;
use App\Models\RestaurantTable;
use App\Models\User;
use App\Services\CheckoutService;
use App\Services\TableSessionService;
use Database\Seeders\DatabaseSeeder;
use Database\Seeders\DemoSalesSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CheckoutTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        BusinessSetting::current()->update(['upi_id' => 'example@upi', 'gstin' => '15AAAAA0000A1Z5', 'pool_rate_per_hour' => 200]);
    }

    public function test_pool_table_checkout_creates_invoice_and_frees_table(): void
    {
        $this->travelTo(now()->setTime(20, 0));
        $table = RestaurantTable::query()->where('type', 'pool')->first();
        $tables = app(TableSessionService::class);
        $session = $tables->openFor($table);
        $tables->startTimer($session);
        $tables->addItem($session, MenuItem::query()->where('name', 'Chicken momo (8 pc)')->first(), 2);
        $tables->addItem($session, MenuItem::query()->where('name', 'Cold coffee')->first(), 2);
        $tables->addItem($session, MenuItem::query()->where('name', 'French fries')->first());

        $this->travel(84)->minutes();

        $invoice = app(CheckoutService::class)->complete($session->fresh(), ['payment_method' => 'upi']);

        $this->assertSame('INV-00001', $invoice->number);
        $this->assertSame(90, $invoice->pool_billed_minutes);
        $this->assertSame(300.0, $invoice->pool_amount);
        $this->assertSame(530.0, $invoice->items_subtotal);
        $this->assertSame(911.0, $invoice->total);
        $this->assertSame('Your Restaurant Name', $invoice->business['name']);
        $this->assertSame('closed', $session->fresh()->status);
        $this->assertSame(2, BusinessSetting::current()->next_invoice_number);
        $this->assertStringContainsString('<svg', $invoice->toReceipt()['qr_svg']);
    }

    public function test_pages_print_pdf_and_exports_work(): void
    {
        $this->seed(DemoSalesSeeder::class);
        $user = User::query()->first();
        $invoice = Invoice::query()->latest('id')->first();

        $this->actingAs($user);
        foreach (['/admin', '/admin/pos', '/admin/reports', '/admin/business-settings', '/admin/invoices', '/admin/menu-items', '/admin/restaurant-tables', '/admin/categories'] as $url) {
            $this->get($url)->assertOk();
        }
        $this->get(route('invoices.print', $invoice))->assertOk()->assertSee($invoice->number);
        $this->get(route('invoices.print', ['invoice' => $invoice, 'format' => 'a4']))->assertOk();
        $this->get(route('invoices.pdf', $invoice))->assertOk()->assertHeader('content-type', 'application/pdf');
        $this->get(route('exports.invoices'))->assertOk();
        $this->get(route('exports.items'))->assertOk();
        $this->get(route('exports.daily'))->assertOk();
    }

    public function test_guests_are_sent_to_login(): void
    {
        $this->get('/admin/pos')->assertRedirect();
        $this->get(route('exports.invoices'))->assertRedirect(route('filament.admin.auth.login'));
    }
}
