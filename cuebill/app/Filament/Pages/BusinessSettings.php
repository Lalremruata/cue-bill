<?php

namespace App\Filament\Pages;

use App\Models\BusinessSetting;
use App\Support\UpiQr;
use BackedEnum;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Illuminate\Support\Facades\Storage;
use Livewire\WithFileUploads;
use UnitEnum;

class BusinessSettings extends Page
{
    use WithFileUploads;

    protected string $view = 'filament.pages.business-settings';

    protected static string|BackedEnum|null $navigationIcon = 'heroicon-o-building-storefront';

    protected static ?string $navigationLabel = 'Business settings';

    protected static string|UnitEnum|null $navigationGroup = 'Settings';

    protected static ?int $navigationSort = 1;

    protected static ?string $slug = 'business-settings';

    /** @var array<string, mixed> */
    public array $data = [];

    public $logo = null;

    public const FIELDS = [
        'name', 'address', 'city', 'state', 'pin', 'phone', 'email', 'gstin', 'fssai',
        'invoice_prefix', 'next_invoice_number', 'invoice_footer',
        'upi_id', 'upi_payee_name', 'show_upi_qr',
        'pool_rate_per_hour', 'billing_block_minutes', 'minimum_minutes', 'pool_cost_per_hour',
        'happy_hour_enabled', 'happy_hour_rate', 'happy_hour_start', 'happy_hour_end',
        'gst_food_rate', 'gst_pool_rate',
    ];

    public function getTitle(): string
    {
        return 'Business settings';
    }

    public function mount(): void
    {
        $s = BusinessSetting::current();
        $this->data = collect(self::FIELDS)->mapWithKeys(fn ($f) => [$f => $s->{$f}])->all();
        $this->data['happy_hour_start'] = substr((string) $s->happy_hour_start, 0, 5);
        $this->data['happy_hour_end'] = substr((string) $s->happy_hour_end, 0, 5);
    }

    protected function rules(): array
    {
        return [
            'data.name' => ['required', 'string', 'max:120'],
            'data.address' => ['nullable', 'string', 'max:255'],
            'data.city' => ['nullable', 'string', 'max:80'],
            'data.state' => ['required', 'string', 'max:80'],
            'data.pin' => ['nullable', 'digits:6'],
            'data.phone' => ['nullable', 'string', 'max:30'],
            'data.email' => ['nullable', 'email'],
            'data.gstin' => ['nullable', 'regex:/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/'],
            'data.fssai' => ['nullable', 'digits:14'],
            'data.invoice_prefix' => ['nullable', 'string', 'max:20'],
            'data.next_invoice_number' => ['required', 'integer', 'min:1'],
            'data.invoice_footer' => ['nullable', 'string', 'max:160'],
            'data.upi_id' => ['nullable', 'regex:/^[A-Za-z0-9._-]{2,256}@[A-Za-z]{2,64}$/'],
            'data.upi_payee_name' => ['nullable', 'string', 'max:60'],
            'data.show_upi_qr' => ['boolean'],
            'data.pool_rate_per_hour' => ['required', 'numeric', 'min:0'],
            'data.billing_block_minutes' => ['required', 'integer', 'in:1,5,10,15,30,60'],
            'data.minimum_minutes' => ['required', 'integer', 'min:0', 'max:240'],
            'data.pool_cost_per_hour' => ['required', 'numeric', 'min:0'],
            'data.happy_hour_enabled' => ['boolean'],
            'data.happy_hour_rate' => ['required', 'numeric', 'min:0'],
            'data.happy_hour_start' => ['required', 'date_format:H:i'],
            'data.happy_hour_end' => ['required', 'date_format:H:i', 'after:data.happy_hour_start'],
            'data.gst_food_rate' => ['required', 'numeric', 'min:0', 'max:28'],
            'data.gst_pool_rate' => ['required', 'numeric', 'min:0', 'max:28'],
            'logo' => ['nullable', 'image', 'max:1024'],
        ];
    }

    protected function messages(): array
    {
        return [
            'data.gstin.regex' => 'GSTIN should be 15 characters, e.g. 15ABCDE1234F1Z5.',
            'data.upi_id.regex' => 'Enter a UPI ID like name@okhdfcbank.',
        ];
    }

    public function updatedData($value, $key): void
    {
        if ($key === 'gstin') {
            $this->data['gstin'] = strtoupper(trim((string) $value));
        }
    }

    public function save(): void
    {
        $this->validate();
        $s = BusinessSetting::current();
        $values = $this->data;
        $values['happy_hour_start'] .= ':00';
        $values['happy_hour_end'] .= ':00';

        if ($this->logo) {
            if ($s->logo_path) {
                Storage::disk('public')->delete($s->logo_path);
            }
            $values['logo_path'] = $this->logo->store('logos', 'public');
            $this->logo = null;
        }

        $s->update($values);
        Notification::make()->title('Business settings saved')->body('New invoices will use these details.')->success()->send();
    }

    public function removeLogo(): void
    {
        $s = BusinessSetting::current();
        if ($s->logo_path) {
            Storage::disk('public')->delete($s->logo_path);
            $s->update(['logo_path' => null]);
        }
    }

    protected function getViewData(): array
    {
        $d = $this->data;
        $upiOk = UpiQr::isValidUpiId($d['upi_id'] ?? null);
        $sampleAmount = 1276.0;
        $number = ($d['invoice_prefix'] ?? '').str_pad((string) ($d['next_invoice_number'] ?? 1), 5, '0', STR_PAD_LEFT);

        return [
            'gstOk' => UpiQr::isValidGstin($d['gstin'] ?? null),
            'upiOk' => $upiOk,
            'sampleAmount' => $sampleAmount,
            'nextNumber' => $number,
            'qrSvg' => $upiOk && ($d['show_upi_qr'] ?? false)
                ? UpiQr::svg($d['upi_id'], ($d['upi_payee_name'] ?? '') ?: ($d['name'] ?? ''), $sampleAmount, 'Bill '.$number)
                : null,
            'logoUrl' => $this->logo ? $this->logo->temporaryUrl() : (BusinessSetting::current()->logo_path ? Storage::disk('public')->url(BusinessSetting::current()->logo_path) : null),
        ];
    }
}
