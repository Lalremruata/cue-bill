<?php

namespace Tests\Unit;

use App\Support\Billing;
use PHPUnit\Framework\TestCase;

class BillingTest extends TestCase
{
    public function test_elapsed_time_excludes_pauses(): void
    {
        $this->assertSame(0, Billing::elapsedSeconds(null, 0, null, null, 1000));
        $this->assertSame(3600, Billing::elapsedSeconds(1000, 60, null, null, 4660));
        $this->assertSame(1000, Billing::elapsedSeconds(1000, 0, 2000, null, 9999)); // paused
        $this->assertSame(600, Billing::elapsedSeconds(1000, 0, null, 1600, 9999)); // stopped
    }

    public function test_billed_minutes_round_up_to_block_with_minimum(): void
    {
        $this->assertSame(0, Billing::billedMinutes(0, 15, 30));
        $this->assertSame(30, Billing::billedMinutes(10 * 60, 15, 30));
        $this->assertSame(90, Billing::billedMinutes(84 * 60 + 10, 15, 30));
        $this->assertSame(105, Billing::billedMinutes(90 * 60 + 1, 15, 30));
        $this->assertSame(2, Billing::billedMinutes(61, 1, 0));
    }

    public function test_totals_with_gst_discount_and_round_off(): void
    {
        $t = Billing::totals(300, 530, 0, 18, 5);
        $this->assertSame(54.0, $t['gst_pool']);
        $this->assertSame(26.5, $t['gst_food']);
        $this->assertSame(911.0, $t['total']);
        $this->assertSame(0.5, $t['round_off']);

        $t = Billing::totals(300, 530, 10, 18, 5);
        $this->assertSame(83.0, $t['discount']);
        $this->assertSame(747.0, $t['net_revenue']);
        $this->assertSame(819.0, $t['total']);
    }

    public function test_indian_rupee_format(): void
    {
        $this->assertSame('₹1,48,620', Billing::inr(148620));
        $this->assertSame('₹12,34,567.50', Billing::inr(1234567.5, 2));
        $this->assertSame('1h 24m', Billing::duration(84));
    }
}
