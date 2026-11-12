# CueBill (Flutter)

A POS for a restaurant with pool tables, built in Flutter from the Laravel app in `cuebill/` and the design in `cuebill-design-handoff/`. Pool time is billed by the hour, food and drinks go on the table's order, and the app prints GST invoices with a UPI QR for the exact amount. Everything is stored in a local SQLite database, so it works offline.

Runs on Android 6.0+, iOS, macOS 10.15+, Windows and Linux. (Web is not supported, because it needs local SQLite.)

## Run

```bash
flutter pub get
flutter run -d macos        # or windows, linux, an Android tablet, an iPad
flutter test                # billing maths, checkout, reports, backup, and every screen at 1440 px and 390 px
```

On first run the app seeds the menu, 8 tables and default settings. To try the dashboard, go to **Settings → Data & backup → Load sample sales** (45 days of made-up sales). Then enter your restaurant details, GSTIN and UPI ID in **Settings**.

## Screens

| Screen | What it does |
|---|---|
| Dashboard | Sales, gross profit, margin and pool hours against the previous period; revenue by day; where profit comes from; best sellers; items that need attention; pool busy hours; recent invoices |
| Tables & Orders | Table grid with live pool timers: open play or booked time (30 min to 2 h, or any length), countdown, +30 min / +1 hour, warning and "time up" alerts, Adjust (fix the booking or played time, with a reason and history). Tap-to-add menu; tap a quantity to type it. The order panel keeps its totals and checkout in view however long the order gets; on phones it is a bar along the bottom that opens the full order. |
| Checkout | Cash / UPI / Card / Split, discount, customer, cash change, live 80 mm or A4 receipt preview, then print or save as PDF |
| Invoices | Every sale, with search, reprint (80 mm or A4), PDF and Excel export. Invoices cannot be edited or deleted. |
| Reports | Any date range and payment method: item performance (Star / Steady / Slow / Loss risk), daily sales, invoices. Excel export, print or PDF. |
| Menu & Tables | Cost and price edited inline, with live margin; categories; tables (a pool table can have its own rate) |
| Settings | Restaurant details and logo, GSTIN, invoice numbering, UPI, pool rates and happy hour, GST rates, backup and restore. The receipt preview updates as you type. |

## Google Drive backups

Settings → **Google Drive** connects a Google account. CueBill then uploads a copy of its database to a **CueBill backups** folder in that Drive once a day (while the app is open and online), and whenever you tap **Back up to Drive now**. It keeps the newest 30 backups. **Restore from Drive…** lists them and restores the one you pick. CueBill asks only for the `drive.file` permission, so it can see only the files it creates.

On Android and iOS, sign-in uses the phone's Google account picker. On Windows and macOS, it opens Google in the browser.

### One-time setup

The app needs your own Google sign-in keys. Without them, the Drive card says "not set up" and everything else works as before.

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project, then go to **APIs & Services → Library** and enable the **Google Drive API**.
2. Go to **OAuth consent screen**: choose **External**, fill in the app name and your email, and add the scope `.../auth/drive.file`. Add the Google accounts you'll use as **test users**.
3. Go to **Credentials → Create credentials → OAuth client ID** and create:
   - **Desktop app**, for Windows and macOS. Note its client ID and client secret.
   - **Web application**, for Android sign-in. Note its client ID (this is the "server client ID").
   - **Android**: package name `com.example.cue_bill`, plus the SHA-1 of your signing key (`cd android && ./gradlew signingReport`).
   - **iOS**: bundle ID `com.example.cueBill`. Note its client ID.
4. Copy `google_oauth.example.json` to `google_oauth.json` and fill in the four values.
5. For iOS, copy `ios/Flutter/GoogleOAuth.example.xcconfig` to `ios/Flutter/GoogleOAuth.xcconfig` and set `GOOGLE_REVERSED_CLIENT_ID`: the iOS client ID with its parts reversed, e.g. `com.googleusercontent.apps.1234-abcd`.
6. Run or build with the keys:

   ```bash
   flutter run -d macos --dart-define-from-file=google_oauth.json
   flutter build apk --dart-define-from-file=google_oauth.json
   ```

`google_oauth.json` and `GoogleOAuth.xcconfig` are in `.gitignore`. The desktop client secret is built into the app; Google treats desktop secrets as not confidential.

**Weekly reconnects in Testing mode.** While the consent screen's publishing status is **Testing**, Google expires the sign-in after 7 days and you'd have to connect again every week. Click **Publish app** on the consent screen to stop this. `drive.file` is a non-sensitive scope, so publishing doesn't need Google's review.

**App ID.** The Android and iOS clients are tied to the app ID. If you change it later from `com.example.*`, create new Android and iOS clients for the new ID.

## Code map

```
lib/core/billing.dart        billing maths: timer, billing blocks, GST, discount, round-off (port of Billing.php)
lib/core/format.dart         ₹ with Indian grouping, times, dates
lib/core/upi.dart            upi://pay link, UPI ID and GSTIN validation
lib/data/models.dart         settings, menu, tables, sessions, invoices
lib/data/database.dart       SQLite schema and first-run seed data
lib/data/store.dart          AppStore: all reads and writes, timer actions, checkout transaction, backup and restore
lib/data/demo_sales.dart     sample sales generator (port of DemoSalesSeeder)
lib/services/checkout.dart   bill calculation and receipt preview (port of CheckoutService)
lib/services/analytics.dart  every dashboard and report number (port of SalesAnalytics)
lib/services/receipt*.dart   receipt data and the PDF version (80 mm roll and A4)
lib/services/excel_export.dart  .xlsx exports
lib/services/drive_*.dart    Google Drive: sign-in (drive_auth), Drive API calls (drive_backup), daily backup and restore (drive_sync)
lib/ui/theme.dart            design tokens from DESIGN.md (CbColors, type scale)
lib/ui/widgets.dart          shared components: cards, chips, badges, KPI tiles, tables
lib/ui/receipt_view.dart     on-screen receipt (keep it in step with receipt_pdf.dart)
lib/ui/screens/*             the six screens plus checkout
assets/fonts/                Inter and Space Grotesk, bundled so the app and PDFs work offline
```

## Rules carried over from the Laravel app

- Prices exclude GST. GST rates come from settings and are never hard-coded.
- Elapsed time = (stopped or paused or now) − started − paused seconds. Billed minutes round up to the block and never go below the minimum. The discount applies to pool time and items. The total is rounded to the nearest rupee, and the difference shows as round off.
- Booked time (optional, picked when the timer starts): the booking is charged in full even if the table finishes early (a setting). Overtime up to the free minutes (default 5) is not charged; past that, the overtime is rounded up to the block and added to the booking. The timer never stops by itself at the end of a booking; the table is flagged and staff extend or stop it.
- Changing played time or cutting a booking needs a reason. Every timer action is kept in `session_events`.
- The hourly rate is fixed when the timer starts: the happy-hour rate inside the window, otherwise the table's own rate, otherwise the default.
- Each invoice stores a copy of the business details, so reprints never change. Invoice numbers are taken inside a transaction.
- UPI link: `upi://pay?pa=<id>&pn=<name>&am=<total>&cu=INR&tn=Bill <number>`. The UPI ID is not URL-encoded.

## Differences from the Laravel app

- There is no login. It is a single-device app.
- Tablets on the LAN do not share one database. Each device keeps its own data.
- Backups are a copy of the SQLite file: download it (**Settings → Download backup / Restore**) or send it to Google Drive.
- The app ID is still Flutter's default (`com.example.cue_bill` on Android, `com.example.cueBill` on Apple). Change it before publishing to a store.
