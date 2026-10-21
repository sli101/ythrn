import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// التقويم الهجري الحسابي (المدني): الحقبة، الذهاب والإياب، تواريخ معلومة،
/// ونافذة نصف الشهر للناسية (H7-05).
void main() {
  test('١ محرم ١ هـ = ١٩ تموز ٦٢٢ م (الميلادي المسقط) ورقمه صفر', () {
    const h = HijriDate(1, 1, 1);
    expect(h.dayNumber, 0);
    expect(h.toDate(), DateTime(622, 7, 19));
    expect(HijriDate.fromDate(DateTime(622, 7, 19)), h);
  });

  test('تواريخ معلومة بالتقويم الحسابي (±يوم عن الرؤية)', () {
    // ١ رمضان ١٤٤٦ هـ: ١ آذار ٢٠٢٥ م بأم القرى؛ و١ محرم ١٤٤٧ هـ: ٢٦ حزيران ٢٠٢٥ م.
    // الحسابي يوافق الرؤية أو يجاورها بيوم.
    expect(const HijriDate(1446, 9, 1).toDate().difference(DateTime(2025, 3, 1)).inDays.abs(), lessThanOrEqualTo(1));
    expect(const HijriDate(1447, 1, 1).toDate().difference(DateTime(2025, 6, 26)).inDays.abs(), lessThanOrEqualTo(1));
  });

  test('الذهاب والإياب يوميًّا على مدى سنتين', () {
    var d = DateTime(2024, 1, 1);
    HijriDate? prev;
    for (var i = 0; i < 730; i++) {
      final h = HijriDate.fromDate(d);
      expect(h.isValid, isTrue, reason: '$d → $h');
      expect(h.toDate(), d, reason: '$h');
      if (prev != null) expect(h.dayNumber, prev.dayNumber + 1);
      prev = h;
      d = d.add(const Duration(days: 1));
    }
  });

  test('طول الأشهر: الفردية ٣٠ والزوجية ٢٩ وذو الحجة ٣٠ في الكبيسة', () {
    expect(HijriDate.daysInMonth(1446, 1), 30);
    expect(HijriDate.daysInMonth(1446, 2), 29);
    expect(HijriDate.isLeapYear(1445), isTrue);
    expect(HijriDate.daysInMonth(1445, 12), 30);
    expect(HijriDate.daysInYear(1445), 355);
    expect(const HijriDate(1445, 12, 30).addDays(1), const HijriDate(1446, 1, 1));
  });

  test('نافذة الناسية: النصف الأول ١–١٥ والثاني ١٦ إلى آخر الشهر بفجر اليوم', () {
    const clock = FixedDayClock();
    final ref = DateTime(2025, 3, 10); // في رمضان ١٤٤٦.
    final h = HijriDate.fromDate(ref);
    final (f1, t1) = nasiyaHalfMonthWindow(1, ref, clock);
    expect(f1, clock.fajr(HijriDate(h.year, h.month, 1).toDate()));
    expect(t1, clock.fajr(HijriDate(h.year, h.month, 16).toDate()));
    expect(t1.difference(f1).inDays, 15);
    final (f2, t2) = nasiyaHalfMonthWindow(2, ref, clock);
    expect(f2, t1);
    expect(t2, clock.fajr(HijriDate(h.year, h.month + 1, 1).toDate()));
    expect(t2.difference(f2).inDays, HijriDate.daysInMonth(h.year, h.month) - 15);
  });
}
