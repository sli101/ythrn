import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

void main() {
  final time = FiqhTime(const FixedDayClock());
  final builder = SegmentBuilder(time);
  DateTime d(int day, [int h = 0, int m = 0]) => DateTime(2026, 1, day, h, m);

  test('بدء وانقطاع → مقطع واحد', () {
    final s = builder.build([BloodStart(d(1, 5)), BloodStop(d(4, 5))]).value;
    expect(s, hasLength(1));
    expect(s.single.start, d(1, 5));
    expect(s.single.end, d(4, 5));
  });

  test('انقطاع نصف ساعة ثم عود → مقطع واحد (H0-09)', () {
    final r = builder.build([BloodStart(d(1, 5)), BloodStop(d(2, 10)), BloodStart(d(2, 10, 30)), BloodStop(d(4, 5))]);
    expect(r.value, hasLength(1));
    expect(r.value.single.negligibleGaps, [d(2, 10)]);
    expect(r.trace.map((t) => t.id), contains('H0-09'));
  });

  test('انقطاع خمس ساعات → مقطعان', () {
    final s = builder.build([BloodStart(d(1, 5)), BloodStop(d(2, 10)), BloodStart(d(2, 15)), BloodStop(d(4, 5))]).value;
    expect(s, hasLength(2));
  });

  test('FullStop يسير لا يقطع وغير يسير يقطع', () {
    expect(builder.build([BloodStart(d(1, 5)), FullStop(d(2, 10), const Duration(minutes: 20)), BloodStop(d(4))]).value, hasLength(1));
    final s = builder.build([BloodStart(d(1, 5)), FullStop(d(2, 10), const Duration(hours: 5)), BloodStop(d(4))]).value;
    expect(s, hasLength(2));
    expect(s[1].start, d(2, 15));
  });

  test('الدم الجاري مقطع مفتوح', () {
    final s = builder.build([BloodStart(d(1, 5))]).value;
    expect(s.single.ongoing, isTrue);
  });

  test('تغيّر الصفات داخل المقطع', () {
    final s = builder.build([BloodStart(d(1, 5), props: BloodProps.wajid), PropsChange(d(3, 5), BloodProps.faqid), BloodStop(d(6))]).value.single;
    expect(s.propsAt(d(2)), BloodProps.wajid);
    expect(s.propsAt(d(4)), BloodProps.faqid);
  });

  test('«ليس دمًا» لا يفتح مقطعًا', () {
    expect(builder.build([BloodStart(d(1, 5), isBlood: const Tri.known(false))]).value, isEmpty);
  });
}
