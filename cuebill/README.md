# CueBill — pool table + restaurant POS (Laravel 12 + Filament 4)

Runs on the counter PC with a local SQLite database, so it works without internet.

## What's inside

| Screen | What it does |
|---|---|
| **Dashboard** | Sales, gross profit, margin and pool hours vs the previous 7 days; revenue by day (pool / food / drinks / snacks); where profit comes from; pool busy hours; best sellers; items that need attention; recent invoices |
| **Tables & Orders** (`/admin/pos`) | Pool tables with a live timer (start, pause, resume, stop), dining tables and takeaway, tap-to-add menu, running total |
| **Checkout** | Cash / UPI / Card / Split, discount, customer name and phone, cash change, live invoice preview (80 mm or A4) with a UPI QR for the exact amount |
| **Invoices** | Every sale; reprint as 80 mm receipt or A4, save as PDF, export to Excel |
| **Reports** | Any date range and payment method: item performance (Star / Steady / Slow / Loss risk), daily sales, invoice list; Excel export; print or save as PDF |
| **Menu & costs** | Edit cost and price inline; margin is worked out for you |
| **Categories / Tables** | Food, drinks and snacks categories; pool and dining tables (a pool table can have its own hourly rate) |
| **Business settings** | Restaurant name, address, GSTIN, FSSAI, logo, invoice prefix and number, footer, UPI ID and payee name, pool rates (billing block, minimum, running cost, happy hour), GST rates, database backup |

Billing rules (all editable in Business settings): pool time is rounded up to the billing block (default 15 min) with a minimum (default 30 min). Prices are GST-exclusive. GST is 5% on food and 18% on pool time by default; confirm the rates with your CA. Each invoice keeps a copy of the business details used when it was printed.

## Install (about 10 minutes)

You need PHP 8.2+ (with `sqlite3`, `gd`, `zip`, `intl`, `fileinfo`) and Composer. On Windows, [Laravel Herd](https://herd.laravel.com) installs both.

```bash
# 1. Fresh Laravel project
composer create-project laravel/laravel cuebill
cd cuebill

# 2. Packages
composer require filament/filament:"^4.0" barryvdh/laravel-dompdf bacon/bacon-qr-code openspout/openspout -W

# 3. Filament panel (accept the ID "admin")
php artisan filament:install --panels

# 4. Copy the CueBill files over the project (overwrites the panel provider, User model, routes/web.php, bootstrap/app.php)
php path/to/cuebill-files/install.php .

# 5. Database
php artisan migrate --seed
php artisan storage:link
php artisan db:seed --class=DemoSalesSeeder   # optional: 45 days of sample sales to try the dashboard

# 6. Run
php artisan serve
```

Open http://127.0.0.1:8000 and sign in with **admin@cuebill.local / password**, then change the password. To add staff accounts, run `php artisan make:filament-user`.

Then go to **Business settings** and enter your restaurant details and UPI ID, and set up **Menu & costs** and **Tables**.

To remove the sample sales later, run `php artisan migrate:fresh --seed`. This deletes all data.

### Use phones and tablets for orders

Run `php artisan serve --host=0.0.0.0 --port=8000`, then open `http://<counter-PC-IP>:8000` on any device on the same Wi-Fi. The pool timers stay in sync with the counter PC.

### Printing

- **80 mm thermal printer:** install the printer driver, set the paper to 80 mm (roll) and the margins to none. "Print 80 mm receipt" opens the print dialog automatically.
- **A4:** "Print A4 invoice" or "Save as PDF".
- In Chrome, you can start it with `--kiosk-printing` to skip the print dialog at the counter.

### Backups

Business settings → **Download backup** saves a copy of `database/database.sqlite`. Keep copies on a USB drive or Google Drive. To restore, close the app and replace `database/database.sqlite` with the backup.

## Building on it with Claude Code

`CLAUDE.md` (project rules) and `design/` (the design handoff) are copied into the project:

- `design/DESIGN.md`: colour tokens, type, components, and a spec for each screen
- `design/screens/*.png` and `*.html`: a reference image and static HTML for each of the six screens

Start Claude Code in the project folder and it picks these up automatically. For example: *"Match the Tables & Orders page to design/screens/02-tables-orders.png"*.

## Tests

```bash
php artisan test
```

`tests/Unit/BillingTest.php` covers the timer, rounding, GST and round-off maths. `tests/Feature/CheckoutTest.php` runs a full pool table checkout, then loads every page and the print, PDF and Excel routes.

## Code map

```
app/Support/Billing.php                 timer, billing blocks, GST, round-off, ₹ formatting (pure PHP)
app/Support/UpiQr.php                   upi://pay link + SVG QR (bacon/bacon-qr-code)
app/Support/SpreadsheetExport.php       streamed .xlsx via OpenSpout
app/Services/TableSessionService.php    start / pause / resume / stop, add / remove items
app/Services/CheckoutService.php        bill calculation, preview and saving the invoice
app/Services/SalesAnalytics.php         every dashboard and report number
app/Filament/Pages/{Pos,Checkout,Reports,BusinessSettings}.php
app/Filament/Widgets/*                  dashboard
app/Filament/Resources/*                menu items, categories, tables, invoices
resources/views/invoices/*              receipt partial (shared by preview, print and PDF)
public/css/cuebill.css, public/js/cuebill.js   styles and live timer (no npm build needed)
```

## Optional: desktop app

The app is a normal Laravel app, so you can wrap it with NativePHP later if you want a double-click desktop app instead of `php artisan serve`.
