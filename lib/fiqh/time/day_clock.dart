/// مصدر المواقيت لكل يوم تقويمي (T-01، H9-11).
///
/// التطبيق يزوّد تنفيذًا بمكتبة مواقيت على الطريقة الشيعية مع ضبط يدوي؛
/// والاختبارات تستعمل [FixedDayClock].
abstract class DayClock {
  const DayClock();

  /// الفجر الصادق لليوم التقويمي الذي يقع فيه [date] (الوقت يُهمل).
  DateTime fajr(DateTime date);

  /// طلوع الشمس (آخر وقت صلاة الصبح).
  DateTime sunrise(DateTime date);

  /// الزوال (أول وقت الظهرين).
  DateTime dhuhr(DateTime date);

  /// المغرب (ذهاب الحمرة المشرقية): أول وقت العشاءين ونهاية النهار الفقهي.
  DateTime maghrib(DateTime date);

  /// منتصف الليل الشرعي: منتصف ما بين المغرب وفجر اليوم التالي (آخر وقت العشاءين).
  DateTime midnight(DateTime date) {
    final m = maghrib(date);
    final f = fajr(DateTime(date.year, date.month, date.day + 1));
    return m.add(Duration(minutes: f.difference(m).inMinutes ~/ 2));
  }
}

/// مواقيت ثابتة كل يوم.
class FixedDayClock extends DayClock {
  const FixedDayClock({
    this.fajrTime = const Duration(hours: 4, minutes: 30),
    this.sunriseTime = const Duration(hours: 6),
    this.dhuhrTime = const Duration(hours: 12),
    this.maghribTime = const Duration(hours: 18, minutes: 30),
  });

  final Duration fajrTime;
  final Duration sunriseTime;
  final Duration dhuhrTime;
  final Duration maghribTime;

  @override
  DateTime fajr(DateTime date) => _midnight(date).add(fajrTime);

  @override
  DateTime sunrise(DateTime date) => _midnight(date).add(sunriseTime);

  @override
  DateTime dhuhr(DateTime date) => _midnight(date).add(dhuhrTime);

  @override
  DateTime maghrib(DateTime date) => _midnight(date).add(maghribTime);

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);
}
