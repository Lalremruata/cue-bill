<?php

namespace App\Support;

/**
 * Pure billing maths (no framework dependencies) so it is easy to unit test.
 */
class Billing
{
    public static function elapsedSeconds(?int $startedAt, int $pausedSeconds, ?int $pausedAt, ?int $stoppedAt, int $now): int
    {
        if (! $startedAt) {
            return 0;
        }
        $end = $stoppedAt ?? $pausedAt ?? $now;

        return max(0, $end - $startedAt - $pausedSeconds);
    }

    /** Minutes the customer pays for: rounded up to the billing block, never below the minimum. */
    public static function billedMinutes(int $elapsedSeconds, int $blockMinutes, int $minimumMinutes): int
    {
        if ($elapsedSeconds <= 0) {
            return 0;
        }
        $minutes = (int) ceil($elapsedSeconds / 60);
        if ($blockMinutes > 1) {
            $minutes = (int) (ceil($minutes / $blockMinutes) * $blockMinutes);
        }

        return max($minutes, $minimumMinutes);
    }

    public static function poolAmount(int $billedMinutes, float $ratePerHour): float
    {
        return round($billedMinutes / 60 * $ratePerHour, 2);
    }

    /**
     * Prices are GST-exclusive; the discount applies to pool time and items alike.
     *
     * @return array{subtotal: float, discount_pool: float, discount_food: float, discount: float, gst_pool: float, gst_food: float, exact: float, round_off: float, total: float, net_revenue: float}
     */
    public static function totals(float $poolAmount, float $itemsSubtotal, float $discountPercent, float $gstPoolRate, float $gstFoodRate): array
    {
        $discountPercent = max(0, min(100, $discountPercent));
        $discountPool = round($poolAmount * $discountPercent / 100, 2);
        $discountFood = round($itemsSubtotal * $discountPercent / 100, 2);
        $netPool = $poolAmount - $discountPool;
        $netFood = $itemsSubtotal - $discountFood;
        $gstPool = round($netPool * $gstPoolRate / 100, 2);
        $gstFood = round($netFood * $gstFoodRate / 100, 2);
        $exact = round($netPool + $netFood + $gstPool + $gstFood, 2);
        $total = round($exact);

        return [
            'subtotal' => round($poolAmount + $itemsSubtotal, 2),
            'discount_pool' => $discountPool,
            'discount_food' => $discountFood,
            'discount' => round($discountPool + $discountFood, 2),
            'gst_pool' => $gstPool,
            'gst_food' => $gstFood,
            'exact' => $exact,
            'round_off' => round($total - $exact, 2),
            'total' => (float) $total,
            'net_revenue' => round($netPool + $netFood, 2),
        ];
    }

    public static function duration(int $minutes): string
    {
        $h = intdiv($minutes, 60);
        $m = $minutes % 60;

        return trim(($h ? $h.'h ' : '').($m || ! $h ? $m.'m' : ''));
    }

    public static function inr(float $amount, int $decimals = 0): string
    {
        $negative = $amount < 0;
        [$whole, $fraction] = array_pad(explode('.', number_format(abs($amount), $decimals, '.', '')), 2, null);
        // Indian digit grouping: 1,23,45,678
        $last3 = substr($whole, -3);
        $rest = substr($whole, 0, -3);
        $grouped = $rest !== '' ? preg_replace('/\B(?=(\d{2})+(?!\d))/', ',', $rest).','.$last3 : $last3;

        return ($negative ? '-' : '').'₹'.$grouped.($fraction !== null ? '.'.$fraction : '');
    }
}
