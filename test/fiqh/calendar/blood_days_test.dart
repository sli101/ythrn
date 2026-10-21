import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// أيام التقويم → أحداث المحرك؛ وكشف الحاجة إلى الساعة؛ والترحيل من الأحداث.
void main() {
  const clock = FixedDayClock();
  final time = FiqhTime(clock);
  final d1 = DateTime(2026, 3, 1);
  DateTime day(int n) => d1.add(Duration(days: n - 1));
  final today = day(30);

  test('مدى واحد ٧ أيام → بدء عند فجر الأول وانقطاع عند فجر الثامن', () {
    final days = [for (var i = 1; i <= 7; i++) BloodDay(day(i))];
    final ev = BloodCalendar.toEvents(days, clock, today: today);
    expect(ev.length, 2);
    expect(ev[0], isA<BloodStart>());
    expect(ev[0].at, clock.fajr(day(1)));
    expect(ev[1], isA<BloodStop>());
    expect(ev[1].at, clock.fajr(day(8)));
  });

  test('بدء ليلًا → مغرب اليوم؛ انقطاع نهارًا → زوال اليوم؛ الساعة الصريحة تغلب', () {
    final ev = BloodCalendar.toEvents([
      BloodDay(day(1), startPart: DayPart.night),
      BloodDay(day(2)),
      BloodDay(day(3), stopPart: DayPart.day),
    ], clock, today: today);
    expect(ev[0].at, clock.maghrib(day(1)));
    expect(ev[1].at, clock.dhuhr(day(3)));
    final exact = BloodCalendar.toEvents([BloodDay(day(1), startAt: day(1).add(const Duration(hours: 9)))], clock, today: today);
    expect(exact[0].at, day(1).add(const Duration(hours: 9)));
  });

  test('مديان منفصلان → أربعة أحداث؛ والمدى المنتهي باليوم بلا انقطاع = جارٍ', () {
    final ev = BloodCalendar.toEvents([BloodDay(day(1)), BloodDay(day(2)), BloodDay(day(29)), BloodDay(day(30))], clock, today: today);
    expect(ev.map((e) => e.runtimeType).toList(), [BloodStart, BloodStop, BloodStart]);
    final stopped = BloodCalendar.toEvents([BloodDay(day(30), stopPart: DayPart.day)], clock, today: today);
    expect(stopped.last, isA<BloodStop>());
  });

  test('الصفات: في أول يوم على البدء، وتغيّرها لاحقًا حدث تغيّر عند فجر اليوم', () {
    final ev = BloodCalendar.toEvents([
      BloodDay(day(1), props: BloodProps.wajid),
      BloodDay(day(2)),
      BloodDay(day(3), props: BloodProps.faqid),
      BloodDay(day(4), spots: true),
    ], clock, today: today);
    expect((ev[0] as BloodStart).props, BloodProps.wajid);
    final changes = ev.whereType<PropsChange>().toList();
    expect(changes.length, 2);
    expect(changes[0].at, clock.fajr(day(3)));
    expect(changes[0].props, BloodProps.faqid);
    expect(changes[1].spots, isTrue);
  });

  test('الترميز ذهابًا وإيابًا', () {
    final d = BloodDay(day(5), props: BloodProps.faqid, spots: true, startPart: DayPart.night, stopAt: day(5).add(const Duration(hours: 15)));
    expect(BloodDay.fromJson(d.toJson()), d);
  });

  test('كشف الحاجة إلى الساعة: ٣ أيام عند حافة الثلاثة تحتاج ساعة، و٧ أيام في العادة لا', () {
    final engine = FiqhEngine(time);
    const habit = HabitState(type: WomanType.mub, origin: HabitOrigin.declared);
    EngineResult eval(List<FiqhEvent> ev) => engine.evaluate(habit: habit, events: ev, now: clock.fajr(today), eligibility: const EligibilityInputs(ageLunarYears: Tri.known(30)));
    // ثلاثة أيام: هل تمّت الثلاثة يتوقف على ساعة البدء والانقطاع.
    final three = [for (var i = 1; i <= 3; i++) BloodDay(day(i))];
    final needs = BloodCalendar.precisionNeeds(three, clock, today: today, now: clock.fajr(today), evaluate: eval);
    expect(needs, isNotEmpty);
    // سبعة أيام بصفات الحيض: لا تختلف الساعة.
    final seven = [for (var i = 1; i <= 7; i++) BloodDay(day(i), props: i == 1 ? BloodProps.wajid : null)];
    expect(BloodCalendar.precisionNeeds(seven, clock, today: today, now: clock.fajr(today), evaluate: eval), isEmpty);
  });

  test('الترحيل من أحداث قديمة: مقطع بساعاته → أيامه، والجاري بلا انقطاع', () {
    final events = [BloodStart(day(1).add(const Duration(hours: 9)), props: BloodProps.wajid), BloodStop(day(4).add(const Duration(hours: 15))), BloodStart(day(29).add(const Duration(hours: 10)))];
    final days = BloodCalendar.fromEvents(events, time, now: day(30).add(const Duration(hours: 8)));
    expect(days.map((d) => d.day.day).toList(), [1, 2, 3, 4, 29, 30]);
    expect(days.first.startAt, day(1).add(const Duration(hours: 9)));
    expect(days.first.props, BloodProps.wajid);
    expect(days[3].stopAt, day(4).add(const Duration(hours: 15)));
    expect(days.last.stopAt, isNull);
    // الإياب يعيد الأحداث نفسها.
    final back = BloodCalendar.toEvents(days, clock, today: day(30));
    expect(back.map((e) => e.at).toList(), events.map((e) => e.at).toList());
  });
}
