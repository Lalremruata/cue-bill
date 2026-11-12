import 'package:cue_bill/core/billing.dart';
import 'package:cue_bill/core/format.dart';
import 'package:cue_bill/core/upi.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of tests/Unit/BillingTest.php: the Flutter app must bill exactly like the Laravel app.
void main() {
  test('elapsed time excludes pauses', () {
    expect(Billing.elapsedSeconds(startedAt: null, pausedSeconds: 0, pausedAt: null, stoppedAt: null, now: 1000), 0);
    expect(
      Billing.elapsedSeconds(startedAt: 1000, pausedSeconds: 60, pausedAt: null, stoppedAt: null, now: 4660),
      3600,
    );
    expect(Billing.elapsedSeconds(startedAt: 1000, pausedSeconds: 0, pausedAt: 2000, stoppedAt: null, now: 9999), 1000);
    expect(Billing.elapsedSeconds(startedAt: 1000, pausedSeconds: 0, pausedAt: null, stoppedAt: 1600, now: 9999), 600);
  });

  test('billed minutes round up to block with minimum', () {
    expect(Billing.billedMinutes(0, 15, 30), 0);
    expect(Billing.billedMinutes(10 * 60, 15, 30), 30);
    expect(Billing.billedMinutes(84 * 60 + 10, 15, 30), 90);
    expect(Billing.billedMinutes(90 * 60 + 1, 15, 30), 105);
    expect(Billing.billedMinutes(61, 1, 0), 2);
  });

  test('booked time: full booking, free overtime, then overtime in blocks', () {
    int billed(int playedMin, int? booked, {int grace = 5, bool minimum = true, int block = 15, int min = 30}) =>
        Billing.billedMinutes(
          playedMin * 60,
          block,
          min,
          bookedMinutes: booked,
          graceMinutes: grace,
          bookedIsMinimum: minimum,
        );

    expect(billed(0, 60), 0); // timer not started
    expect(billed(40, 60), 60); // left early: the booking is the minimum
    expect(billed(40, 60, minimum: false), 45); // or played time in blocks...
    expect(billed(65, 70, minimum: false, grace: 0), 70); // ...never more than the booking
    expect(billed(60, 60), 60);
    expect(billed(63, 60), 60); // inside the 5 free minutes
    expect(billed(65, 60), 60);
    expect(billed(66, 60), 75); // 6 min over → one 15-min block
    expect(billed(61, 60, grace: 0), 75);
    expect(billed(95, 60), 105); // 35 over → 45
    expect(billed(10, 15), 30); // the minimum charge still applies
    expect(billed(84, null), 90); // open play is unchanged
    expect(billed(72, 60, block: 1, grace: 0), 72);
  });

  test('time left on a booking', () {
    expect(Billing.remainingSeconds(600, null), isNull);
    expect(Billing.remainingSeconds(600, 0), isNull);
    expect(Billing.remainingSeconds(600, 60), 3000);
    expect(Billing.remainingSeconds(3700, 60), -100);
  });

  test('totals with GST, discount and round off', () {
    var t = Billing.totals(poolAmount: 300, itemsSubtotal: 530, discountPercent: 0, gstPoolRate: 18, gstFoodRate: 5);
    expect(t.gstPool, 54.0);
    expect(t.gstFood, 26.5);
    expect(t.total, 911.0);
    expect(t.roundOff, 0.5);

    t = Billing.totals(poolAmount: 300, itemsSubtotal: 530, discountPercent: 10, gstPoolRate: 18, gstFoodRate: 5);
    expect(t.discount, 83.0);
    expect(t.netRevenue, 747.0);
    expect(t.total, 819.0);
  });

  test('rounds like PHP', () {
    expect(roundTo(1.005, 2), 1.01);
    expect(roundTo(910.5), 911);
    expect(roundTo(-0.5), -1);
  });

  test('Indian rupee format and durations', () {
    expect(Fmt.inr(148620), '₹1,48,620');
    expect(Fmt.inr(1234567.5, 2), '₹12,34,567.50');
    expect(Fmt.inr(999), '₹999');
    expect(Fmt.inr(-1500), '-₹1,500');
    expect(Fmt.amount(300), '300.00');
    expect(Billing.duration(84), '1h 24m');
    expect(Billing.duration(120), '2h');
    expect(Billing.duration(0), '0m');
    expect(Fmt.timer(5050), '01:24:10');
    expect(Fmt.trim(1.5), '1.5');
    expect(Fmt.trim(2.0), '2');
  });

  test('UPI link and validation', () {
    expect(
      Upi.uri(upiId: 'shop@okaxis', payeeName: 'Cue Bar', amount: 911, note: 'Bill INV-00001'),
      'upi://pay?pa=shop@okaxis&pn=Cue%20Bar&am=911.00&cu=INR&tn=Bill%20INV-00001',
    );
    expect(Upi.isValidUpiId('example@upi'), isTrue);
    expect(Upi.isValidUpiId('example'), isFalse);
    expect(Upi.isValidGstin('15AAAAA0000A1Z5'), isTrue);
    expect(Upi.isValidGstin('15AAAAA0000A1X5'), isFalse);
  });
}
