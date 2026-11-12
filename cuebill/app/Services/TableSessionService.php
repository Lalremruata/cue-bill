<?php

namespace App\Services;

use App\Models\BusinessSetting;
use App\Models\MenuItem;
use App\Models\RestaurantTable;
use App\Models\SessionItem;
use App\Models\TableSession;

class TableSessionService
{
    public function openFor(RestaurantTable $table): TableSession
    {
        return $table->openSession()->first()
            ?? $table->sessions()->create(['status' => 'open']);
    }

    public function startTimer(TableSession $session): void
    {
        if ($session->timer_started_at) {
            return;
        }
        $now = now();
        $session->update([
            'timer_started_at' => $now,
            'timer_paused_at' => null,
            'timer_stopped_at' => null,
            'paused_seconds' => 0,
            'hourly_rate' => BusinessSetting::current()->poolRateFor($session->table, $now),
        ]);
    }

    public function pauseTimer(TableSession $session): void
    {
        if ($session->timerState() === 'running') {
            $session->update(['timer_paused_at' => now()]);
        }
    }

    public function resumeTimer(TableSession $session): void
    {
        if ($session->timerState() === 'paused') {
            $session->update([
                'paused_seconds' => $session->paused_seconds + (int) $session->timer_paused_at->diffInSeconds(now(), true),
                'timer_paused_at' => null,
            ]);
        }
    }

    public function stopTimer(TableSession $session): void
    {
        $state = $session->timerState();
        if ($state === 'running' || $state === 'paused') {
            $session->update(['timer_stopped_at' => $session->timer_paused_at ?? now()]);
        }
    }

    public function addItem(TableSession $session, MenuItem $item, int $qty = 1): void
    {
        $line = $session->items()->firstOrNew(['menu_item_id' => $item->id]);
        $line->qty = ($line->exists ? $line->qty : 0) + $qty;
        $line->save();
    }

    public function changeQty(SessionItem $line, int $delta): void
    {
        $qty = $line->qty + $delta;
        $qty > 0 ? $line->update(['qty' => $qty]) : $line->delete();
    }

    /** Close an empty session without billing (e.g. table opened by mistake). */
    public function cancel(TableSession $session): void
    {
        $session->items()->delete();
        $session->update(['status' => 'closed', 'timer_stopped_at' => $session->timer_stopped_at ?? now()]);
    }
}
