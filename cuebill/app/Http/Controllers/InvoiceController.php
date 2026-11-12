<?php

namespace App\Http\Controllers;

use App\Models\Invoice;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\Request;

class InvoiceController extends Controller
{
    /** Browser print view. ?format=80mm (thermal receipt) or a4. */
    public function print(Request $request, Invoice $invoice)
    {
        return view('invoices.print', [
            'r' => $invoice->load('items')->toReceipt(),
            'format' => $request->query('format') === 'a4' ? 'a4' : '80mm',
            'autoPrint' => $request->boolean('auto', true),
        ]);
    }

    public function pdf(Request $request, Invoice $invoice)
    {
        $format = $request->query('format') === '80mm' ? '80mm' : 'a4';
        $r = $invoice->load('items')->toReceipt();
        $pdf = Pdf::loadView('invoices.pdf', ['r' => $r, 'format' => $format]);

        // 80 mm roll: 226pt wide, height grows with the number of lines.
        $format === '80mm'
            ? $pdf->setPaper([0, 0, 226.77, 420 + count($r['lines']) * 28 + ($r['qr_svg'] ? 170 : 0)])
            : $pdf->setPaper('a4');

        return $pdf->download($invoice->number.'.pdf');
    }
}
