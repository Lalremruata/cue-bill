<x-filament-panels::page>
    @include('invoices.partials.receipt-styles')
    @php $inr = fn ($v) => \App\Support\Billing::inr((float) $v); @endphp

    <div class="cb-checkout">
        <div class="cb-checkout-form">
            @if ($invoice)
                <x-filament::section>
                    <x-slot name="heading">{{ $invoice->number }} saved</x-slot>
                    <x-slot name="description">{{ $inr($invoice->total) }} · {{ $invoice->table_name }} · {{ \App\Models\Invoice::PAYMENT_METHODS[$invoice->payment_method] }} · stored on this device</x-slot>
                    <div class="cb-btn-grid">
                        <x-filament::button tag="a" target="_blank" icon="heroicon-m-printer" :href="route('invoices.print', ['invoice' => $invoice, 'format' => '80mm'])">Print 80 mm receipt</x-filament::button>
                        <x-filament::button tag="a" target="_blank" icon="heroicon-m-printer" color="gray" :href="route('invoices.print', ['invoice' => $invoice, 'format' => 'a4'])">Print A4 invoice</x-filament::button>
                        <x-filament::button tag="a" icon="heroicon-m-arrow-down-tray" color="gray" :href="route('invoices.pdf', ['invoice' => $invoice, 'format' => 'a4'])">Save as PDF</x-filament::button>
                        <x-filament::button tag="a" icon="heroicon-m-squares-2x2" color="gray" :href="\App\Filament\Pages\Pos::getUrl()">Back to tables</x-filament::button>
                    </div>
                </x-filament::section>
            @else
                <x-filament::section>
                    <x-slot name="heading">{{ $tableSession->table->name }}</x-slot>
                    <x-slot name="description">
                        @if ($summary['billed_minutes'])
                            Played {{ \App\Support\Billing::duration($summary['played_minutes']) }}, billed {{ \App\Support\Billing::duration($summary['billed_minutes']) }} at {{ $inr($summary['rate']) }}/hr ·
                        @endif
                        {{ count($summary['items']) }} menu items
                    </x-slot>

                    <div class="cb-field">
                        <span class="cb-label">Payment method</span>
                        <div class="cb-pay-grid" role="group" aria-label="Payment method">
                            @foreach (\App\Models\Invoice::PAYMENT_METHODS as $key => $label)
                                <button type="button" wire:click="setPayment('{{ $key }}')" aria-pressed="{{ $paymentMethod === $key ? 'true' : 'false' }}"
                                        class="cb-pay {{ $paymentMethod === $key ? 'is-on' : '' }}">{{ $label }}</button>
                            @endforeach
                        </div>
                    </div>

                    <div class="cb-field">
                        <span class="cb-label">Discount</span>
                        <div class="cb-chips">
                            @foreach (['0' => 'None', '5' => '5%', '10' => '10%', '15' => '15%'] as $value => $label)
                                <button type="button" wire:click="setDiscount('{{ $value }}')" class="cb-chip {{ (float) $discount === (float) $value ? 'is-on' : '' }}">{{ $label }}</button>
                            @endforeach
                            <div style="width: 120px;">
                                <x-filament::input.wrapper suffix="%" :valid="! $errors->has('discount')">
                                    <x-filament::input type="number" min="0" max="100" step="0.5" wire:model.live.debounce.400ms="discount" aria-label="Custom discount percent" />
                                </x-filament::input.wrapper>
                            </div>
                        </div>
                        @error('discount')<p class="cb-error">{{ $message }}</p>@enderror
                    </div>

                    <div class="cb-two">
                        <label class="cb-field">
                            <span class="cb-label">Customer name (optional)</span>
                            <x-filament::input.wrapper><x-filament::input type="text" wire:model.blur="customerName" /></x-filament::input.wrapper>
                        </label>
                        <label class="cb-field">
                            <span class="cb-label">Phone (optional)</span>
                            <x-filament::input.wrapper :valid="! $errors->has('customerPhone')"><x-filament::input type="tel" wire:model.blur="customerPhone" /></x-filament::input.wrapper>
                            @error('customerPhone')<span class="cb-error">Enter a valid phone number</span>@enderror
                        </label>
                    </div>

                    @if ($paymentMethod === 'cash')
                        <label class="cb-field">
                            <span class="cb-label">Cash received</span>
                            <x-filament::input.wrapper prefix="₹"><x-filament::input type="number" min="0" wire:model.live.debounce.400ms="cashReceived" /></x-filament::input.wrapper>
                        </label>
                    @endif

                    <div class="cb-due">
                        <div class="cb-row"><span>Amount due</span><span>{{ \App\Models\Invoice::PAYMENT_METHODS[$paymentMethod] }}</span></div>
                        <div class="cb-due-amount cb-num">{{ $inr($summary['totals']['total']) }}</div>
                        @if ($paymentMethod === 'cash' && is_numeric($cashReceived) && (float) $cashReceived > 0)
                            <div class="cb-num">Return {{ $inr(max(0, (float) $cashReceived - $summary['totals']['total'])) }}</div>
                        @endif
                        @if (in_array($paymentMethod, ['upi', 'split']) && ! $r['qr_svg'])
                            <div class="cb-sm">Add a valid UPI ID in Business settings to print a payment QR.</div>
                        @endif
                    </div>

                    <div class="cb-order-actions">
                        <x-filament::button tag="a" color="gray" :href="\App\Filament\Pages\Pos::getUrl(['table' => $tableSession->restaurant_table_id])">Back</x-filament::button>
                        <x-filament::button wire:click="complete" icon="heroicon-m-check" class="cb-grow" wire:loading.attr="disabled">Complete sale</x-filament::button>
                    </div>
                </x-filament::section>
            @endif
        </div>

        <div class="cb-preview-wrap">
            <div class="cb-preview-toolbar">
                <span class="cb-label">Invoice preview</span>
                <div class="cb-chips">
                    <button type="button" wire:click="$set('previewFormat', '80mm')" class="cb-chip {{ $previewFormat === '80mm' ? 'is-on' : '' }}">80 mm receipt</button>
                    <button type="button" wire:click="$set('previewFormat', 'a4')" class="cb-chip {{ $previewFormat === 'a4' ? 'is-on' : '' }}">A4 tax invoice</button>
                </div>
            </div>
            <div class="cb-preview">
                <div class="cb-paper {{ $previewFormat === 'a4' ? 'is-a4' : 'is-roll' }}">
                    @include('invoices.partials.receipt', ['r' => $r, 'format' => $previewFormat])
                </div>
            </div>
            <p class="cb-muted cb-sm">Name, address, GSTIN and UPI ID come from <a href="{{ \App\Filament\Pages\BusinessSettings::getUrl() }}" class="cb-link">Business settings</a>.</p>
        </div>
    </div>
</x-filament-panels::page>
