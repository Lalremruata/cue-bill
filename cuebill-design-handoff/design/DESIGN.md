# CueBill — design handoff

The source of truth is the design canvas: https://claude.ai/artifact/Lf3RwW4X2oDXVUcoSVijCv

This folder is a snapshot of it for building:

- `screens/*.png`: each screen at 1440 px wide. **Open these before you change any UI.**
- `screens/*.html`: static HTML of each screen. Open it in a browser and inspect it for exact spacing, sizes and colours.

The sample numbers, names and the `example@upi` QR in the screens are placeholders. Real data comes from the database.

| # | Screen | Reference | Implemented in |
|---|---|---|---|
| 1 | Dashboard | `screens/01-dashboard.png` | `app/Filament/Widgets/*`, default Filament Dashboard |
| 2 | Tables & Orders | `screens/02-tables-orders.png` | `app/Filament/Pages/Pos.php` + `resources/views/filament/pages/pos.blade.php` |
| 3 | Checkout & invoice | `screens/03-checkout-invoice.png` | `Checkout.php` + `checkout.blade.php` + `resources/views/invoices/partials/receipt.blade.php` |
| 4 | Sales reports | `screens/04-reports.png` | `Reports.php` + `reports.blade.php` |
| 5 | Menu & costs | `screens/05-menu-costs.png` | `app/Filament/Resources/MenuItems/*` (inline-editable table) + pool rates in Business settings |
| 6 | Business settings | `screens/06-business-settings.png` | `BusinessSettings.php` + `business-settings.blade.php` |

The design's dark sidebar is a mockup. In the app, Filament's own sidebar and topbar are used, with the navigation groups Sales / Menu & Tables / Settings. Don't rebuild the sidebar.

## 1. Look

The look is calm and practical for the counter: felt green on a light neutral ground, with dark panels for live money and time. No gradients, no emoji, no left-border cards.

### Colour tokens (already in `public/css/cuebill.css` as `--cb-*`)

| Token | Light | Dark (`.dark`) | Use |
|---|---|---|---|
| `--cb-ink` | `#16201B` | `#EEF2EF` | Body text |
| `--cb-muted` | `#56625B` | `#A3B0A9` | Secondary text, labels (5.9:1 on white) |
| `--cb-line` | `#E1E5E0` | `rgba(255,255,255,.1)` | Borders, row dividers |
| `--cb-soft` | `#F4F6F3` | `rgba(255,255,255,.04)` | Page ground, menu tiles, order footer |
| `--cb-card` | `#FFFFFF` | `#18181B` | Cards |
| `--cb-green` | `#0E6B4A` | same | Primary: buttons, selected state, "good" |
| `--cb-green-soft` | `#E4F1EA` | `rgba(14,107,74,.25)` | Selected payment, hover |
| `--cb-dark` | `#14201A` | same | Live panels (timer header, amount due), active chip |
| `--cb-amber` / soft | `#8A4B08` / `#FDF1DD` | `#F2B766` / … | "Slow", warnings |
| `--cb-red` / soft | `#B42318` / `#FDECEA` | `#FF8A80` / … | "Loss risk", errors, Stop timer |

Filament's primary colour is `Color::Emerald`, set in the panel provider, so it matches.

**Chart series** (always in this order; they differ in lightness as well as hue):

| Series | Colour |
|---|---|
| Pool table | `#0E6B4A` |
| Food | `#D08A2E` |
| Drinks | `#9CC5B0` |
| Snacks | `#E9C98F` |

The busy-hours bar shades by occupancy: ≥75% `#0E6B4A`, 40–74% `#5FA383`, below 40% `#C4DCCF`.

### Type

- **Fonts:** Inter for everything in the app (set with `->font('Inter')`). The design uses Space Grotesk for headings and big numbers. That's optional; if you add it, use it only for page titles, KPI values, the timer and totals.
- **Numbers:** every amount, time and quantity uses `font-variant-numeric: tabular-nums` (class `cb-num`).
- **Scale:**

| Element | Size and weight |
|---|---|
| Page title | 28 px / 700 |
| Card heading | 17 px / 600 |
| KPI value | 24–30 px / 700 |
| Body | 14 px |
| Labels | 13 px / 600 muted |
| Table header | 12 px / 600, uppercase, letter-spacing .04em |
| Live timer | 44 px / 700 |
| Grand total | 26 px / 700 |

### Shape and spacing

- **Radii:** cards 14 px, tiles and inputs 10–12 px, chips are pills (999 px), badges 6 px.
- **Spacing:** 24 px between page columns, 16 px between cards, 12 px inside grids, card padding 20 px.
- **Touch targets:** at least 44 px (menu tiles 76 px tall, table cards 120 px). This is a touchscreen till.

### Money and time format

- **Rupees:** Indian digit grouping, `₹1,48,620`. Use `App\Support\Billing::inr()` in PHP and `Intl.NumberFormat('en-IN', …)` in JS. Bill totals are whole rupees; receipt lines show 2 decimals.
- **Timer:** `HH:MM:SS`. Durations read `1h 24m`. Times read `9:42 PM`. Dates read `06-11-2026` on invoices and `06 Nov` in tables.

## 2. Components (CSS classes in `cuebill.css`)

| Component | Class | Notes |
|---|---|---|
| Status dot | `cb-dot cb-dot-running / -busy / -free` | Green with a halo / amber / hollow grey ring. Always shown next to a text legend. |
| Table card | `cb-table-card` (+`is-pool`, `is-selected`) | Pool cards have a pale green ground. Selected: 2 px green border + 4 px soft ring. Content: name + dot, type · rate, big value (timer or ₹), sub line. |
| Menu tile | `cb-menu-item` | Name on top; price (bold) and category at the bottom. Tapping adds 1. |
| Chip | `cb-chip` (+`is-on`) | Category filter, discount presets, date presets. On = dark fill. |
| Payment button | `cb-pay` (+`is-on`) | 2×2 or 4-across grid, 48 px tall. On = green border + soft green. |
| Live panel | `cb-order-head`, `cb-due` | Dark `--cb-dark` block with white text, for the timer and the amount due. |
| Qty stepper | `cb-stepper` | Filament icon buttons with − and +. Removing the last one deletes the line. |
| Badge | `cb-badge is-star / is-steady / is-slow / is-loss` | Item rating. |
| Margin bar | `cb-bar` + `cb-bar-fill is-good / is-mid / is-bad` | Width = margin %. Good ≥50%, mid 30–49%, bad below 30%. |
| KPI tile | `cb-kpi` | Label (13 px muted) over value (22 px bold). |
| Paper | `cb-paper is-roll / is-a4` inside `cb-preview` | White receipt on a grey tray, always white even in dark mode. |

The ratings, used everywhere:

| Rating | Rule |
|---|---|
| **Loss risk** | Margin below 30% |
| **Slow** | Fewer than max(5, 20% of the average quantity) sold |
| **Star** | Margin ≥ 60% and quantity ≥ average |
| **Steady** | Everything else |

The rules live in `SalesAnalytics::items()`.

## 3. Screens

### 1 · Dashboard (`01-dashboard.png`)

1. **KPI row** (4 across, wraps): Sales, Gross profit, Profit margin, Pool table hours. Each shows the change against the previous period as a green or red pill, plus a short note.
2. **Revenue by day**: stacked bars (pool / food / drinks / snacks), full width, with a period filter.
3. **Where profit comes from**: a split bar or doughnut with a profit and margin list per stream, and a one-line insight.
4. **Best sellers** (top by profit) and **Needs attention** (Loss risk or Slow, each with the reason) side by side.
5. **Pool table busy hours**, 12 PM–11 PM, coloured by occupancy, with a happy-hour hint.
6. **Recent invoices** with Receipt and PDF links.

### 2 · Tables & Orders (`02-tables-orders.png`)

The page has two columns. The left takes about 3/5: the table grid, then "Add items to <table>". The right is the order panel, about 2/5, sticky on desktop and stacked below on phones.

- **Table grid:** pool tables first, then dining, then takeaway. Free tables say "Free · Tap to open".
- **Order panel header (dark):**
  - Table name and status, with the start time on the right.
  - The timer, ticking every second on the client (`public/js/cuebill.js`, `cbClock`).
  - A rate line: `₹200/hr · billed in 15-min blocks, min 30 min · billable 90 min`.
  - Buttons by state: idle shows Start timer; running shows Pause and Stop timer; paused shows Resume and Stop timer. Stop asks for confirmation.
- **Order lines:** name, unit price, stepper, line total. When empty: "No food or drinks yet. Tap an item to add it."
- **Footer:** pool table time, food & drinks, GST (estimate), and the **Total** in large type. Then Clear (with confirmation) and **Stop & checkout**, the primary button, about two-thirds of the width.

### 3 · Checkout & invoice (`03-checkout-invoice.png`)

The form is on the left and the invoice preview on the right.

- **Payment method:** Cash / UPI / Card / Split. UPI is the default.
- **Discount:** None / 5 / 10 / 15%, plus a custom % field.
- **Customer name and phone:** optional.
- **Cash received:** shown only for Cash, with the change to return.
- **Format toggle:** 80 mm receipt / A4 tax invoice.
- **Amount due:** dark panel.
- **Note:** "Name, address, GSTIN and UPI ID come from Business settings", with an Edit link.
- **Complete sale:** saves the sale, then shows "INV-xxxxx saved" with Print 80 mm, Print A4, Save as PDF and Back to tables.
- **Receipt order**, top to bottom:
  1. Logo
  2. Name, address, city/state/PIN, phone, GSTIN, FSSAI
  3. **TAX INVOICE**
  4. Invoice number, date and time, table, customer, payment method
  5. Item table with the pool line first: "Pool table time — 8:34–9:58 PM · played 1h 24m, billed 1h 30m"
  6. Subtotal, discount, then CGST+SGST on pool and CGST+SGST on food (shown separately), round off
  7. **TOTAL**
  8. UPI QR for the exact amount, only for UPI or Split: "Scan to pay ₹911 with any UPI app" and the UPI ID
  9. Footer message
- Use dashed rules between receipt sections and a solid rule above TOTAL.

### 4 · Sales reports (`04-reports.png`)

- **Filter bar:** From, To, Payment, quick ranges (Today / 7 / 30 / 90 days), Print / Save PDF, **Export to Excel**. The export follows the active tab and filters.
- **KPI tiles:** Collected (incl. GST), Revenue (ex GST), Cost, Gross profit, Margin, Invoices.
- **Item performance** tab:
  - Category chips: All / Pool table / Food / Snacks / Drinks.
  - A ratings legend, and Sort by (profit, revenue, qty, margin %).
  - Columns: Item, Category, Qty (pool in hours), Revenue, Cost, Profit (bold), Margin bar + %, Rating badge.
  - Items with no sales are listed as Slow.
- **Daily sales** tab: invoices, pool hours, pool / food / drinks / snacks, collected, profit, margin.
- **Invoices** tab: number, date and time, table, paid by, amount, plus Reprint, A4 and PDF.
- **Print:** hide the sidebar, topbar and filters (`@media print` in `cuebill.css`).

### 5 · Menu & costs (`05-menu-costs.png`)

- **Menu table:** the cost and selling price are **edited inline**. Profit per unit and the margin badge update from them (green ≥50%, amber 30–49%, red below 30%). Category badge, and an "on menu" toggle.
- **Pool rates, GST and backup:** these appear on this screen in the design but live in Business settings in the app.

### 6 · Business settings (`06-business-settings.png`)

The form is on the left and a sticky receipt preview on the right that **updates as you type**.

- **Restaurant details:** logo upload, name, address, city, state, PIN, phone, email.
- **Tax & invoice:** GSTIN, validated live with "✓ Valid format · state code 15"; FSSAI; invoice prefix with "Next invoice: INV-00143"; next number; footer; GST rates.
- **UPI payments:** "Print UPI QR on invoices" toggle, UPI ID validated live, payee name, and an explainer saying the QR carries the exact amount.
- **Pool table rates:** rate per hour, billing block, minimum charge, running cost per hour (for pool profit), and happy hour (rate, from, to).
- **Data & backup:** Download backup, with restore instructions.
- **Saving:** Save changes is sticky at the bottom; a success notification confirms the save.

## 4. Behaviour that must not change

- **Billing:** elapsed time is (stopped or paused or now) − started − paused seconds. Billed minutes are rounded up to the block, never below the minimum. Prices exclude GST. The discount applies to both pool time and items. The bill is rounded to the nearest rupee and the difference shown as round off. See `app/Support/Billing.php` and `tests/Unit/BillingTest.php`.
- **Hourly rate:** fixed when the timer starts (the happy-hour rate if inside the window, otherwise the table's own rate, otherwise the default).
- **Invoices:** each invoice copies the business details when it is saved, so reprints never change. Invoice numbers come from `business_settings.next_invoice_number`, inside a transaction.
- **UPI link:** `upi://pay?pa=<id>&pn=<name>&am=<total>&cu=INR&tn=Bill <number>`. The UPI ID is not URL-encoded.

## 5. Accessibility checklist

- Every control is a real `<button>`, `<a>` or `<input>` with a label. Icon-only buttons have a `label` / `aria-label`.
- Text contrast is at least 4.5:1, including the 12–13 px muted labels.
- Selected states use `aria-pressed`, tabs use `aria-selected`, and status colours always come with text.
- Every screen must work at phone width: columns stack, wide tables scroll inside `.cb-scroll`.
