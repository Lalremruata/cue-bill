<?php

namespace App\Filament\Pages;

use App\Models\BusinessSetting;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\RestaurantTable;
use App\Models\SessionItem;
use App\Models\TableSession;
use App\Services\TableSessionService;
use App\Support\Billing;
use BackedEnum;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use UnitEnum;

class Pos extends Page
{
    protected string $view = 'filament.pages.pos';

    protected static string|BackedEnum|null $navigationIcon = 'heroicon-o-squares-2x2';

    protected static ?string $navigationLabel = 'Tables & Orders';

    protected static string|UnitEnum|null $navigationGroup = 'Sales';

    protected static ?int $navigationSort = 1;

    protected static ?string $slug = 'pos';

    public ?int $selectedTableId = null;

    public string $category = 'all';

    public string $search = '';

    public function getTitle(): string
    {
        return 'Tables & Orders';
    }

    public function mount(): void
    {
        $this->selectedTableId = request()->integer('table') ?: RestaurantTable::query()->where('is_active', true)->orderBy('sort')->value('id');
    }

    public function selectTable(int $id): void
    {
        $this->selectedTableId = $id;
    }

    public function setCategory(string $category): void
    {
        $this->category = $category;
    }

    protected function currentTable(): RestaurantTable
    {
        return RestaurantTable::query()->findOrFail($this->selectedTableId);
    }

    protected function currentSession(bool $create = true): ?TableSession
    {
        $table = $this->currentTable();

        return $create ? app(TableSessionService::class)->openFor($table) : $table->openSession()->first();
    }

    public function startTimer(TableSessionService $service): void
    {
        abort_unless($this->currentTable()->isPool(), 422);
        $service->startTimer($this->currentSession());
    }

    public function pauseTimer(TableSessionService $service): void
    {
        if ($s = $this->currentSession(false)) {
            $service->pauseTimer($s);
        }
    }

    public function resumeTimer(TableSessionService $service): void
    {
        if ($s = $this->currentSession(false)) {
            $service->resumeTimer($s);
        }
    }

    public function stopTimer(TableSessionService $service): void
    {
        if ($s = $this->currentSession(false)) {
            $service->stopTimer($s);
        }
    }

    public function addItem(int $menuItemId, TableSessionService $service): void
    {
        $service->addItem($this->currentSession(), MenuItem::query()->where('is_active', true)->findOrFail($menuItemId));
    }

    public function changeQty(int $lineId, int $delta, TableSessionService $service): void
    {
        $line = SessionItem::query()->findOrFail($lineId);
        abort_unless($line->session->restaurant_table_id === $this->selectedTableId, 403);
        $service->changeQty($line, $delta > 0 ? 1 : -1);
    }

    public function cancelOrder(TableSessionService $service): void
    {
        if ($s = $this->currentSession(false)) {
            $service->cancel($s);
            Notification::make()->title('Order cleared')->success()->send();
        }
    }

    public function checkout()
    {
        $s = $this->currentSession(false);
        if (! $s || ($s->items()->doesntExist() && ! $s->timer_started_at)) {
            Notification::make()->title('Nothing to bill yet')->body('Start the timer or add items first.')->warning()->send();

            return null;
        }

        return redirect(Checkout::getUrl(['session' => $s->id]));
    }

    protected function getViewData(): array
    {
        $settings = BusinessSetting::current();
        $tables = RestaurantTable::query()->where('is_active', true)->orderBy('sort')->orderBy('name')
            ->with('openSession.items.menuItem')->get();
        $selected = $tables->firstWhere('id', $this->selectedTableId) ?? $tables->first();
        $this->selectedTableId = $selected?->id;
        $session = $selected?->openSession;

        $menu = MenuItem::query()->with('category')->where('is_active', true)
            ->when($this->category !== 'all', fn ($q) => $q->where('category_id', $this->category))
            ->when($this->search !== '', fn ($q) => $q->where('name', 'like', '%'.$this->search.'%'))
            ->orderBy('name')->get();

        return [
            'settings' => $settings,
            'tables' => $tables,
            'selected' => $selected,
            'session' => $session,
            'menu' => $menu,
            'categories' => Category::query()->orderBy('sort')->orderBy('name')->get(),
            'inr' => fn ($v) => Billing::inr((float) $v),
            'clock' => fn (?TableSession $s) => $this->clockConfig($s, $settings),
        ];
    }

    /** Data for the live timer (resources/js in public/js/cuebill.js). */
    protected function clockConfig(?TableSession $s, BusinessSetting $settings): array
    {
        $ms = fn ($d) => $d ? $d->getTimestamp() * 1000 : null;
        $rate = $s ? (float) ($s->hourly_rate ?: $settings->poolRateFor($s->table, now())) : (float) $settings->pool_rate_per_hour;

        return [
            'serverNow' => now()->getTimestamp() * 1000,
            'start' => $ms($s?->timer_started_at),
            'pausedSeconds' => $s?->paused_seconds ?? 0,
            'pausedAt' => $ms($s?->timer_paused_at),
            'stoppedAt' => $ms($s?->timer_stopped_at),
            'rate' => $rate,
            'block' => $settings->billing_block_minutes,
            'min' => $settings->minimum_minutes,
            'items' => $s ? $s->itemsSubtotal() : 0,
            'gstPool' => $settings->gst_pool_rate,
            'gstFood' => $settings->gst_food_rate,
        ];
    }
}
