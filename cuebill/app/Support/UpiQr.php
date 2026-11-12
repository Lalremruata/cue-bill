<?php

namespace App\Support;

use BaconQrCode\Renderer\Image\SvgImageBackEnd;
use BaconQrCode\Renderer\ImageRenderer;
use BaconQrCode\Renderer\RendererStyle\RendererStyle;
use BaconQrCode\Writer;

class UpiQr
{
    /** upi://pay link understood by GPay, PhonePe, Paytm, BHIM and bank apps. */
    public static function uri(string $upiId, string $payeeName, float $amount, string $note): string
    {
        // The UPI ID is left unencoded (some UPI apps do not decode %40); the other fields are URL-encoded.
        return 'upi://pay?pa='.trim($upiId)
            .'&pn='.rawurlencode($payeeName)
            .'&am='.number_format($amount, 2, '.', '')
            .'&cu=INR'
            .'&tn='.rawurlencode($note);
    }

    public static function svg(string $upiId, string $payeeName, float $amount, string $note, int $size = 180): string
    {
        $writer = new Writer(new ImageRenderer(new RendererStyle($size, 2), new SvgImageBackEnd()));

        return $writer->writeString(self::uri($upiId, $payeeName, $amount, $note));
    }

    public static function isValidUpiId(?string $upiId): bool
    {
        return (bool) preg_match('/^[A-Za-z0-9._-]{2,256}@[A-Za-z]{2,64}$/', (string) $upiId);
    }

    public static function isValidGstin(?string $gstin): bool
    {
        return (bool) preg_match('/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/', (string) $gstin);
    }
}
