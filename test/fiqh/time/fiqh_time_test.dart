import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// اختبارات الوحدة T (`docs/fiqh/extraction/08-C-T.md`) وH0-09.
/// فجر 04:30 ومغرب 18:30 ثابتان. اليوم ١ = 2026-01-01.
void main() {
  const clock = FixedDayClock();
  final time = FiqhTime(clock);
  DateTime d(int day, [int h = 0, int m = 0]) => DateTime(2026, 1, day, h, m);
  DateTime fajr(int day) => d(day, 4, 30);
  DateTime maghrib(int day) => d(day, 18, 30);

  group('T-01 اليوم من الفجر إلى المغرب', () {
    test('ما قبل الفجر من ليلة اليوم السابق', () {
      expect(time.fiqhDayOf(d(5, 3, 0)), DateTime(2026, 1, 4));
      expect(time.fiqhDayOf(d(5, 4, 30)), DateTime(2026, 1, 5));
      expect(time.fiqhDayOf(d(5, 23, 0)), DateTime(2026, 1, 5));
    });
    test('النهار [فجر، مغرب)', () {
      expect(time.isDaytime(fajr(5)), isTrue);
      expect(time.isDaytime(maghrib(5)), isFalse);
      expect(time.isDaytime(d(5, 12)), isTrue);
      expect(time.isDaytime(d(5, 2)), isFalse);
    });
    test('الدم الليلي يُعدّ من فجر اليوم التالي', () {
      expect(time.countingStart(d(5, 22)), fajr(6));
      expect(time.countingStart(d(6, 2)), fajr(6));
      expect(time.countingStart(d(6, 9)), d(6, 9));
    });
  });

  group('T-02 الثلاثة الأولى', () {
    test('بدء عند الفجر → مغرب اليوم الثالث (ج م٤٩٥)', () {
      final r = time.threeDaysCompleteAt(fajr(1));
      expect(r.value, maghrib(3));
      expect(r.trace.map((t) => t.id), contains('T-02'));
      expect(r.trace.map((t) => t.id), contains('T-01'));
    });
    test('بدء ليلًا → كالفجر التالي', () {
      expect(time.threeDaysCompleteAt(d(1, 23)).value, maghrib(4));
    });
    test('تلفيق: بدء ظهر الأول → ظهر الرابع (ج م٤٩٥)', () {
      expect(time.threeDaysCompleteAt(d(1, 12)).value, d(4, 12));
    });
  });

  group('T-03 العشرة', () {
    test('بدء عند الفجر → فجر الحادي عشر؛ ليلة الحادي عشر ملحقة (ج م٤٩٨ هـ٣)', () {
      expect(time.tenDaysEndAt(fajr(1)).value, fajr(11));
    });
    test('بدء ظهر الأول → ظهر الحادي عشر، ٢٤٠ ساعة بلا جبر (ج م٤٩٩)', () {
      expect(time.tenDaysEndAt(d(1, 12)).value, d(11, 12));
    });
    test('بدء ليلًا → كالفجر التالي', () {
      expect(time.tenDaysEndAt(d(1, 20)).value, fajr(12));
    });
  });

  group('T-04 أقل الطهر', () {
    test('طهرت الساعة ١٠ → الساعة ١٠ من الحادي عشر (ج م٥٠٥)', () {
      expect(time.minTuhrEndsAt(d(6, 10)).value, d(16, 10));
      expect(time.minTuhrElapsed(stop: d(6, 10), newStart: d(16, 9)), isFalse);
      expect(time.minTuhrElapsed(stop: d(6, 10), newStart: d(16, 10)), isTrue);
    });
    test('طهرت قبل الفجر → الملاك فجر اليوم الأول', () {
      expect(time.minTuhrEndsAt(d(6, 3)).value, fajr(16));
    });
  });

  group('H0-09 الفترات اليسيرة', () {
    test('نصف ساعة مغتفرة، خمس ساعات قاطعة، وما بينهما قاطع (الشك)', () {
      expect(time.isNegligibleGap(const Duration(minutes: 30)).value, isTrue);
      expect(time.isNegligibleGap(const Duration(minutes: 15)).value, isTrue);
      expect(time.isNegligibleGap(const Duration(hours: 5)).value, isFalse);
      expect(time.isNegligibleGap(const Duration(minutes: 90)).value, isFalse);
      expect(time.isNegligibleGap(const Duration(hours: 5)).trace.single.id, 'H0-09');
    });
  });

  test('daysBetween كسري', () {
    expect(FiqhTime.daysBetween(d(1, 0), d(31, 0)), 30);
    expect(FiqhTime.daysBetween(d(1, 0), d(1, 6)), 0.25);
  });
}
