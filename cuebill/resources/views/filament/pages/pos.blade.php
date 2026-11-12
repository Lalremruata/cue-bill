<x-filament-panels::page>
    <div class="cb-pos">
        {{-- Left: tables + menu --}}
        <div class="cb-pos-main">
            <div class="cb-legend">
                <span><i class="cb-dot cb-dot-running"></i>In play</span>
                <span><i class="cb-dot cb-dot-busy"></i>Paused / ordering</span>
                <span><i class="cb-dot cb-dot-free"></i>Free</span>
            </div>

            <section class="cb-table-grid" aria-label="Tables">
                @foreach ($tables as $t)
                    @php
                        $s = $t->openSession;
                        $state = $s?->timerState() ?? 'idle';
                        $hasItems = $s && $s->items->isNotEmpty();
                        $status = $t->isPool()
                            ? ($state === 'running' ? 'running' : (($state !== 'idle' || $hasItems) ? 'busy' : 'free'))
                            : ($hasItems ? 'busy' : 'free');
                    @endphp
                    <button type="button"
                            wire:click="selectTable({{ $t->id }})"
                            wire:key="table-{{ $t->id }}-{{ $s?->updated_at?->timestamp }}-{{ $s?->items->sum('qty') }}"
                            aria-pressed="{{ $selected?->id === $t->id ? 'true' : 'false' }}"
                            class="cb-table-card {{ $t->isPool() ? 'is-pool' : '' }} {{ $selected?->id === $t->id ? 'is-selected' : '' }}"
                            @if ($t->isPool() && $s && $s->timer_started_at) x-data="cbClock(@js($clock($s)))" @endif>
                        <span class="cb-table-card-head">
                            <span class="cb-table-name">{{ $t->name }}</span>
                            <i class="cb-dot cb-dot-{{ $status }}"></i>
                        </span>
                        <span class="cb-muted cb-sm">{{ $t->isPool() ? 'Pool · '.$inr($t->hourly_rate ?: $settings->pool_rate_per_hour).'/hr' : \App\Models\RestaurantTable::TYPES[$t->type] }}</span>
                        @if ($status === 'free')
                            <span class="cb-table-big">Free</span>
                            <span class="cb-muted cb-sm">Tap to open</span>
                        @elseif ($t->isPool() && $s->timer_started_at)
                            <span class="cb-table-big cb-num" x-text="clock">--:--:--</span>
                            <span class="cb-muted cb-sm cb-num"><span x-text="money(total)"></span> so far</span>
                        @else
                            <span class="cb-table-big cb-num">{{ $inr($s->itemsSubtotal()) }}</span>
                            <span class="cb-muted cb-sm">{{ $s->items->sum('qty') }} items</span>
                        @endif
                    </button>
                @endforeach
            </section>

            @if ($selected)
                <x-filament::section>
                    <x-slot name="heading">Add items to {{ $selected->name }}</x-slot>
                    <div class="cb-menu-toolbar">
                    <div class="cb-chips" role="group" aria-label="Category">
                        <button type="button" wire:click="setCategory('all')" class="cb-chip {{ $category === 'all' ? 'is-on' : '' }}">All</button>
                        @foreach ($categories as $c)
                            <button type="button" wire:click="setCategory('{{ $c->id }}')" class="cb-chip {{ (string) $category === (string) $c->id ? 'is-on' : '' }}">{{ $c->name }}</button>
                        @endforeach
                    </div>
                    <div class="cb-search">
                        <x-filament::input.wrapper prefix-icon="heroicon-m-magnifying-glass">
                            <x-filament::input type="search" wire:model.live.debounce.300ms="search" placeholder="Search menu…" aria-label="Search menu" />
                        </x-filament::input.wrapper>
                    </div>
                    </div>

                    <div class="cb-menu-grid">
                        @forelse ($menu as $m)
                            <button type="button" wire:click="addItem({{ $m->id }})" wire:key="menu-{{ $m->id }}" class="cb-menu-item">
                                <span class="cb-menu-name">{{ $m->name }}</span>
                                <span class="cb-menu-foot"><strong class="cb-num">{{ $inr($m->price) }}</strong><span class="cb-muted cb-sm">{{ $m->category?->name }}</span></span>
                            </button>
                        @empty
                            <p class="cb-muted">No menu items match. Add items under Menu &amp; Tables → Menu items.</p>
                        @endforelse
                    </div>
                </x-filament::section>
            @endif
        </div>

        {{-- Right: current order --}}
        @if ($selected)
            <aside class="cb-order" aria-label="Current order"
                   wire:key="order-{{ $selected->id }}-{{ $session?->updated_at?->timestamp }}-{{ $session?->items->sum('qty') }}"
                   @if ($session) x-data="cbClock(@js($clock($session)))" @endif>
                <div class="cb-order-head">
                    <div class="cb-order-title">
                        <div>
                            <div class="cb-order-name">{{ $selected->name }}</div>
                            <div class="cb-order-sub">
                                {{ \App\Models\RestaurantTable::TYPES[$selected->type] }} ·
                                {{ match ($session?->timerState()) { 'running' => 'In play', 'paused' => 'Paused', 'stopped' => 'Timer stopped', default => $session ? 'Ordering' : 'Free' } }}
                            </div>
                        </div>
                        @if ($session?->timer_started_at)
                            <span class="cb-order-sub cb-num">Started {{ $session->timer_started_at->format('g:i A') }}</span>
                        @endif
                    </div>

                    @if ($selected->isPool())
                        <div class="cb-clock cb-num" @if ($session) x-text="clock" @endif>00:00:00</div>
                        <div class="cb-order-sub cb-num">
                            {{ $inr($session?->hourly_rate ?: $settings->poolRateFor($selected, now())) }}/hr ·
                            billed in {{ $settings->billing_block_minutes }}-min blocks, min {{ $settings->minimum_minutes }} min
                            @if ($session?->timer_started_at) · billable <span x-text="billedMinutes"></span> min @endif
                        </div>
                        <div class="cb-order-actions">
                            @php $state = $session?->timerState() ?? 'idle'; @endphp
                            @if ($state === 'idle')
                                <x-filament::button wire:click="startTimer" icon="heroicon-m-play" color="success">Start timer</x-filament::button>
                            @endif
                            @if ($state === 'running')
                                <x-filament::button wire:click="pauseTimer" icon="heroicon-m-pause" color="gray">Pause</x-filament::button>
                            @endif
                            @if ($state === 'paused')
                                <x-filament::button wire:click="resumeTimer" icon="heroicon-m-play" color="success">Resume</x-filament::button>
                            @endif
                            @if (in_array($state, ['running', 'paused']))
                                <x-filament::button wire:click="stopTimer" icon="heroicon-m-stop" color="danger" outlined
                                                    wire:confirm="Stop the timer for {{ $selected->name }}?">Stop timer</x-filament::button>
                            @endif
                        </div>
                    @endif
                </div>

                <div class="cb-order-lines">
                    @if (! $session || $session->items->isEmpty())
                        <p class="cb-muted cb-empty">No food or drinks yet. Tap an item to add it.</p>
                    @else
                        @foreach ($session->items as $line)
                            <div class="cb-line" wire:key="line-{{ $line->id }}-{{ $line->qty }}">
                                <div class="cb-line-name">
                                    <div>{{ $line->menuItem->name }}</div>
                                    <div class="cb-muted cb-sm cb-num">{{ $inr($line->menuItem->price) }} each</div>
                                </div>
                                <div class="cb-stepper">
                                    <x-filament::icon-button icon="heroicon-m-minus" color="gray" wire:click="changeQty({{ $line->id }}, -1)" label="Remove one {{ $line->menuItem->name }}" />
                                    <span class="cb-num cb-qty">{{ $line->qty }}</span>
                                    <x-filament::icon-button icon="heroicon-m-plus" color="gray" wire:click="changeQty({{ $line->id }}, 1)" label="Add one {{ $line->menuItem->name }}" />
                                </div>
                                <div class="cb-num cb-line-total">{{ $inr($line->qty * $line->menuItem->price) }}</div>
                            </div>
                        @endforeach
                    @endif
                </div>

                <div class="cb-order-foot">
                    @if ($selected->isPool())
                        <div class="cb-row"><span class="cb-muted">Pool table time</span><span class="cb-num" @if ($session) x-text="money(poolAmount)" @endif>₹0</span></div>
                    @endif
                    <div class="cb-row"><span class="cb-muted">Food &amp; drinks</span><span class="cb-num">{{ $inr($session?->itemsSubtotal() ?? 0) }}</span></div>
                    <div class="cb-row cb-row-total"><span>Total incl. GST (est.)</span><span class="cb-num" @if ($session) x-text="money(total)" @endif>₹0</span></div>
                    <div class="cb-order-actions">
                        @if ($session)
                            <x-filament::button color="gray" outlined wire:click="cancelOrder" wire:confirm="Clear this order without billing?">Clear</x-filament::button>
                        @endif
                        <x-filament::button wire:click="checkout" icon="heroicon-m-receipt-percent" class="cb-grow">Stop &amp; checkout</x-filament::button>
                    </div>
                </div>
            </aside>
        @else
            <x-filament::section>
                <p>No tables yet. Add pool and dining tables under <strong>Menu &amp; Tables → Tables</strong>.</p>
            </x-filament::section>
        @endif
    </div>
</x-filament-panels::page>
