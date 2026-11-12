@php
    use App\Support\Billing;
    $b = $r['business'];
    $money = fn ($v) => number_format((float) $v, 2);
    $logo = null;
    if (! empty($b['logo_path']) && file_exists(storage_path('app/public/'.$b['logo_path']))) {
        $file = storage_path('app/public/'.$b['logo_path']);
        $logo = 'data:'.mime_content_type($file).';base64,'.base64_encode(file_get_contents($file));
    }
    $qrSrc = $r['qr_svg'] ? 'data:image/svg+xml;base64,'.base64_encode($r['qr_svg']) : null;
@endphp
<div class="rc {{ $format === 'a4' ? 'a4' : 'roll' }}">
    <table>
        <tr><td class="c">
            @if ($logo)<img src="{{ $logo }}" alt="" style="max-height: 56px; max-width: 160px; margin-bottom: 4px;"><br>@endif
            <div class="name">{{ $b['name'] ?? '' }}</div>
            @if (! empty($b['address']))<div class="muted">{{ $b['address'] }}</div>@endif
            <div class="muted">{{ collect([$b['city'] ?? null, trim(($b['state'] ?? '').' '.($b['pin'] ?? ''))])->filter()->implode(', ') }}</div>
            @if (! empty($b['phone']))<div class="muted">Ph: {{ $b['phone'] }}</div>@endif
            @if (! empty($b['gstin']))<div class="muted">GSTIN: {{ $b['gstin'] }}</div>@endif
            @if (! empty($b['fssai']))<div class="muted">FSSAI: {{ $b['fssai'] }}</div>@endif
            <div class="title">TAX INVOICE @if ($r['draft'])<span class="draft">PREVIEW</span>@endif</div>
        </td></tr>
    </table>

    <table class="dash" style="margin-top: 8px;">
        <tr><td style="padding-top: 6px;">Invoice: <strong>{{ $r['number'] }}</strong></td><td class="r" style="padding-top: 6px;">{{ $r['date']->format('d-m-Y g:i A') }}</td></tr>
        <tr><td>Table: {{ $r['table'] }}</td><td class="r">Paid by: {{ $r['payment'] }}</td></tr>
        @if ($r['customer'] || $r['phone'])
            <tr><td colspan="2">Customer: {{ trim(($r['customer'] ?? '').' '.($r['phone'] ? '· '.$r['phone'] : ''), ' ·') }}</td></tr>
        @endif
    </table>

    <table class="items" style="margin-top: 6px;">
        <thead><tr><th style="text-align: left;">Item</th><th class="c">Qty</th><th class="r">Rate</th><th class="r">Amount</th></tr></thead>
        <tbody>
            @foreach ($r['lines'] as $line)
                <tr>
                    <td>{{ $line['name'] }}@if ($line['note'])<br><span class="small muted">{{ $line['note'] }}</span>@endif</td>
                    <td class="c">{{ $line['qty'] }}</td>
                    <td class="r">{{ $money($line['rate']) }}</td>
                    <td class="r">{{ $money($line['amount']) }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>

    <table class="dash" style="margin-top: 4px;">
        <tr><td style="padding-top: 6px;">Subtotal</td><td class="r" style="padding-top: 6px;">{{ $money($r['subtotal']) }}</td></tr>
        @if ($r['discount'] > 0)
            <tr><td>Discount ({{ rtrim(rtrim(number_format($r['discount_percent'], 2), '0'), '.') }}%)</td><td class="r">-{{ $money($r['discount']) }}</td></tr>
        @endif
        @if ($r['gst_pool'] > 0)
            <tr class="muted"><td>CGST {{ $r['gst_pool_rate'] / 2 }}% + SGST {{ $r['gst_pool_rate'] / 2 }}% (pool table)</td><td class="r">{{ $money($r['gst_pool']) }}</td></tr>
        @endif
        @if ($r['gst_food'] > 0)
            <tr class="muted"><td>CGST {{ $r['gst_food_rate'] / 2 }}% + SGST {{ $r['gst_food_rate'] / 2 }}% (food &amp; drinks)</td><td class="r">{{ $money($r['gst_food']) }}</td></tr>
        @endif
        @if (abs($r['round_off']) > 0)
            <tr class="muted"><td>Round off</td><td class="r">{{ $money($r['round_off']) }}</td></tr>
        @endif
    </table>
    <table class="solid total" style="margin-top: 4px;">
        <tr><td>TOTAL</td><td class="r">{{ Billing::inr($r['total']) }}</td></tr>
    </table>
    @if ($r['cash_received'])
        <table class="small muted"><tr><td>Cash received {{ Billing::inr($r['cash_received']) }}</td><td class="r">Change {{ Billing::inr(max(0, $r['cash_received'] - $r['total'])) }}</td></tr></table>
    @endif

    @if ($qrSrc)
        <table style="margin-top: 10px;"><tr><td class="c qr">
            <img src="{{ $qrSrc }}" alt="UPI QR code to pay {{ Billing::inr($r['total']) }}"><br>
            <strong>Scan to pay {{ Billing::inr($r['total']) }} with any UPI app</strong><br>
            <span class="small muted">{{ $r['upi_id'] }}</span>
        </td></tr></table>
    @endif

    @if (! empty($b['footer']))
        <table style="margin-top: 8px;"><tr><td class="c muted">{{ $b['footer'] }}</td></tr></table>
    @endif
</div>
