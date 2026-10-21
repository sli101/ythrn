import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// اختبارات محرك الحيض الأساسي (H3، H5، H6). فجر 04:30 ومغرب 18:30.
void main() {
  final time = FiqhTime(const FixedDayClock());
  final engine = HaydEngine(time);
  DateTime d(int day, [int h = 0, int m = 0]) => DateTime(2026, 1, day, h, m);
  DateTime fajr(int day) => d(day, 4, 30);

  HabitState vw({int start = 1, int count = 7}) =>
      HabitState(type: WomanType.vw, anchorDate: fajr(start), count: count, origin: HabitOrigin.declared);
  const mud = HabitState(type: WomanType.mud);

  DayState? stateAt(EngineResult r, DateTime t) => r.at(t)?.state;

  group('H5 الحكم عند بدء الدم', () {
    test('ذات الوقت في وقتها → حيض فورًا ولو فاقدًا (H5-01)', () {
      final r = engine.evaluate(habit: vw(), events: [BloodStart(fajr(1), props: BloodProps.faqid)], now: d(1, 12));
      expect(stateAt(r, d(1, 10)), DayState.hayd);
      expect(r.at(d(1, 10))!.trace.map((t) => t.id), contains('H5-01'));
    });
    test('تعجيل يومين → حيض؛ تقدم خمسة أيام بلا إقرار → كغير ذات الوقت (H5-03)', () {
      final early = engine.evaluate(habit: vw(start: 10), events: [BloodStart(fajr(8), props: BloodProps.faqid)], now: d(8, 12));
      expect(stateAt(early, d(8, 10)), DayState.hayd);
      final tooEarly = engine.evaluate(habit: vw(start: 10), events: [BloodStart(fajr(5), props: BloodProps.faqid)], now: d(5, 12));
      expect(stateAt(tooEarly, d(5, 10)), DayState.jam3M);
      final declared = engine.evaluate(
          habit: vw(start: 10), events: [BloodStart(fajr(5), props: BloodProps.faqid), IsEarlyHabit(fajr(5), const Tri.known(true))], now: d(5, 12));
      expect(stateAt(declared, d(5, 10)), DayState.hayd);
    });
    test('غير ذات الوقت: واجد → حيض؛ فاقد مع الشك → جمع؛ فاقد مع العلم → حيض (H5-02)', () {
      expect(stateAt(engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.wajid)], now: d(1, 12)), d(1, 10)), DayState.hayd);
      final doubt = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.faqid)], now: d(1, 12));
      expect(stateAt(doubt, d(1, 10)), DayState.jam3M);
      expect(doubt.at(d(1, 10))!.classification, 'ihtiyat_wujubi');
      final knows = engine.evaluate(
          habit: mud,
          events: [BloodStart(fajr(1), props: BloodProps.faqid), Expectation(fajr(1), ExpectationKind.willLastThreeDays, const Tri.known(true))],
          now: d(1, 12));
      expect(stateAt(knows, d(1, 10)), DayState.hayd);
    });
  });

  group('H3 الثلاثة والعشرة', () {
    test('تمام الثلاثة متصلًا يثبت الحيض من أوله (الجمع → حيض)', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.faqid)], now: d(4, 12));
      expect(stateAt(r, d(1, 10)), DayState.hayd);
      expect(stateAt(r, d(4, 10)), DayState.hayd);
    });
    test('انقطع قبل الثلاثة → استحاضة (H3-01)', () {
      final r = engine.evaluate(habit: vw(), events: [BloodStart(fajr(1)), BloodStop(d(3, 10))], now: d(5));
      expect(stateAt(r, d(2, 10)), DayState.istU);
      expect(r.at(d(2, 10))!.trace.map((t) => t.id), contains('H5-01'));
    });
    test('نقاء متخلل بين دمين ضمن العشرة → جمع (H3-02)', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.wajid), BloodStop(fajr(5)), BloodStart(fajr(7)), BloodStop(fajr(9)), KursufTest(d(9, 6), KursufResult.clean)], now: d(12));
      expect(stateAt(r, d(3)), DayState.hayd);
      expect(stateAt(r, d(5, 12)), DayState.jam3);
      expect(stateAt(r, d(7, 12)), DayState.hayd);
      expect(stateAt(r, d(10, 12)), DayState.tahir);
      expect(r.isFullyCovered, isTrue);
    });
    test('الدم بعد العشرة لذات الوقتية والعددية → أيام العادة حيض والباقي استحاضة (H7-01)', () {
      final r = engine.evaluate(habit: vw(), events: [BloodStart(fajr(1))], now: d(13));
      expect(r.isFullyCovered, isTrue);
      expect(stateAt(r, d(3, 12)), DayState.hayd);
      expect(stateAt(r, d(7, 12)), DayState.hayd);
      expect(stateAt(r, d(8, 12)), DayState.istU);
      expect(stateAt(r, d(12, 12)), DayState.istU);
      expect(r.at(d(8, 12))!.trace.map((t) => t.id), contains('H7-01a'));
    });
    test('دم ثانٍ قبل أقل الطهر من حيضة محكوم بها: دمان تساويا → الأول حيض (H8-01a)', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.wajid), BloodStop(fajr(6)), KursufTest(d(6, 6), KursufResult.clean), BloodStart(fajr(12), props: BloodProps.wajid)], now: d(15, 12));
      expect(r.isFullyCovered, isTrue);
      expect(stateAt(r, d(3, 12)), DayState.hayd);
      expect(stateAt(r, d(13, 12)), DayState.istU);
      expect(r.at(d(13, 12))!.trace.map((t) => t.id), contains('H8-01a'));
    });
    test('دم قبل أقل الطهر من حيض سابق (lastBloodEnd) → استحاضة (H3-03)', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(5), props: BloodProps.wajid)], now: d(8), lastBloodEnd: d(1, 10));
      expect(stateAt(r, d(6)), DayState.istU);
    });
  });

  group('H6 الانقطاع والاستبراء', () {
    final base = [BloodStart(fajr(1), props: BloodProps.wajid), BloodStop(fajr(5))];
    test('تحتمل البقاء داخلًا ولم تستبرئ → ينتظر القطنة (H6-01)', () {
      final r = engine.evaluate(habit: mud, events: base, now: d(6));
      final iv = r.at(d(5, 12))!;
      expect(iv.state, DayState.pending);
      expect(iv.pendingInput, 'kursufTest');
    });
    test('لا تحتمل البقاء → طهر', () {
      final r = engine.evaluate(habit: mud, events: [...base, InnerContinuity(fajr(5), const Tri.known(false))], now: d(6));
      expect(stateAt(r, d(5, 12)), DayState.tahir);
    });
    test('قطنة نظيفة → طهر؛ مع الاطمئنان بالعود → جمع إلى العشرة (H6-02)', () {
      expect(stateAt(engine.evaluate(habit: mud, events: [...base, KursufTest(d(5, 6), KursufResult.clean)], now: d(6)), d(5, 12)), DayState.tahir);
      final r = engine.evaluate(
          habit: mud,
          events: [...base, KursufTest(d(5, 6), KursufResult.clean), Expectation(fajr(5), ExpectationKind.willReturnBeforeTen, const Tri.known(true))],
          now: d(13));
      expect(stateAt(r, d(7)), DayState.jam3);
      expect(stateAt(r, d(12)), DayState.tahir);
    });
    test('قطنة ملوثة: مضطربة → حيض إلى العشرة (H6-03)', () {
      final r = engine.evaluate(habit: mud, events: [...base, KursufTest(d(5, 6), KursufResult.stained)], now: d(12));
      expect(stateAt(r, d(8)), DayState.hayd);
      expect(stateAt(r, d(10)), DayState.hayd);
    });
    test('قطنة ملوثة في أيام العادة → حيض إلى تمام العادة ثم بحسب علمها', () {
      final stained = [...base, KursufTest(d(5, 6), KursufResult.stained)];
      final r = engine.evaluate(habit: vw(count: 7), events: stained, now: d(12));
      expect(stateAt(r, d(6)), DayState.hayd);
      expect(stateAt(r, d(9)), DayState.istU, reason: 'بعد العادة مع التردد: غسل وعمل المستحاضة');
      final knowsStop = engine.evaluate(habit: vw(count: 7), events: [...stained, Expectation(fajr(8), ExpectationKind.willExceedTen, const Tri.known(false))], now: d(12));
      expect(stateAt(knowsStop, d(9)), DayState.hayd);
    });
  });
}
