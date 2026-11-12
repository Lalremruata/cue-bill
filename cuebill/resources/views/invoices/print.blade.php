<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $r['number'] }}</title>
    @include('invoices.partials.receipt-styles')
    <style>
        body { margin: 0; background: #e7ebe6; font-family: Inter, Arial, sans-serif; }
        .toolbar { display: flex; gap: 8px; justify-content: center; padding: 12px; flex-wrap: wrap; }
        .toolbar a, .toolbar button { font: 600 14px Inter, Arial, sans-serif; padding: 10px 16px; border-radius: 8px; border: 1px solid #c9d1c8; background: #fff; color: #16201b; text-decoration: none; cursor: pointer; }
        .toolbar .primary { background: #0e6b4a; border-color: #0e6b4a; color: #fff; }
        .paper { background: #fff; margin: 0 auto 24px; box-shadow: 0 6px 24px rgba(0,0,0,.12); box-sizing: border-box; }
        .paper.roll { width: 80mm; padding: 4mm; }
        .paper.a4 { width: 210mm; min-height: 297mm; padding: 16mm; }
        @media print {
            body { background: #fff; }
            .toolbar { display: none; }
            .paper { box-shadow: none; margin: 0; }
            @page { margin: 0; size: {{ $format === 'a4' ? 'A4' : '80mm auto' }}; }
        }
    </style>
</head>
<body>
    <div class="toolbar">
        <button type="button" class="primary" onclick="window.print()">Print</button>
        <a href="{{ route('invoices.print', ['invoice' => request()->route('invoice'), 'format' => $format === 'a4' ? '80mm' : 'a4', 'auto' => 0]) }}">Switch to {{ $format === 'a4' ? '80 mm receipt' : 'A4' }}</a>
        <a href="{{ route('invoices.pdf', ['invoice' => request()->route('invoice'), 'format' => $format]) }}">Save as PDF</a>
        <a href="{{ url('/admin/pos') }}">Back to tables</a>
    </div>
    <div class="paper {{ $format === 'a4' ? 'a4' : 'roll' }}">
        @include('invoices.partials.receipt', ['r' => $r, 'format' => $format])
    </div>
    @if ($autoPrint)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
</body>
</html>
