# CueBill: notes for Claude Code

CueBill is a POS for a restaurant with pool tables. Pool time is billed hourly, food and drinks are added to the table's order, and the app prints GST invoices with a UPI QR. Sales are stored locally, and there are dashboards and reports with Excel and PDF export.

**Stack:** Laravel 12, Filament 4, Livewire 3, SQLite (local, works offline), barryvdh/laravel-dompdf, bacon/bacon-qr-code, openspout (Excel).

## Design

- **Read `design/DESIGN.md` and open the matching `design/screens/*.png` before any UI work.** New UI must match those screens: tokens, spacing, components and copy.
- **Styling:** custom screens use plain CSS in `public/css/cuebill.css` (`cb-*` classes and `--cb-*` variables), loaded through a render hook in `AdminPanelProvider`.
  - Don't add Tailwind utility classes to Blade views. Filament's compiled CSS doesn't include arbitrary utilities, and there is no Vite theme build.
  - If you need a new style, add a `cb-` class to `cuebill.css`, with dark-mode support through `.dark`.
- **Filament components:** prefer Filament's Blade components (`x-filament::section`, `button`, `input.wrapper`, `input`, `input.select`, `input.checkbox`, `icon-button`, `tabs`) inside custom pages.
- **Icons:** use `heroicon-*` names through Filament components. `<x-heroicon-*>` components are disabled by `DisableBladeIconComponents`.
- **Copy:** short, plain English. Money always goes through `Billing::inr()` (₹ with Indian grouping). Times use the 12-hour format.

## Code layout

| File | What it does |
|---|---|
| `app/Support/Billing.php` | All billing maths (pure PHP). Change it only together with `tests/Unit/BillingTest.php`. |
| `app/Services/TableSessionService.php` | Timer and order actions. |
| `app/Services/CheckoutService.php` | `calculate()`, `preview()` (draft receipt) and `complete()` (transaction, invoice number, business snapshot). |
| `app/Services/SalesAnalytics.php` | Every dashboard and report number. Revenue = after discount, before GST. Collected = including GST. |
| `resources/views/invoices/partials/receipt.blade.php` | The one receipt layout, used by the checkout preview, the print view and the PDF. It uses tables, not flexbox, because dompdf can't do flexbox. |
| Invoices | Can't be edited or deleted from the UI (GST records). |

## Rules

- Keep the app working offline. No CDN assets in print or PDF views; logos and QR codes are embedded as data URIs.
- Prices are GST-exclusive. GST rates come from `business_settings`, never hard-coded.
- Any new setting goes into the `business_settings` table, the `BusinessSettings` page (FIELDS + rules + view), and `snapshot()` if it prints on invoices.
- Target Filament 4 APIs:
  - `Filament\Schemas\Schema` forms
  - `Filament\Actions\*` with `recordActions()` / `toolbarActions()`
  - non-static `protected string $view` on pages and widgets
  - `string|BackedEnum|null $navigationIcon`

## Commands

```bash
php artisan test                                   # unit + feature tests (must pass)
php artisan migrate:fresh --seed                   # reset with menu, tables and admin user
php artisan db:seed --class=DemoSalesSeeder        # 45 days of sample sales
php artisan serve --host=0.0.0.0 --port=8000       # counter PC + tablets on the LAN
```

Login: `admin@cuebill.local` / `password`.

## Checking UI changes

Run the app, open the changed page at 1440 px wide and at phone width, and compare it side by side with the matching `design/screens/*.png`. Check the light and dark themes. For invoices, check the print view (`/invoices/{id}/print?format=80mm` and `?format=a4`) and the PDF.
