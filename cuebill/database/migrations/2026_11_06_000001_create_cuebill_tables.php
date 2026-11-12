<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Single-row table: restaurant details, invoice, UPI, pool rates and GST settings.
        Schema::create('business_settings', function (Blueprint $table) {
            $table->id();
            $table->string('name')->default('Your Restaurant Name');
            $table->string('address')->nullable();
            $table->string('city')->nullable();
            $table->string('state')->default('Mizoram');
            $table->string('pin', 10)->nullable();
            $table->string('phone', 30)->nullable();
            $table->string('email')->nullable();
            $table->string('gstin', 15)->nullable();
            $table->string('fssai', 20)->nullable();
            $table->string('logo_path')->nullable();

            $table->string('invoice_prefix', 20)->default('INV-');
            $table->unsignedInteger('next_invoice_number')->default(1);
            $table->string('invoice_footer')->nullable();

            $table->string('upi_id')->nullable();
            $table->string('upi_payee_name')->nullable();
            $table->boolean('show_upi_qr')->default(true);

            $table->decimal('pool_rate_per_hour', 10, 2)->default(200);
            $table->unsignedSmallInteger('billing_block_minutes')->default(15);
            $table->unsignedSmallInteger('minimum_minutes')->default(30);
            $table->decimal('pool_cost_per_hour', 10, 2)->default(30);
            $table->boolean('happy_hour_enabled')->default(false);
            $table->decimal('happy_hour_rate', 10, 2)->default(150);
            $table->time('happy_hour_start')->default('12:00:00');
            $table->time('happy_hour_end')->default('16:00:00');

            $table->decimal('gst_food_rate', 5, 2)->default(5);
            $table->decimal('gst_pool_rate', 5, 2)->default(18);
            $table->timestamps();
        });

        Schema::create('categories', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('type')->default('food'); // food | drinks | snacks
            $table->unsignedSmallInteger('sort')->default(0);
            $table->timestamps();
        });

        Schema::create('menu_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('category_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->decimal('cost_price', 10, 2)->default(0);
            $table->decimal('price', 10, 2);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('restaurant_tables', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('type')->default('dining'); // pool | dining | takeaway
            $table->decimal('hourly_rate', 10, 2)->nullable(); // overrides the default pool rate
            $table->unsignedSmallInteger('sort')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('table_sessions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_table_id')->constrained()->cascadeOnDelete();
            $table->string('status')->default('open'); // open | closed
            $table->timestamp('timer_started_at')->nullable();
            $table->timestamp('timer_paused_at')->nullable();
            $table->unsignedInteger('paused_seconds')->default(0);
            $table->timestamp('timer_stopped_at')->nullable();
            $table->decimal('hourly_rate', 10, 2)->nullable(); // locked in when the timer starts
            $table->timestamps();
            $table->index(['restaurant_table_id', 'status']);
        });

        Schema::create('session_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('table_session_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_item_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('qty')->default(1);
            $table->timestamps();
            $table->unique(['table_session_id', 'menu_item_id']);
        });

        Schema::create('invoices', function (Blueprint $table) {
            $table->id();
            $table->string('number')->unique();
            $table->foreignId('table_session_id')->nullable()->constrained()->nullOnDelete();
            $table->string('table_name');
            $table->string('customer_name')->nullable();
            $table->string('customer_phone', 20)->nullable();
            $table->string('payment_method'); // cash | upi | card | split
            $table->decimal('cash_received', 10, 2)->nullable();

            $table->timestamp('pool_started_at')->nullable();
            $table->timestamp('pool_ended_at')->nullable();
            $table->unsignedInteger('pool_played_minutes')->default(0);
            $table->unsignedInteger('pool_billed_minutes')->default(0);
            $table->decimal('pool_rate', 10, 2)->default(0);
            $table->decimal('pool_amount', 10, 2)->default(0);
            $table->decimal('pool_cost', 10, 2)->default(0);

            $table->decimal('items_subtotal', 10, 2)->default(0);
            $table->decimal('items_cost', 10, 2)->default(0);
            $table->decimal('discount_percent', 5, 2)->default(0);
            $table->decimal('discount_amount', 10, 2)->default(0);
            $table->decimal('gst_pool', 10, 2)->default(0);
            $table->decimal('gst_food', 10, 2)->default(0);
            $table->decimal('gst_pool_rate', 5, 2)->default(0);
            $table->decimal('gst_food_rate', 5, 2)->default(0);
            $table->decimal('round_off', 6, 2)->default(0);
            $table->decimal('total', 10, 2);
            $table->decimal('net_revenue', 10, 2)->default(0); // after discount, before GST
            $table->decimal('total_cost', 10, 2)->default(0);

            $table->json('business'); // snapshot of business details at the time of sale
            $table->timestamp('paid_at');
            $table->timestamps();
            $table->index('paid_at');
        });

        Schema::create('invoice_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('invoice_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_item_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name');
            $table->string('category_name')->nullable();
            $table->string('category_type')->nullable();
            $table->unsignedInteger('qty');
            $table->decimal('unit_price', 10, 2);
            $table->decimal('unit_cost', 10, 2)->default(0);
            $table->decimal('amount', 10, 2);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('invoice_items');
        Schema::dropIfExists('invoices');
        Schema::dropIfExists('session_items');
        Schema::dropIfExists('table_sessions');
        Schema::dropIfExists('restaurant_tables');
        Schema::dropIfExists('menu_items');
        Schema::dropIfExists('categories');
        Schema::dropIfExists('business_settings');
    }
};
