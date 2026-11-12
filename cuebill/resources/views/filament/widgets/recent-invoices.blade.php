<x-filament-widgets::widget>
    <x-filament::section heading="Recent invoices">
        <div class="cb-scroll">
            <table class="cb-table">
                <thead><tr><th>Invoice</th><th>Time</th><th>Table</th><th>Paid by</th><th class="r">Amount</th><th class="r">Print</th></tr></thead>
                <tbody>
                    @forelse ($invoices as $inv)
                        <tr>
                            <td class="cb-num cb-strong">{{ $inv->number }}</td>
                            <td class="cb-num">{{ $inv->paid_at->format('d M, g:i A') }}</td>
                            <td>{{ $inv->table_name }}</td>
                            <td>{{ \App\Models\Invoice::PAYMENT_METHODS[$inv->payment_method] ?? $inv->payment_method }}</td>
                            <td class="r cb-num cb-strong">{{ \App\Support\Billing::inr($inv->total) }}</td>
                            <td class="r cb-actions">
                                <a class="cb-link" target="_blank" href="{{ route('invoices.print', ['invoice' => $inv, 'format' => '80mm']) }}">Receipt</a>
                                <a class="cb-link" href="{{ route('invoices.pdf', ['invoice' => $inv]) }}">PDF</a>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6" class="cb-muted">No sales yet — open a table under Tables &amp; Orders.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </x-filament::section>
</x-filament-widgets::widget>
