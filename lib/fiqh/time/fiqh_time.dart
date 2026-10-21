import '../model/rule_ref.dart';
import 'day_clock.dart';

/// حسابات الزمن الفقهي (الوحدة T في `docs/fiqh/extraction/08-C-T.md`).
///
/// الاصطلاح: «اليوم» من الفجر الصادق إلى المغرب، والليلة التي تليه تحمل رقمه
/// (T-01). الليل لا يُعدّ في الثلاثة ولا في العشرة، لكن الزيادة فيه لا تضر.
class FiqhTime {
  const FiqhTime(this.clock);

  final DayClock clock;

  /// الانقطاع التام المغتفر في أثناء الثلاثة الأولى (H0-09: ربع ساعة إلى نصف).
  static const negligibleGap = Duration(minutes: 30);

  // ---------------------------------------------------------------- اليوم

  /// اليوم الفقهي الذي تقع فيه اللحظة: إن كانت بعد المغرب وقبل منتصف الليل
  /// فهي من ليلة ذلك اليوم؛ وإن كانت بعد منتصف الليل وقبل الفجر فهي من ليلة
  /// اليوم السابق. يعيد منتصف ليل اليوم التقويمي الذي يحمل الرقم.
  DateTime fiqhDayOf(DateTime t) {
    final day = DateTime(t.year, t.month, t.day);
    return t.isBefore(clock.fajr(day)) ? day.subtract(const Duration(days: 1)) : day;
  }

  /// هل اللحظة في النهار [فجر، مغرب)؟
  bool isDaytime(DateTime t) {
    final day = DateTime(t.year, t.month, t.day);
    return !t.isBefore(clock.fajr(day)) && t.isBefore(clock.maghrib(day));
  }

  /// بداية العدّ لدمٍ بدأ في [start]: إن بدأ في النهار فهي لحظته (تلفيق)،
  /// وإن بدأ ليلًا فهي فجر اليوم التالي (T-02، T-05: الدم الليلي يُلحق بلا عدّ).
  DateTime countingStart(DateTime start) {
    if (isDaytime(start)) return start;
    final day = fiqhDayOf(start);
    return clock.fajr(day.add(const Duration(days: 1)));
  }

  bool _startsAtFajr(DateTime t) => t == clock.fajr(DateTime(t.year, t.month, t.day));

  // ---------------------------------------------------------------- الحدود

  /// لحظة تمام الثلاثة الأولى لدمٍ بدأ في [start] (T-02، H3-01).
  ///
  /// بدء عند الفجر أو ليلًا → نهاية نهار اليوم الثالث (المغرب، على الأشد لأن
  /// الغروب/المغرب محل إشكال T-01). بدء في الساعة س من النهار → الساعة س من
  /// اليوم الرابع.
  Traced<DateTime> threeDaysCompleteAt(DateTime start) {
    final s = countingStart(start);
    if (_startsAtFajr(s)) {
      final third = fiqhDayOf(s).add(const Duration(days: 2));
      return Traced(clock.maghrib(third), const [RuleRef('T-02', 'بدء عند الفجر أو ليلًا: إلى مغرب الثالث'), RuleRef('T-01')]);
    }
    return Traced(_sameClockAfterDays(s, 3), const [RuleRef('T-02', 'تلفيق: الساعة نفسها من الرابع')]);
  }

  /// نهاية العشرة لدمٍ بدأ في [start] (T-03): ما بعدها تجاوز.
  ///
  /// بدء عند الفجر أو ليلًا → فجر اليوم الحادي عشر (ليلة الحادي عشر ملحقة
  /// بالحيض، ج م٤٩٨ هـ٣). بدء في الساعة س نهارًا → الساعة س من الحادي عشر
  /// (٢٤٠ ساعة) بلا جبر من الليل.
  Traced<DateTime> tenDaysEndAt(DateTime start) {
    final s = countingStart(start);
    if (_startsAtFajr(s)) {
      final eleventh = fiqhDayOf(s).add(const Duration(days: 10));
      return Traced(clock.fajr(eleventh), const [RuleRef('T-03', 'بدء عند الفجر: ليلة الحادي عشر ملحقة')]);
    }
    return Traced(_sameClockAfterDays(s, 10), const [RuleRef('T-03', '٢٤٠ ساعة')]);
  }

  /// نهاية أقل الطهر لنقاءٍ تامٍّ بدأ في [stop] (T-04، H3-03): دم يبدأ قبلها ليس حيضًا.
  ///
  /// كحساب العشرة: إن طهرت قبل الفجر فالملاك فجر اليوم الأول؛ وإن طهرت الساعة
  /// س نهارًا فالنهاية الساعة س من الحادي عشر بلا جبر من الليل (ج م٥٠٥).
  Traced<DateTime> minTuhrEndsAt(DateTime stop) {
    final s = countingStart(stop);
    if (_startsAtFajr(s)) {
      final eleventh = fiqhDayOf(s).add(const Duration(days: 10));
      return Traced(clock.fajr(eleventh), const [RuleRef('T-04', 'طهرت قبل الفجر: الملاك فجر اليوم الأول')]);
    }
    return Traced(_sameClockAfterDays(s, 10), const [RuleRef('T-04', '٢٤٠ ساعة من لحظة النقاء')]);
  }

  /// هل انقضى أقل الطهر بين انقطاع [stop] وبدء دم جديد في [newStart]؟
  bool minTuhrElapsed({required DateTime stop, required DateTime newStart}) =>
      !newStart.isBefore(minTuhrEndsAt(stop).value);

  // ---------------------------------------------------------------- الفواصل

  /// هل الانقطاع التام (ظاهرًا وباطنًا) مغتفر في أثناء الثلاثة الأولى؟ (H0-09)
  ///
  /// ≤ نصف ساعة مغتفر؛ «عدة ساعات» قاطع؛ والشك في كونه متعارفًا → ليس بحيض،
  /// فكل ما زاد على النصف ساعة يُعدّ قاطعًا.
  Traced<bool> isNegligibleGap(Duration gap) => Traced(
        gap <= negligibleGap,
        [RuleRef('H0-09', gap <= negligibleGap ? 'فترة يسيرة متعارفة' : 'انقطاع غير يسير أو مشكوك')],
      );

  // ---------------------------------------------------------------- أدوات

  /// الساعة نفسها بعد [days] يومًا تقويميًّا.
  static DateTime _sameClockAfterDays(DateTime t, int days) =>
      DateTime(t.year, t.month, t.day + days, t.hour, t.minute, t.second);

  /// عدد الأيام (كسريًّا) بين لحظتين.
  static double daysBetween(DateTime a, DateTime b) =>
      b.difference(a).inMinutes / Duration.minutesPerDay;
}
