<?php

namespace App\Support;

use OpenSpout\Common\Entity\Row;
use OpenSpout\Writer\XLSX\Writer;
use Symfony\Component\HttpFoundation\StreamedResponse;

/** Streams an .xlsx file using OpenSpout (already installed with Filament). */
class SpreadsheetExport
{
    /**
     * @param  array<int, string>  $headings
     * @param  iterable<array<int, mixed>>  $rows
     */
    public static function download(string $filename, array $headings, iterable $rows): StreamedResponse
    {
        return response()->streamDownload(function () use ($headings, $rows) {
            $writer = new Writer();
            $writer->openToFile('php://output');
            $writer->addRow(Row::fromValues($headings));
            foreach ($rows as $row) {
                $writer->addRow(Row::fromValues(array_values($row)));
            }
            $writer->close();
        }, $filename, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ]);
    }
}
