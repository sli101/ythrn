import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// اختبارات محرك النفاس والسقط (N1، N2، M). فجر 04:30 ومغرب 18:30.
void main() {
  final time = FiqhTime(const FixedDayClock());
  final engine = FiqhEngine(time);
  DateTime d(int day, [int h = 0, int m = 0]) => DateTime(2026, 1, day, h, m);
  DateTime fajr(int day) => d(day, 4, 30);
  DayState? at(EngineResult r, DateTime t) => r.at(t)?.state;

  const w7 = HabitState(type: WomanType.w, count: 7, origin: HabitOrigin.declared);
  const mud = HabitState(type: WomanType.mud);

  group('N2-01 الدم الواحد', () {
    test('لا يتجاوز العشرة → كله نفاس', () {
      final r = engine.evaluate(habit: w7, events: [Birth(fajr(1)), BloodStart(fajr(1)), BloodStop(fajr(9))], now: d(20));
      expect(at(r, d(5, 12)), DayState.nifas);
      expect(at(r, d(8, 12)), DayState.nifas);
      expect(at(r, d(12, 12)), DayState.tahir);
    });
    test('تجاوز وذات عدد ٧ من الفجر → سبعة نفاس والباقي استحاضة (ج م٦٢٢)', () {
      final r = engine.evaluate(habit: w7, events: [Birth(fajr(1)), BloodStart(fajr(1))], now: d(13));
      expect(at(r, d(7, 12)), DayState.nifas);
      expect(at(r, d(8, 3)), DayState.nifas, reason: 'ليلة الثامن نفاس');
      expect(at(r, d(8, 12)), DayState.istU);
    });
    test('تجاوز من ظهر الأول → إلى ظهر الثامن (تلفيق)', () {
      final r = engine.evaluate(habit: w7, events: [Birth(d(1, 12)), BloodStart(d(1, 12))], now: d(13));
      expect(at(r, d(8, 11)), DayState.nifas);
      expect(at(r, d(8, 13)), DayState.istU);
    });
    test('تجاوز بلا عدد → عشرة', () {
      final r = engine.evaluate(habit: mud, events: [Birth(fajr(1)), BloodStart(fajr(1))], now: d(14));
      expect(at(r, d(10, 12)), DayState.nifas);
      expect(at(r, d(11, 12)), DayState.istU);
      expect(r.at(d(10, 12))!.trace.map((t) => t.id), contains('N2-01'));
    });
    test('الناسية تجعل أكبر عدد محتمل', () {
      const nas = HabitState(type: WomanType.nasC, memory: NasiyaMemory(countMin: 5, countMax: 6));
      final r = engine.evaluate(habit: nas, events: [Birth(fajr(1)), BloodStart(fajr(1))], now: d(14));
      expect(at(r, d(6, 12)), DayState.nifas);
      expect(at(r, d(7, 12)), DayState.istU);
    });
    test('الناقصة بحد أعلى ثمانية (N2-02)', () {
      const def = HabitState(type: WomanType.mud, deficient: DeficientBounds(max: 8));
      final r = engine.evaluate(habit: def, events: [Birth(fajr(1)), BloodStart(fajr(1))], now: d(14));
      expect(at(r, d(8, 12)), DayState.nifas);
      expect(at(r, d(9, 12)), DayState.istU);
    });
  });

  group('N2-03 الدماء المتعددة', () {
    test('يومان ثم نقاء ثم دم من السادس تجاوز: عددية ٧ (م٢٥٦)', () {
      final r = engine.evaluate(habit: w7, events: [Birth(fajr(1)), BloodStart(fajr(1)), BloodStop(fajr(3)), BloodStart(fajr(6))], now: d(13));
      expect(at(r, d(2, 12)), DayState.nifas);
      expect(at(r, d(4, 12)), DayState.jam3N);
      expect(at(r, d(7, 12)), DayState.nifas);
      expect(at(r, d(9, 12)), DayState.jam3NM);
      expect(r.at(d(9, 12))!.classification, 'ihtiyat_wujubi');
      expect(at(r, d(11, 12)), DayState.istU);
    });
    test('بلا عدد: ما قبل العشرة نفاس والنقاء جمع وما بعدها استحاضة', () {
      final r = engine.evaluate(habit: mud, events: [Birth(fajr(1)), BloodStart(fajr(1)), BloodStop(fajr(3)), BloodStart(fajr(6))], now: d(13));
      expect(at(r, d(4, 12)), DayState.jam3N);
      expect(at(r, d(9, 12)), DayState.nifas);
      expect(at(r, d(11, 12)), DayState.istU);
    });
  });

  group('N1-05 ولادتان', () {
    test('على رأس العشرة → نفاسان متواليان بلا فصل', () {
      final r = engine.evaluate(habit: mud, events: [Birth(fajr(1)), BloodStart(fajr(1)), Birth(fajr(11)), BloodStop(fajr(21))], now: d(25));
      expect(at(r, d(5, 12)), DayState.nifas);
      expect(at(r, d(15, 12)), DayState.nifas);
      expect(at(r, d(20, 12)), DayState.nifas);
      expect(r.isFullyCovered, isTrue);
    });
    test('تداخل العشرتين → النقاء بينهما جمع', () {
      final r = engine.evaluate(habit: mud, events: [Birth(fajr(1)), BloodStart(fajr(1)), BloodStop(fajr(4)), Birth(fajr(5)), BloodStart(fajr(5)), BloodStop(fajr(11))], now: d(15));
      expect(at(r, d(2, 12)), DayState.nifas);
      expect(at(r, d(4, 12)), DayState.jam3N);
      expect(at(r, d(8, 12)), DayState.nifas);
    });
  });

  group('N2-04 ما بعد النفاس', () {
    test('دم ثانٍ في عشرة الولادة نفاس إلى العشرة ثم استحاضة (N2-03)', () {
      final r = engine.evaluate(habit: mud, events: [Birth(fajr(1)), BloodStart(fajr(1)), BloodStop(fajr(6)), BloodStart(fajr(9), props: BloodProps.wajid), BloodStop(fajr(14))], now: d(20));
      expect(at(r, d(5, 12)), DayState.nifas);
      expect(at(r, d(7, 12)), DayState.jam3N);
      expect(at(r, d(10, 12)), DayState.nifas);
      expect(at(r, d(12, 12)), DayState.istU);
    });
    test('عشرة الاستحاضة بعد تمام النفاس مطلقًا ولو بصفات الحيض', () {
      final r = engine.evaluate(habit: mud, events: [Birth(fajr(1)), BloodStart(fajr(1)), BloodStop(fajr(6)), BloodStart(fajr(13), props: BloodProps.wajid), BloodStop(fajr(16))], now: d(20));
      expect(at(r, d(5, 12)), DayState.nifas);
      expect(at(r, d(14, 12)), DayState.istU);
      expect(r.at(d(14, 12))!.trace.map((t) => t.id), contains('H3-03'));
    });
    test('ذات الوقت تنتظر أيام عادتها', () {
      final vw = HabitState(type: WomanType.vw, anchorDate: fajr(20), count: 6, origin: HabitOrigin.declared);
      final r = engine.evaluate(habit: vw, events: [Birth(fajr(10)), BloodStart(fajr(10)), BloodStop(fajr(16)), BloodStart(fajr(20), props: BloodProps.wajid), BloodStop(fajr(26)), BloodStart(fajr(50)), BloodStop(fajr(56))], now: d(60));
      expect(at(r, d(12, 12)), DayState.nifas);
      expect(at(r, d(22, 12)), DayState.istU);
      expect(at(r, d(52, 12)), DayState.hayd);
    });
  });

  group('M السقط', () {
    test('مضغة: لا نفاس؛ الدم الواجد حيض', () {
      final r = engine.evaluate(habit: mud, events: [Miscarriage(fajr(1), stage: MiscarriageStage.mudgha), BloodStart(fajr(1), props: BloodProps.wajid), BloodStop(fajr(5))], now: d(10));
      expect(at(r, d(3, 12)), DayState.hayd);
      expect(r.notices.map((n) => n.id), contains('M-01'));
    });
    test('متخلق: نفاس؛ وبعد ولوج الروح تنبيه غسل مس الميت', () {
      final r = engine.evaluate(habit: mud, events: [Miscarriage(fajr(1), stage: MiscarriageStage.formed, ensouled: const Tri.known(true)), BloodStart(fajr(1)), BloodStop(fajr(6))], now: d(10));
      expect(at(r, d(3, 12)), DayState.nifas);
      expect(r.notices.map((n) => n.id), contains('M-06'));
    });
    test('مرحلة مجهولة → معلَّق', () {
      final r = engine.evaluate(habit: mud, events: [Miscarriage(fajr(1)), BloodStart(fajr(1))], now: d(5));
      final iv = r.at(d(3, 12))!;
      expect(iv.state, DayState.pending);
      expect(iv.pendingInput, 'miscarriageStage');
    });
  });

  test('N1-01 دم بعد أحد عشر يومًا من الولادة ليس نفاسًا', () {
    final r = engine.evaluate(habit: mud, events: [Birth(fajr(1)), BloodStart(fajr(12), props: BloodProps.wajid), BloodStop(fajr(16))], now: d(20));
    expect(at(r, d(13, 12)), DayState.hayd);
    expect(at(r, d(5, 12)), DayState.tahir);
  });
}
