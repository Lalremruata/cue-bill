<x-filament-panels::page>
    @php
        $inr = fn ($v) => \App\Support\Billing::inr((float) $v);
    @endphp

    <form wire:submit="save" class="cb-settings">
        <div class="cb-settings-main">

            <x-filament::section heading="Restaurant details" description="Printed at the top of every invoice.">
                <div class="cb-logo-row">
                    <div class="cb-logo">
                        @if ($logoUrl)
                            <img src="{{ $logoUrl }}" alt="Logo">
                        @else
                            <x-filament::icon icon="heroicon-o-photo" class="cb-logo-icon" />
                        @endif
                    </div>
                    <div class="cb-field">
                        <span class="cb-label">Logo (optional, PNG/JPG up to 1 MB)</span>
                        <input type="file" accept="image/png,image/jpeg" wire:model="logo" class="cb-file">
                        @if ($logoUrl && ! $logo)
                            <button type="button" wire:click="removeLogo" class="cb-link cb-sm">Remove logo</button>
                        @endif
                        @error('logo')<span class="cb-error">{{ $message }}</span>@enderror
                    </div>
                </div>

                <div class="cb-grid">
                    @foreach ([
                        ['name', 'Restaurant name', 'text', 'cb-span'],
                        ['address', 'Address', 'text', 'cb-span'],
                        ['city', 'City', 'text', ''],
                        ['state', 'State', 'text', ''],
                        ['pin', 'PIN code', 'text', ''],
                        ['phone', 'Phone', 'tel', ''],
                        ['email', 'Email (optional)', 'email', ''],
                    ] as [$key, $label, $type, $class])
                        <label class="cb-field {{ $class }}">
                            <span class="cb-label">{{ $label }}</span>
                            <x-filament::input.wrapper :valid="! $errors->has('data.'.$key)">
                                <x-filament::input :type="$type" wire:model.live.debounce.500ms="data.{{ $key }}" />
                            </x-filament::input.wrapper>
                            @error('data.'.$key)<span class="cb-error">{{ $message }}</span>@enderror
                        </label>
                    @endforeach
                </div>
            </x-filament::section>

            <x-filament::section heading="Tax & invoice">
                <div class="cb-grid">
                    <label class="cb-field">
                        <span class="cb-label">GSTIN</span>
                        <x-filament::input.wrapper :valid="! $errors->has('data.gstin')">
                            <x-filament::input type="text" maxlength="15" wire:model.live.debounce.500ms="data.gstin" style="text-transform: uppercase" />
                        </x-filament::input.wrapper>
                        @error('data.gstin')
                            <span class="cb-error">{{ $message }}</span>
                        @else
                            @if (filled($data['gstin'] ?? null))
                                <span class="cb-sm {{ $gstOk ? 'cb-ok' : 'cb-warn' }}">{{ $gstOk ? '✓ Valid format · state code '.substr($data['gstin'], 0, 2) : 'Should be 15 characters, e.g. 15ABCDE1234F1Z5' }}</span>
                            @endif
                        @enderror
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">FSSAI licence no. (optional)</span>
                        <x-filament::input.wrapper :valid="! $errors->has('data.fssai')"><x-filament::input type="text" wire:model.blur="data.fssai" /></x-filament::input.wrapper>
                        @error('data.fssai')<span class="cb-error">{{ $message }}</span>@enderror
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">Invoice number prefix</span>
                        <x-filament::input.wrapper><x-filament::input type="text" wire:model.live.debounce.500ms="data.invoice_prefix" /></x-filament::input.wrapper>
                        <span class="cb-sm cb-muted">Next invoice: <strong>{{ $nextNumber }}</strong></span>
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">Next invoice number</span>
                        <x-filament::input.wrapper :valid="! $errors->has('data.next_invoice_number')"><x-filament::input type="number" min="1" wire:model.live.debounce.500ms="data.next_invoice_number" /></x-filament::input.wrapper>
                        @error('data.next_invoice_number')<span class="cb-error">{{ $message }}</span>@enderror
                    </label>
                    <label class="cb-field cb-span">
                        <span class="cb-label">Footer message</span>
                        <x-filament::input.wrapper><x-filament::input type="text" wire:model.live.debounce.500ms="data.invoice_footer" /></x-filament::input.wrapper>
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">GST on food &amp; drinks</span>
                        <x-filament::input.wrapper suffix="%"><x-filament::input type="number" step="0.01" wire:model.blur="data.gst_food_rate" /></x-filament::input.wrapper>
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">GST on pool table time</span>
                        <x-filament::input.wrapper suffix="%"><x-filament::input type="number" step="0.01" wire:model.blur="data.gst_pool_rate" /></x-filament::input.wrapper>
                    </label>
                </div>
                <p class="cb-sm cb-muted">Prices are entered without GST; GST is added on the bill. Confirm the rates for your business with your CA.</p>
            </x-filament::section>

            <x-filament::section heading="UPI payments" description="Each invoice gets a QR with the exact bill amount and invoice number — the customer scans and confirms.">
                <label class="cb-check">
                    <x-filament::input.checkbox wire:model.live="data.show_upi_qr" />
                    <span>Print UPI QR on invoices paid by UPI or Split</span>
                </label>
                <div class="cb-grid">
                    <label class="cb-field">
                        <span class="cb-label">UPI ID (VPA)</span>
                        <x-filament::input.wrapper :valid="! $errors->has('data.upi_id')">
                            <x-filament::input type="text" placeholder="name@bank" wire:model.live.debounce.500ms="data.upi_id" />
                        </x-filament::input.wrapper>
                        @error('data.upi_id')
                            <span class="cb-error">{{ $message }}</span>
                        @else
                            @if (filled($data['upi_id'] ?? null))
                                <span class="cb-sm {{ $upiOk ? 'cb-ok' : 'cb-warn' }}">{{ $upiOk ? '✓ Looks like a valid UPI ID' : 'Enter a UPI ID like name@okhdfcbank' }}</span>
                            @endif
                        @enderror
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">Payee name shown in UPI apps</span>
                        <x-filament::input.wrapper><x-filament::input type="text" wire:model.live.debounce.500ms="data.upi_payee_name" :placeholder="$data['name'] ?? ''" /></x-filament::input.wrapper>
                    </label>
                </div>
            </x-filament::section>

            <x-filament::section heading="Pool table rates">
                <div class="cb-grid">
                    <label class="cb-field">
                        <span class="cb-label">Rate per hour</span>
                        <x-filament::input.wrapper prefix="₹"><x-filament::input type="number" min="0" wire:model.blur="data.pool_rate_per_hour" /></x-filament::input.wrapper>
                        <span class="cb-sm cb-muted">A table can have its own rate under Tables.</span>
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">Bill in blocks of</span>
                        <x-filament::input.wrapper>
                            <x-filament::input.select wire:model.blur="data.billing_block_minutes">
                                <option value="1">Per minute</option><option value="5">5 minutes</option><option value="10">10 minutes</option>
                                <option value="15">15 minutes</option><option value="30">30 minutes</option><option value="60">1 hour</option>
                            </x-filament::input.select>
                        </x-filament::input.wrapper>
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">Minimum charge</span>
                        <x-filament::input.wrapper suffix="min"><x-filament::input type="number" min="0" wire:model.blur="data.minimum_minutes" /></x-filament::input.wrapper>
                    </label>
                    <label class="cb-field">
                        <span class="cb-label">Running cost per hour</span>
                        <x-filament::input.wrapper prefix="₹"><x-filament::input type="number" min="0" wire:model.blur="data.pool_cost_per_hour" /></x-filament::input.wrapper>
                        <span class="cb-sm cb-muted">Electricity, cloth, cues — used for pool profit.</span>
                    </label>
                </div>
                <label class="cb-check">
                    <x-filament::input.checkbox wire:model.live="data.happy_hour_enabled" />
                    <span>Happy-hour rate</span>
                </label>
                @if ($data['happy_hour_enabled'] ?? false)
                    <div class="cb-grid cb-grid-3">
                        <label class="cb-field">
                            <span class="cb-label">Happy-hour rate</span>
                            <x-filament::input.wrapper prefix="₹"><x-filament::input type="number" min="0" wire:model.blur="data.happy_hour_rate" /></x-filament::input.wrapper>
                        </label>
                        <label class="cb-field">
                            <span class="cb-label">From</span>
                            <x-filament::input.wrapper><x-filament::input type="time" wire:model.blur="data.happy_hour_start" /></x-filament::input.wrapper>
                        </label>
                        <label class="cb-field">
                            <span class="cb-label">To</span>
                            <x-filament::input.wrapper :valid="! $errors->has('data.happy_hour_end')"><x-filament::input type="time" wire:model.blur="data.happy_hour_end" /></x-filament::input.wrapper>
                            @error('data.happy_hour_end')<span class="cb-error">Must be after the start time</span>@enderror
                        </label>
                    </div>
                    <p class="cb-sm cb-muted">The rate is fixed when the timer starts.</p>
                @endif
            </x-filament::section>

            <x-filament::section heading="Data & backup">
                <p class="cb-sm">All sales are stored in the database on this computer and keep working without internet.</p>
                <div class="cb-order-actions">
                    <x-filament::button tag="a" color="gray" icon="heroicon-m-arrow-down-tray" :href="route('backup.download')">Download backup</x-filament::button>
                </div>
                <p class="cb-sm cb-muted">Copy the backup to a USB drive or Google Drive regularly. To restore, replace <code>database/database.sqlite</code> with a backup file while the app is closed.</p>
            </x-filament::section>

            <div class="cb-sticky-save">
                <x-filament::button type="submit" icon="heroicon-m-check" wire:loading.attr="disabled">Save changes</x-filament::button>
            </div>
        </div>

        <aside class="cb-settings-preview" aria-label="Receipt preview">
            <span class="cb-label">Receipt preview · updates as you type</span>
            <div class="cb-preview">
                <div class="cb-paper is-roll rc" style="text-align: center;">
                    @if ($logoUrl)<img src="{{ $logoUrl }}" alt="" style="max-height: 48px; max-width: 150px; margin: 0 auto 4px; display: block;">@endif
                    <div class="name">{{ $data['name'] ?? '' }}</div>
                    @if (filled($data['address'] ?? null))<div class="muted">{{ $data['address'] }}</div>@endif
                    <div class="muted">{{ collect([$data['city'] ?? null, trim(($data['state'] ?? '').' '.($data['pin'] ?? ''))])->filter()->implode(', ') }}</div>
                    @if (filled($data['phone'] ?? null))<div class="muted">Ph: {{ $data['phone'] }}</div>@endif
                    @if (filled($data['gstin'] ?? null))<div class="muted">GSTIN: {{ $data['gstin'] }}</div>@endif
                    @if (filled($data['fssai'] ?? null))<div class="muted">FSSAI: {{ $data['fssai'] }}</div>@endif
                    <div class="title">TAX INVOICE</div>
                    <table class="dash" style="margin-top: 8px;"><tr><td style="text-align: left; padding-top: 6px;">{{ $nextNumber }}</td><td class="r" style="padding-top: 6px;">Sample bill</td></tr></table>
                    <table class="solid total"><tr><td style="text-align: left;">TOTAL</td><td class="r">{{ $inr($sampleAmount) }}</td></tr></table>
                    @if ($qrSvg)
                        <div class="qr" style="margin-top: 10px;">
                            <img src="data:image/svg+xml;base64,{{ base64_encode($qrSvg) }}" alt="Sample UPI QR code">
                            <div><strong>Scan to pay {{ $inr($sampleAmount) }} with any UPI app</strong></div>
                            <div class="small muted">{{ $data['upi_id'] }}</div>
                        </div>
                    @endif
                    @if (filled($data['invoice_footer'] ?? null))<div class="muted" style="margin-top: 8px;">{{ $data['invoice_footer'] }}</div>@endif
                </div>
            </div>
        </aside>
    </form>

    @include('invoices.partials.receipt-styles')
</x-filament-panels::page>
