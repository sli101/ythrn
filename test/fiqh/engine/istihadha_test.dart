import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

void main() {
  final time = FiqhTime(const FixedDayClock());
  final engine = FiqhEngine(time);
  DateTime d(int day, [int h = 0, int m = 0]) => DateTime(2026, 1, day, h, m);
  DateTime fajr(int day) => d(day, 4, 30);
  const mud = HabitState(type: WomanType.mud);

  group('تعيين القسم (I1-04، I2-01)', () {
    test('بلا اختبار: غير معيَّن ومدخل معلَّق', () {
      final r = engine.evaluate(habit: mud, events: [BloodStart(fajr(1), props: BloodProps.faqid), BloodStop(fajr(3))], now: d(10));
      final iv = r.at(d(2, 12))!;
      expect(iv.state, DayState.istU);
      expect(iv.pendingInput, 'istihadhaTest');
      expect(iv.trace.map((t) => t.id), contains('I2-01'));
    });
    test('الاختبار يعيّن القسم من لحظته ويبقى حتى اختبار آخر', () {
      final r = engine.evaluate(
          habit: mud,
          events: [BloodStart(fajr(1), props: BloodProps.faqid), IstihadhaTest(d(1, 6), IstihadhaLevel.qalila), IstihadhaTest(d(2, 6), IstihadhaLevel.kathira), BloodStop(fajr(3))],
          now: d(10));
      expect(r.at(d(1, 5))!.state, DayState.istU);
      expect(r.at(d(1, 12))!.state, DayState.istQ);
      expect(r.at(d(2, 12))!.state, DayState.istK);
      expect(r.at(d(2, 12))!.trace.map((t) => t.id), contains('I1-04'));
    });
    test('اختبار استحاضة سابقة لا يسري على اللاحقة', () {
      final r = engine.evaluate(
          habit: mud,
          events: [
            BloodStart(fajr(1), props: BloodProps.faqid),
            IstihadhaTest(d(1, 6), IstihadhaLevel.kathira),
            BloodStop(fajr(3)),
            BloodStart(fajr(20), props: BloodProps.faqid),
            BloodStop(fajr(22)),
          ],
          now: d(30));
      expect(r.at(d(2, 12))!.state, DayState.istK);
      expect(r.at(d(21, 12))!.state, DayState.istU);
    });
  });

  group('الوظائف (I2)', () {
    const duties = IstihadhaDuties();
    test('القليلة: وضوء لكل صلاة بلا غسل', () {
      final d = duties.forLevel(IstihadhaLevel.qalila);
      expect(d.any((x) => x.rule.id == 'I2-02' && x.text.contains('الوضوء')), isTrue);
      expect(d.any((x) => x.text.contains('غسل واحد') || x.text.contains('ثلاثة أغسال')), isFalse);
    });
    test('المتوسطة: غسل واحد في اليوم احتياطًا وجوبًا', () {
      final d = duties.forLevel(IstihadhaLevel.mutawassita);
      final g = d.firstWhere((x) => x.text.contains('غسل واحد'));
      expect(g.rule.id, 'I2-03');
      expect(g.classification, 'ihtiyat_wujubi');
    });
    test('الكثيرة الصبيب: ثلاثة أغسال بلا وضوء؛ والمتقطعة: غسل عند كل بروز', () {
      final c = duties.forLevel(IstihadhaLevel.kathira);
      expect(c.any((x) => x.text.contains('ثلاثة أغسال')), isTrue);
      expect(c.any((x) => x.text == 'لا وضوء'), isTrue);
      final i = duties.forLevel(IstihadhaLevel.kathira, flow: IstihadhaFlow.intermittent);
      expect(i.any((x) => x.text.contains('عند كل بروز') && x.classification == 'ihtiyat_wujubi'), isTrue);
    });
    test('المشترك: يحرم مس المصحف ويجوز الصوم والمقاربة والمساجد والطلاق', () {
      final d = duties.forLevel(IstihadhaLevel.qalila);
      expect(d.where((x) => x.kind == DutyKind.prohibition).map((x) => x.rule.id), contains('I2-10'));
      expect(d.where((x) => x.kind == DutyKind.permission).map((x) => x.rule.id), containsAll(['I2-10', 'I2-12']));
    });
    test('بلا قسم: الاختبار أول الوظائف', () {
      expect(duties.forLevel(null).first.rule.id, 'I2-01');
    });
  });
}
