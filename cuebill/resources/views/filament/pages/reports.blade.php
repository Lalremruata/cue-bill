<x-filament-panels::page>
    <div class="cb-report">
        <x-filament::section class="cb-no-print">
            <div class="cb-filters">
                <label class="cb-field">
                    <span class="cb-label">From</span>
                    <x-filament::input.wrapper><x-filament::input type="date" wire:model.live="from" /></x-filament::input.wrapper>
                </label>
                <label class="cb-field">
                    <span class="cb-label">To</span>
                    <x-filament::input.wrapper><x-filament::input type="date" wire:model.live="to" /></x-filament::input.wrapper>
                </label>
                <label class="cb-field">
                    <span class="cb-label">Payment</span>
                    <x-filament::input.wrapper>
                        <x-filament::input.select wire:model.live="payment">
                            <option value="">All methods</option>
                            @foreach ($payments as $key => $label)<option value="{{ $key }}">{{ $label }}</option>@endforeach
                        </x-filament::input.select>
                    </x-filament::input.wrapper>
                </label>
                <div class="cb-chips">
                    <button type="button" wire:click="preset(1)" class="cb-chip">Today</button>
                    <button type="button" wire:click="preset(7)" class="cb-chip">7 days</button>
                    <button type="button" wire:click="preset(30)" class="cb-chip">30 days</button>
                    <button type="button" wire:click="preset(90)" class="cb-chip">90 days</button>
                </div>
                <div class="cb-filter-actions">
                    <x-filament::button color="gray" icon="heroicon-m-printer" onclick="window.print()">Print / Save PDF</x-filament::button>
                    <x-filament::button tag="a" :href="$exportUrl" icon="heroicon-m-table-cells">Export to Excel</x-filament::button>
                </div>
            </div>
        </x-filament::section>

        <div class="cb-kpis">
            @foreach ([
                ['Collected (incl. GST)', $inr($summary['collected'])],
                ['Revenue (ex GST)', $inr($summary['revenue'])],
                ['Cost', $inr($summary['cost'])],
                ['Gross profit', $inr($summary['profit'])],
                ['Margin', $summary['margin'].'%'],
                ['Invoices', number_format($summary['invoices'])],
            ] as [$label, $value])
                <div class="cb-kpi"><span class="cb-muted cb-sm">{{ $label }}</span><strong class="cb-num">{{ $value }}</strong></div>
            @endforeach
        </div>

        <x-filament::tabs class="cb-no-print">
            <x-filament::tabs.item :active="$tab === 'items'" wire:click="$set('tab', 'items')">Item performance</x-filament::tabs.item>
            <x-filament::tabs.item :active="$tab === 'daily'" wire:click="$set('tab', 'daily')">Daily sales</x-filament::tabs.item>
            <x-filament::tabs.item :active="$tab === 'invoices'" wire:click="$set('tab', 'invoices')">Invoices</x-filament::tabs.item>
        </x-filament::tabs>

        <x-filament::section>
            @if ($tab === 'items')
                <div class="cb-table-toolbar">
                    <div class="cb-chips" role="group" aria-label="Category">
                        @foreach (['' => 'All', 'pool' => 'Pool table'] + \App\Models\Category::TYPES as $key => $label)
                            <button type="button" wire:click="$set('category', '{{ $key }}')" class="cb-chip {{ $category === (string) $key ? 'is-on' : '' }}">{{ $label }}</button>
                        @endforeach
                    </div>
                    <label class="cb-inline">
                        <span class="cb-sm">Sort by</span>
                        <x-filament::input.wrapper>
                            <x-filament::input.select wire:model.live="sort">
                                <option value="profit">Profit</option><option value="revenue">Revenue</option><option value="qty">Qty sold</option><option value="margin">Margin %</option>
                            </x-filament::input.select>
                        </x-filament::input.wrapper>
                    </label>
                </div>
                <p class="cb-legend-text cb-sm">
                    <span class="cb-badge is-star">Star</span> sells well, margin ≥ 60% ·
                    <span class="cb-badge is-steady">Steady</span> fine on both ·
                    <span class="cb-badge is-slow">Slow</span> few sold ·
                    <span class="cb-badge is-loss">Loss risk</span> margin under 30%
                </p>
                <div class="cb-scroll">
                    <table class="cb-table">
                        <thead><tr><th>Item</th><th>Category</th><th class="r">Qty</th><th class="r">Revenue</th><th class="r">Cost</th><th class="r">Profit</th><th style="width: 170px;">Margin</th><th>Rating</th></tr></thead>
                        <tbody>
                            @forelse ($rows as $r)
                                <tr>
                                    <td class="cb-strong">{{ $r['name'] }}</td>
                                    <td class="cb-muted">{{ $r['category'] }}</td>
                                    <td class="r cb-num">{{ $r['qty'] }}{{ $r['unit'] ? ' '.$r['unit'] : '' }}</td>
                                    <td class="r cb-num">{{ $inr($r['revenue']) }}</td>
                                    <td class="r cb-num cb-muted">{{ $inr($r['cost']) }}</td>
                                    <td class="r cb-num cb-strong">{{ $inr($r['profit']) }}</td>
                                    <td>
                                        <div class="cb-bar-cell">
                                            <div class="cb-bar"><div class="cb-bar-fill {{ $r['margin'] < 30 ? 'is-bad' : ($r['margin'] < 50 ? 'is-mid' : 'is-good') }}" style="width: {{ max(0, min(100, $r['margin'])) }}%"></div></div>
                                            <span class="cb-num cb-sm">{{ round($r['margin']) }}%</span>
                                        </div>
                                    </td>
                                    <td><span class="cb-badge is-{{ ['Star' => 'star', 'Steady' => 'steady', 'Slow' => 'slow', 'Loss risk' => 'loss'][$r['rating']] }}">{{ $r['rating'] }}</span></td>
                                </tr>
                            @empty
                                <tr><td colspan="8" class="cb-muted">No sales in this period.</td></tr>
                            @endforelse
                        </tbody>
                    </table>
                </div>
            @elseif ($tab === 'daily')
                <div class="cb-scroll">
                    <table class="cb-table">
                        <thead><tr><th>Date</th><th class="r">Invoices</th><th class="r">Pool hours</th><th class="r">Pool</th><th class="r">Food</th><th class="r">Drinks</th><th class="r">Snacks</th><th class="r">Collected</th><th class="r">Profit</th><th class="r">Margin</th></tr></thead>
                        <tbody>
                            @foreach ($daily as $d)
                                <tr>
                                    <td class="cb-num cb-strong">{{ $d['date']->format('D, d M') }}</td>
                                    <td class="r cb-num">{{ $d['invoices'] }}</td>
                                    <td class="r cb-num">{{ $d['pool_hours'] }}</td>
                                    <td class="r cb-num">{{ $inr($d['pool']) }}</td>
                                    <td class="r cb-num">{{ $inr($d['food']) }}</td>
                                    <td class="r cb-num">{{ $inr($d['drinks']) }}</td>
                                    <td class="r cb-num">{{ $inr($d['snacks']) }}</td>
                                    <td class="r cb-num cb-strong">{{ $inr($d['collected']) }}</td>
                                    <td class="r cb-num">{{ $inr($d['profit']) }}</td>
                                    <td class="r cb-num">{{ $d['margin'] }}%</td>
                                </tr>
                            @endforeach
                        </tbody>
                    </table>
                </div>
            @else
                <div class="cb-scroll">
                    <table class="cb-table">
                        <thead><tr><th>Invoice</th><th>Date &amp; time</th><th>Table</th><th>Paid by</th><th class="r">Amount</th><th class="r cb-no-print">Actions</th></tr></thead>
                        <tbody>
                            @forelse ($invoices as $inv)
                                <tr>
                                    <td class="cb-num cb-strong">{{ $inv->number }}</td>
                                    <td class="cb-num">{{ $inv->paid_at->format('d M, g:i A') }}</td>
                                    <td>{{ $inv->table_name }}</td>
                                    <td>{{ $payments[$inv->payment_method] ?? $inv->payment_method }}</td>
                                    <td class="r cb-num cb-strong">{{ $inr($inv->total) }}</td>
                                    <td class="r cb-no-print cb-actions">
                                        <a class="cb-link" target="_blank" href="{{ route('invoices.print', ['invoice' => $inv, 'format' => '80mm']) }}">Reprint</a>
                                        <a class="cb-link" target="_blank" href="{{ route('invoices.print', ['invoice' => $inv, 'format' => 'a4']) }}">A4</a>
                                        <a class="cb-link" href="{{ route('invoices.pdf', ['invoice' => $inv]) }}">PDF</a>
                                    </td>
                                </tr>
                            @empty
                                <tr><td colspan="6" class="cb-muted">No invoices in this period.</td></tr>
                            @endforelse
                        </tbody>
                    </table>
                    @if ($invoices->count() === 300)<p class="cb-sm cb-muted">Showing the latest 300 — export to Excel for all.</p>@endif
                </div>
            @endif
        </x-filament::section>
    </div>
</x-filament-panels::page>
