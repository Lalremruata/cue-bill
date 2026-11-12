<x-filament-widgets::widget>
    <x-filament::section :heading="$heading" :description="$description">
        @if ($rows->isEmpty())
            <p class="cb-muted cb-sm">{{ $empty }}</p>
        @else
            <ul class="cb-list">
                @foreach ($rows as $row)
                    <li>
                        <div>
                            <div class="cb-strong">{{ $row['name'] }}</div>
                            <div class="cb-muted cb-sm cb-num">{{ $row['meta'] }}</div>
                        </div>
                        <span class="cb-badge is-{{ ['good' => 'star', 'warn' => 'slow', 'bad' => 'loss'][$row['tone']] }} cb-num">{{ $row['badge'] }}</span>
                    </li>
                @endforeach
            </ul>
        @endif
    </x-filament::section>
</x-filament-widgets::widget>
