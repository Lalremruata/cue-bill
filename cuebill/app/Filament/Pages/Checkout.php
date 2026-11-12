<?php

namespace App\Filament\Pages;

use App\Models\Invoice;
use App\Models\TableSession;
use App\Services\CheckoutService;
use App\Support\Billing;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Livewire\Attributes\Url;

class Checkout extends Page
{
    protected string $view = 'filament.pages.checkout';

    protected static bool $shouldRegisterNavigation = false;

    protected static ?string $slug = 'checkout';

    #[Url]
    public ?int $session = null;

    public string $paymentMethod = 'upi';

    public string $discount = '0';

    public string $customerName = '';

    public string $customerPhone = '';

    public string $cashReceived = '';

    public string $previewFormat = '80mm';

    public ?int $invoiceId = null;

    public function getTitle(): string
    {
        return $this->invoiceId ? 'Sale complete' : 'Checkout';
    }

    public function mount(): void
    {
        $session = TableSession::query()->findOrFail($this->session);
        if ($session->status !== 'open') {
            $this->invoiceId = Invoice::query()->where('table_session_id', $session->id)->value('id');
        }
    }

    public function setPayment(string $method): void
    {
        $this->paymentMethod = array_key_exists($method, Invoice::PAYMENT_METHODS) ? $method : 'cash';
    }

    public function setDiscount(string $percent): void
    {
        $this->discount = $percent;
    }

    protected function options(): array
    {
        return [
            'payment_method' => $this->paymentMethod,
            'discount_percent' => max(0, min(100, (float) $this->discount)),
            'customer_name' => trim($this->customerName),
            'customer_phone' => trim($this->customerPhone),
            'cash_received' => $this->paymentMethod === 'cash' ? $this->cashReceived : '',
        ];
    }

    public function complete(CheckoutService $checkout): void
    {
        $this->validate([
            'discount' => ['numeric', 'min:0', 'max:100'],
            'customerPhone' => ['nullable', 'regex:/^[0-9+\s-]{6,20}$/'],
            'cashReceived' => ['nullable', 'numeric', 'min:0'],
        ]);

        $invoice = $checkout->complete(TableSession::query()->findOrFail($this->session), $this->options());
        $this->invoiceId = $invoice->id;

        Notification::make()->title("Sale {$invoice->number} saved")->body(Billing::inr($invoice->total).' · '.$invoice->table_name.' is free again.')->success()->send();
    }

    protected function getViewData(): array
    {
        if ($this->invoiceId) {
            $invoice = Invoice::query()->with('items')->findOrFail($this->invoiceId);

            return ['invoice' => $invoice, 'r' => $invoice->toReceipt(), 'summary' => null];
        }

        $session = TableSession::query()->with(['table', 'items.menuItem.category'])->findOrFail($this->session);
        $service = app(CheckoutService::class);

        return [
            'invoice' => null,
            'tableSession' => $session,
            'summary' => $service->calculate($session, $this->options()),
            'r' => $service->preview($session, $this->options()),
        ];
    }
}
