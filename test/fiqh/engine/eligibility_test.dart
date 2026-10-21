import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

void main() {
  final time = FiqhTime(const FixedDayClock());
  final engine = FiqhEngine(time);
  DateTime d(int day, [int h = 0, int m = 0]) => DateTime(2026, 1, day, h, m);
  DateTime fajr(int day) => d(day, 4, 30);
  const mud = HabitState(type: WomanType.mud);
  final vw = HabitState(type: WomanType.vw, anchorDate: fajr(1), count: 6, origin: HabitOrigin.declared);
  final blood = [BloodStart(fajr(1), props: BloodProps.wajid), BloodStop(fajr(6))];

  test('العمر القمري يُحسب بـ ٣٥٤٫٣٦٧ يومًا للسنة', () {
    final age = EligibilityInputs.ageAt(DateTime(2017, 1, 1), DateTime(2026, 1, 1));
    expect(age, closeTo(9.27, 0.01));
  });

  test('H1-01a دون التسع: لا حيض ولا استحاضة', () {
    final r = engine.evaluate(habit: mud, events: blood, now: d(10), eligibility: const EligibilityInputs(ageLunarYears: Tri.known(8.0)));
    expect(r.at(d(3, 12))!.state, DayState.ghayr);
    expect(r.at(d(3, 12))!.trace.map((t) => t.id), containsAll(['H1-01a', 'I1-02']));
  });

  test('H1-01b الشاكة في التسع: واجد محل إشكال، فاقد ليس بحيض', () {
    final w = engine.evaluate(habit: mud, events: blood, now: d(10), eligibility: const EligibilityInputs(doubtsNine: true));
    expect(w.at(d(3, 12))!.state, DayState.hayd);
    expect(w.at(d(3, 12))!.classification, 'ishkal');
    final f = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.faqid), Expectation(fajr(1), ExpectationKind.willLastThreeDays, const Tri.known(true)), BloodStop(fajr(6))], now: d(10), eligibility: const EligibilityInputs(doubtsNine: true));
    expect(f.at(d(3, 12))!.state, DayState.istU);
  });

  test('H1-02/H1-06 بعد الستين: استحاضة احتياطًا وجوبًا؛ والشك في إكمالها يبني على عدمه', () {
    final old = engine.evaluate(habit: vw, events: blood, now: d(10), eligibility: const EligibilityInputs(ageLunarYears: Tri.known(61)));
    expect(old.at(d(3, 12))!.state, DayState.istU);
    expect(old.at(d(3, 12))!.classification, 'ihtiyat_wujubi');
    final doubt = engine.evaluate(habit: vw, events: blood, now: d(10), eligibility: const EligibilityInputs(doubtsSixty: true));
    expect(doubt.at(d(3, 12))!.state, DayState.hayd);
  });

  test('H1-05 استئصال الرحم: استحاضة', () {
    final r = engine.evaluate(habit: vw, events: blood, now: d(10), eligibility: const EligibilityInputs(hysterectomy: Tri.known(true)));
    expect(r.at(d(3, 12))!.state, DayState.istU);
    expect(r.at(d(3, 12))!.trace.map((t) => t.id), contains('H1-05'));
  });

  test('H1-03b الحامل ذات الوقت بعد عشرين يومًا بصفات الحيض: الجمع؛ وفي وقتها حيض', () {
    final later = HabitState(type: WomanType.vw, anchorDate: fajr(1), count: 6, origin: HabitOrigin.declared);
    final r = engine.evaluate(habit: later, events: [BloodStart(fajr(25), props: BloodProps.wajid), BloodStop(fajr(29))], now: d(31), eligibility: const EligibilityInputs(pregnant: Tri.known(true)));
    expect(r.at(d(26, 12))!.state, DayState.jam3);
    expect(r.at(d(26, 12))!.classification, 'ihtiyat_wujubi');
    final inTime = engine.evaluate(habit: vw, events: blood, now: d(10), eligibility: const EligibilityInputs(pregnant: Tri.known(true)));
    expect(inTime.at(d(3, 12))!.state, DayState.hayd);
  });

  group('H2 تمييز الدم', () {
    test('ليس دمًا أو مشكوك: طاهر', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), isBlood: const Tri.unknown(UnknownKind.dontRemember)), BloodStop(fajr(3))], now: d(10));
      expect(r.at(d(2, 12))!.state, DayState.tahir);
      expect(r.at(d(2, 12))!.trace.map((t) => t.id), contains('H2-04'));
    });
    test('المشكوك في أواخر حيض قائم يُلحق به', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.wajid), BloodStop(fajr(5)), BloodStart(fajr(7), isBlood: const Tri.unknown(UnknownKind.dontRemember)), BloodStop(fajr(8)), KursufTest(d(8, 6), KursufResult.clean)], now: d(20));
      expect(r.at(d(7, 12))!.state, DayState.hayd);
      expect(r.at(d(6, 12))!.state, DayState.jam3);
    });
    test('جرح مُحرز: غير', () {
      final r = engine.evaluate(habit: mud, events: [...blood, SourceNote(fajr(1), BloodSource.wound)], now: d(10));
      expect(r.at(d(3, 12))!.state, DayState.ghayr);
    });
    test('بكارة: مطوّقة غير، مستنقعة حيض، وبلا اختبار طهارة مع طلب الاختبار', () {
      final ringed = engine.evaluate(habit: mud, events: [...blood, SourceNote(fajr(1), BloodSource.doubtVirginityOrHayd), VirginityTest(d(1, 6), VirginityTestResult.ringed)], now: d(10));
      expect(ringed.at(d(3, 12))!.state, DayState.ghayr);
      final soaked = engine.evaluate(habit: mud, events: [...blood, SourceNote(fajr(1), BloodSource.doubtVirginityOrHayd), VirginityTest(d(1, 6), VirginityTestResult.soaked)], now: d(10));
      expect(soaked.at(d(3, 12))!.state, DayState.hayd);
      final none = engine.evaluate(habit: mud, events: [...blood, SourceNote(fajr(1), BloodSource.doubtVirginityOrHayd)], now: d(10));
      expect(none.at(d(3, 12))!.state, DayState.tahir);
      expect(none.at(d(3, 12))!.pendingInput, 'virginityTest');
    });
    test('مردد بين الجرح والحيض: غير الحائض؛ ومع حيض قائم يُلحق', () {
      final alone = engine.evaluate(habit: mud, events: [...blood, SourceNote(fajr(1), BloodSource.doubtWoundOrHayd)], now: d(10));
      expect(alone.at(d(3, 12))!.state, DayState.ghayr);
      final attached = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.wajid), BloodStop(fajr(5)), BloodStart(fajr(7)), SourceNote(fajr(7), BloodSource.doubtWoundOrHayd), BloodStop(fajr(9)), KursufTest(d(9, 6), KursufResult.clean)], now: d(20));
      expect(attached.at(d(8, 12))!.state, DayState.hayd);
    });
  });
}
