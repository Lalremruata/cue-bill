import 'package:cue_bill/data/models.dart';
import 'package:cue_bill/ui/screens/pos_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ok = BookingState.ok, warning = BookingState.warning, over = BookingState.over;

  test('warning and first time-up fire once', () {
    final t = BookingAlertTracker();
    expect(t.check(1, ok, 600, repeatMinutes: 5), isNull);
    expect(t.check(1, warning, 300, repeatMinutes: 5), BookingAlert.warning);
    expect(t.check(1, warning, 200, repeatMinutes: 5), isNull);
    expect(t.check(1, over, 0, repeatMinutes: 5), BookingAlert.timeUp);
    expect(t.check(1, over, -30, repeatMinutes: 5), isNull);
  });

  test('time-up repeats every N minutes of overtime', () {
    final t = BookingAlertTracker();
    t.check(1, ok, 60, repeatMinutes: 5);
    expect(t.check(1, over, -1, repeatMinutes: 5), BookingAlert.timeUp);
    expect(t.check(1, over, -4 * 60 - 59, repeatMinutes: 5), isNull);
    expect(t.check(1, over, -5 * 60, repeatMinutes: 5), BookingAlert.stillOver);
    expect(t.check(1, over, -5 * 60 - 1, repeatMinutes: 5), isNull);
    expect(t.check(1, over, -10 * 60, repeatMinutes: 5), BookingAlert.stillOver);
  });

  test('repeat off alerts once only', () {
    final t = BookingAlertTracker();
    expect(t.check(1, over, -1, repeatMinutes: 0), BookingAlert.timeUp);
    expect(t.check(1, over, -60 * 60, repeatMinutes: 0), isNull);
  });

  test('extending resets quietly, and the next overrun alerts again', () {
    final t = BookingAlertTracker();
    t.check(1, over, -12 * 60, repeatMinutes: 5);
    expect(t.check(1, ok, 30 * 60, repeatMinutes: 5), isNull);
    expect(t.check(1, warning, 5 * 60, repeatMinutes: 5), BookingAlert.warning);
    expect(t.check(1, over, 0, repeatMinutes: 5), BookingAlert.timeUp);
  });

  test('a table already over when the app opens alerts once, then on the next block', () {
    final t = BookingAlertTracker();
    expect(t.check(1, over, -12 * 60, repeatMinutes: 5), BookingAlert.timeUp);
    expect(t.check(1, over, -14 * 60, repeatMinutes: 5), isNull);
    expect(t.check(1, over, -15 * 60, repeatMinutes: 5), BookingAlert.stillOver);
  });

  test('played time corrected down: next repeat counts from the new overtime', () {
    final t = BookingAlertTracker();
    t.check(1, over, -1, repeatMinutes: 5);
    t.check(1, over, -10 * 60, repeatMinutes: 5);
    expect(t.check(1, over, -3 * 60, repeatMinutes: 5), isNull);
    expect(t.check(1, over, -5 * 60, repeatMinutes: 5), BookingAlert.stillOver);
  });

  test('tables are tracked separately and closed tables are forgotten', () {
    final t = BookingAlertTracker();
    expect(t.check(1, over, -1, repeatMinutes: 5), BookingAlert.timeUp);
    expect(t.check(2, over, -1, repeatMinutes: 5), BookingAlert.timeUp);
    t.forgetExcept({2});
    expect(t.check(1, over, -2, repeatMinutes: 5), BookingAlert.timeUp);
    expect(t.check(2, over, -2, repeatMinutes: 5), isNull);
  });

  test('repeat setting is saved and defaults to 5 minutes', () {
    expect(BusinessSettings.fromJson({}).overtimeRepeatMinutes, 5);
    final s = BusinessSettings()..overtimeRepeatMinutes = 10;
    expect(BusinessSettings.fromJson(s.toJson()).overtimeRepeatMinutes, 10);
  });
}
