import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// اشتقاق العادة من التقويم: حيضتان متوافقتان في شهرين سابقين → ذات عادة
/// وقتية وعددية بلا سؤال، والحيضة الجارية لا تدخل.
void main() {
  const clock = FixedDayClock();
  final time = FiqhTime(clock);
  final engine = FiqhEngine(time);
  final base = DateTime(2026, 1, 1);
  DateTime day(int n) => base.add(Duration(days: n - 1));

  test('حيضتان ٧ أيام بفاصل ٣٠ يومًا → VW بعدد ٧ ثم الحيضة الجارية لا تُحتسب', () {
    final days = [
      for (var i = 1; i <= 7; i++) BloodDay(day(i), props: i == 1 ? BloodProps.wajid : null),
      for (var i = 31; i <= 37; i++) BloodDay(day(i), props: i == 31 ? BloodProps.wajid : null),
      for (var i = 61; i <= 63; i++) BloodDay(day(i)),
    ];
    final today = day(63);
    final now = clock.fajr(today).add(const Duration(hours: 6));
    final events = BloodCalendar.toEvents(days, clock, today: today);
    const initial = HabitState(type: WomanType.mub, origin: HabitOrigin.declared);
    final r = engine.evaluate(habit: initial, events: events, now: now, eligibility: const EligibilityInputs(ageLunarYears: Tri.known(30)));
    const derivation = HabitDerivation();
    final cycles = derivation.closedCycles(r, before: clock.fajr(day(61)));
    expect(cycles.length, 2);
    expect(cycles[0].start, clock.fajr(day(1)));
    expect(cycles[0].bloodDays, closeTo(7, 0.01));
    final habit = derivation.derive(initial, r, before: clock.fajr(day(61)));
    expect(habit.type, WomanType.vw);
    expect(habit.count, 7);
    expect(habit.history.length, 2);
    // إعادة الاشتقاق لا تكرر الحيضات.
    expect(derivation.derive(habit, r, before: clock.fajr(day(61))).history.length, 2);
  });
}
