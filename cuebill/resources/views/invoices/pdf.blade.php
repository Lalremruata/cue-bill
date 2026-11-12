<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>{{ $r['number'] }}</title>
    @include('invoices.partials.receipt-styles')
    <style>
        @page { margin: {{ $format === 'a4' ? '36pt 40pt' : '10pt 8pt' }}; }
        body { font-family: 'DejaVu Sans', sans-serif; margin: 0; }
        .rc { font-size: {{ $format === 'a4' ? '11px' : '9px' }}; }
        .rc .name { font-size: {{ $format === 'a4' ? '18px' : '13px' }}; }
        .rc .total td { font-size: {{ $format === 'a4' ? '15px' : '12px' }}; }
        .rc .qr img { width: {{ $format === 'a4' ? '130px' : '110px' }}; height: {{ $format === 'a4' ? '130px' : '110px' }}; }
    </style>
</head>
<body>
    @include('invoices.partials.receipt', ['r' => $r, 'format' => $format])
</body>
</html>
