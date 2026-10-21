import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

void main() {
  final time = FiqhTime(const FixedDayClock());
  final engine = FiqhEngine(time);
  final duties = DutiesResolver(time);
  DateTime d(int day, [int h = 0, int m = 0]) => DateTime(2026, 1, day, h, m);
  DateTime fajr(int day) => d(day, 4, 30);
  const mud = HabitState(type: WomanType.mud);
  final vw = HabitState(type: WomanType.vw, anchorDate: fajr(1), count: 6, origin: HabitOrigin.declared);

  group('الوظائف بحسب الحالة', () {
    test('الحائض: محرمات بأثرها ومباحات وما بعد النقاء', () {
      final h = duties.forState(DayState.hayd);
      expect(h.where((x) => x.kind == DutyKind.prohibition).map((x) => x.rule.id), containsAll(['H9-01a', 'H9-02a', 'H9-04a', 'H9-06a']));
      expect(h.where((x) => x.kind == DutyKind.permission).map((x) => x.rule.id), contains('H9-03'));
      expect(h.any((x) => x.rule.id == 'H9-07a'), isTrue);
      expect(h.any((x) => x.rule.id == 'H9-08a'), isTrue);
    });
    test('النفساء: الخمسة بعلامة الاحتياط الوجوبي', () {
      final n = duties.forState(DayState.nifas);
      final five = n.where((x) => x.rule.id == 'N3-02');
      expect(five.length, greaterThanOrEqualTo(3));
      expect(five.every((x) => x.classification == 'ihtiyat_wujubi'), isTrue);
    });
    test('الجمع: صلاة وصوم مع تروك الحائض والطلاق محل إشكال', () {
      final j = duties.forState(DayState.jam3);
      expect(j.first.rule.id, 'H3-02');
      expect(j.any((x) => x.rule.id == 'H9-06b' && x.classification == 'ishkal'), isTrue);
      expect(j.any((x) => x.rule.id == 'H9-01a'), isTrue);
    });
    test('الدم المشكوك: وظائف المستحاضة مع تروك الحائض', () {
      final j = duties.forState(DayState.jam3M);
      expect(j.any((x) => x.rule.id == 'I2-01'), isTrue);
      expect(j.any((x) => x.rule.id == 'H9-04a'), isTrue);
    });
    test('الاستحاضة بقسمها', () {
      expect(duties.forState(DayState.istK).any((x) => x.text.contains('ثلاثة أغسال')), isTrue);
      expect(duties.forState(DayState.istK, flow: IstihadhaFlow.intermittent).any((x) => x.text.contains('عند كل بروز')), isTrue);
    });
  });

  group('التنبيهات (H9-07، H9-11، H9-15)', () {
    test('انتهاء الحيض نهارًا: غسل وصلاة الآن إن وسع الوقت', () {
      final r = engine.evaluate(habit: vw, events: [BloodStart(fajr(1)), BloodStop(d(6, 13)), KursufTest(d(6, 13, 30), KursufResult.clean), InnerContinuity(d(6, 13), const Tri.known(false))], now: d(10));
      expect(r.alerts.any((a) => a.rule.id == 'H9-07a'), isTrue);
      expect(r.alerts.any((a) => a.rule.id == 'H9-11a' && a.text.contains('صلي الآن')), isTrue);
    });
    test('انتهاء الحيض ليلًا ورمضان غدًا: الغسل قبل الفجر', () {
      final r = engine.evaluate(habit: vw, events: [BloodStart(fajr(1)), BloodStop(d(6, 23)), KursufTest(d(6, 23, 30), KursufResult.clean), RamadanNote(d(6, 23), isRamadan: true)], now: d(10));
      final a = r.alerts.firstWhere((a) => a.rule.id == 'H9-15');
      expect(a.at, fajr(7));
      final none = engine.evaluate(habit: vw, events: [BloodStart(fajr(1)), BloodStop(d(6, 23)), KursufTest(d(6, 23, 30), KursufResult.clean), RamadanNote(d(6, 23), isRamadan: false)], now: d(10));
      expect(none.alerts.any((a) => a.rule.id == 'H9-15'), isFalse);
    });
    test('بدء الحيض بعد مضي ما يسع الطهارة والصلاة: تنبيه القضاء', () {
      final r = engine.evaluate(habit: vw, events: [BloodStart(d(1, 13))], now: d(3));
      expect(r.alerts.any((a) => a.rule.id == 'H9-11a' && a.text.contains('الظهرين')), isTrue);
      final early = engine.evaluate(habit: vw, events: [BloodStart(d(1, 12, 10))], now: d(3));
      expect(early.alerts.any((a) => a.rule.id == 'H9-11b'), isTrue);
      final before = engine.evaluate(habit: vw, events: [BloodStart(d(1, 12, 2))], now: d(3));
      expect(before.alerts.any((a) => a.rule.id.startsWith('H9-11')), isFalse);
    });
  });

  group('سجل القضاء (H9-08، H9-14)', () {
    test('مبتدئة واجد تجاوز: قضاء صلوات الأيام بعد العدد إلى العشرة', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.wajid)], now: d(16), inputs: const CountInputs(kinCount: 7, kinConditionsMet: Tri.known(true)));
      expect(r.qada.prayerDays.length, 3);
      expect(r.qada.prayerDays.first, DateTime(2026, 1, 8));
    });
    test('صيام رمضان أيام الحيض يُقضى، وأيام الجمع احتياطًا، والحيض بعد المغرب لا يبطل صوم اليوم', () {
      final ramadan = [(DateTime(2026, 1, 1), DateTime(2026, 2, 1))];
      final r = engine.evaluate(habit: mud, events: [BloodStart(d(1, 20), props: BloodProps.wajid), BloodStop(fajr(5)), BloodStart(fajr(7), props: BloodProps.wajid), BloodStop(fajr(9)), KursufTest(d(9, 6), KursufResult.clean)], now: d(20), ramadan: ramadan);
      expect(r.qada.fastDays, [DateTime(2026, 1, 2), DateTime(2026, 1, 3), DateTime(2026, 1, 4), DateTime(2026, 1, 7), DateTime(2026, 1, 8)]);
      expect(r.qada.fastDaysIhtiyat, [DateTime(2026, 1, 5), DateTime(2026, 1, 6)]);
    });
  });
}
