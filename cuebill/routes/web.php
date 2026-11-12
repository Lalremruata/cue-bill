<?php

use App\Http\Controllers\ExportController;
use App\Http\Controllers\InvoiceController;
use Illuminate\Support\Facades\Route;

Route::redirect('/', '/admin');

Route::middleware('auth')->group(function () {
    Route::get('/invoices/{invoice}/print', [InvoiceController::class, 'print'])->name('invoices.print');
    Route::get('/invoices/{invoice}/pdf', [InvoiceController::class, 'pdf'])->name('invoices.pdf');

    Route::get('/exports/invoices', [ExportController::class, 'invoices'])->name('exports.invoices');
    Route::get('/exports/items', [ExportController::class, 'items'])->name('exports.items');
    Route::get('/exports/daily', [ExportController::class, 'daily'])->name('exports.daily');
    Route::get('/backup', [ExportController::class, 'backup'])->name('backup.download');
});
