import '../engine/eligibility.dart';
import '../engine/overflow_resolver.dart';
import 'habit_state.dart';
import 'tri.dart';

/// الملف الشخصي الفقهي (`docs/SPEC.md` §٣.١): كل ما يحتاجه المحرك من غير
/// الأحداث. كل مدخل قيمته الابتدائية «لا أعلم» حتى تُجيب (§٢.٤).
///
/// الموقع والمواقيت ليسا هنا؛ هما شأن التطبيق (T-01) ويصلان المحرك عبر
/// [DayClock].
class FiqhProfile {
  const FiqhProfile({
    this.habit = HabitState.initial,
    this.birth = const Tri.unknown(UnknownKind.dontRemember),
    this.approxAgeYears = const Tri.unknown(UnknownKind.dontRemember),
    this.isQurashi = const Tri.unknown(UnknownKind.dontRemember),
    this.hysterectomy = const Tri.unknown(UnknownKind.dontRemember),
    this.pregnant = const Tri.unknown(UnknownKind.dontRemember),
    this.lastBloodEnd = const Tri.unknown(UnknownKind.dontRemember),
    this.kinCount = const Tri.unknown(UnknownKind.dontRemember),
    this.kinConditionsMet = const Tri.unknown(UnknownKind.dontRemember),
    this.chosenCount = const Tri.unknown(UnknownKind.dontRemember),
    this.nasiyaHalfMonth,
    this.knownTimeDays = const [],
    this.timeWindow,
    this.ramadan = const [],
  });

  /// حالة العادة (§٤).
  final HabitState habit;

  /// تاريخ الميلاد (H1-01، H1-02). التقويم شأن الواجهة؛ العمر القمري يُحسب منه.
  final Tri<DateTime> birth;

  /// سن تقريبي بالسنين إذا جُهل تاريخ الميلاد (`SPEC` §٦).
  final Tri<double> approxAgeYears;

  final Tri<bool> isQurashi;
  final Tri<bool> hysterectomy;
  final Tri<bool> pregnant;

  /// انتهاء آخر حيض أو نفاس قبل تنصيب التطبيق (T-04).
  final Tri<DateTime> lastBloodEnd;

  /// عدد عادة قريبة (H7-07)؛ «لا أتذكر» = لا رجوع إلى الأقارب.
  final Tri<int> kinCount;

  /// تحقق شرطي الرجوع إلى الأقارب؛ عدم العلم بالمخالفة يحقق الشرط (م٢٢٢).
  final Tri<bool> kinConditionsMet;

  /// العدد المختار ٣–١٠ لفاقدة التمييز بلا أقارب (H7-04).
  final Tri<int> chosenCount;

  /// ناسية الوقت تتذكر أن حيضها في النصف الأول (١) أو الثاني (٢) من الشهر
  /// (H7-05). يحتاج تقويمًا هجريًّا ليتحول إلى [timeWindow]؛ يُحفظ هنا فقط.
  final int? nasiyaHalfMonth;

  /// أيام معلومة من وقت الناسية (H7-05).
  final List<DateTime> knownTimeDays;

  /// الوقت المحصور للناسية [من، إلى).
  final (DateTime, DateTime)? timeWindow;

  /// مدى رمضان وقضائه إن أُدخل (H9-15).
  final List<(DateTime, DateTime)> ramadan;

  /// مدخلات الأهلية عند لحظة [at] (عمر قمري من الميلاد أو من السن التقريبي).
  EligibilityInputs eligibilityAt(DateTime at) {
    final b = birth.valueOrNull;
    final approx = approxAgeYears.valueOrNull;
    final Tri<double> age = b != null
        ? Tri.known(EligibilityInputs.ageAt(b, at))
        : approx != null
            ? Tri.known(approx)
            : const Tri.unknown(UnknownKind.dontRemember);
    // سن تقريبي على حافة التسع أو الستين = شك في الإكمال (ج م٤٨٧، ج م٤٨٩).
    final doubtsNine = b == null && approx != null && approx >= 8.5 && approx <= 9.5;
    final doubtsSixty = b == null && approx != null && approx >= 59.5 && approx <= 60.5;
    return EligibilityInputs(
      ageLunarYears: doubtsNine || doubtsSixty ? const Tri.unknown(UnknownKind.dontRemember) : age,
      doubtsNine: doubtsNine,
      doubtsSixty: doubtsSixty,
      hysterectomy: hysterectomy,
      pregnant: pregnant,
      isQurashi: isQurashi,
    );
  }

  CountInputs get countInputs => CountInputs(
        kinCount: kinCount.valueOrNull,
        kinConditionsMet: kinConditionsMet,
        chosenCount: chosenCount.valueOrNull,
      );

  FiqhProfile copyWith({
    HabitState? habit,
    Tri<DateTime>? birth,
    Tri<double>? approxAgeYears,
    Tri<bool>? isQurashi,
    Tri<bool>? hysterectomy,
    Tri<bool>? pregnant,
    Tri<DateTime>? lastBloodEnd,
    Tri<int>? kinCount,
    Tri<bool>? kinConditionsMet,
    Tri<int>? chosenCount,
    int? nasiyaHalfMonth,
    List<DateTime>? knownTimeDays,
    (DateTime, DateTime)? timeWindow,
    List<(DateTime, DateTime)>? ramadan,
  }) =>
      FiqhProfile(
        habit: habit ?? this.habit,
        birth: birth ?? this.birth,
        approxAgeYears: approxAgeYears ?? this.approxAgeYears,
        isQurashi: isQurashi ?? this.isQurashi,
        hysterectomy: hysterectomy ?? this.hysterectomy,
        pregnant: pregnant ?? this.pregnant,
        lastBloodEnd: lastBloodEnd ?? this.lastBloodEnd,
        kinCount: kinCount ?? this.kinCount,
        kinConditionsMet: kinConditionsMet ?? this.kinConditionsMet,
        chosenCount: chosenCount ?? this.chosenCount,
        nasiyaHalfMonth: nasiyaHalfMonth ?? this.nasiyaHalfMonth,
        knownTimeDays: knownTimeDays ?? this.knownTimeDays,
        timeWindow: timeWindow ?? this.timeWindow,
        ramadan: ramadan ?? this.ramadan,
      );
}
