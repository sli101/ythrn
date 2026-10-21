import '../fiqh.dart';

import 'golden_case.dart';

/// يحوّل أرقام أيام السيناريو ولحظاته إلى أزمنة فعلية بمواقيت الحالة.
///
/// اليوم ١ = 2026-03-01. الليلة التي تلي يومًا تحمل رقمه (T-01).
class Scenario {
  Scenario(this.c)
      : clock = _clock(c);

  static FixedDayClock _clock(GoldenCase c) => FixedDayClock(
          fajrTime: _parseHm(c.clock?['fajr'] as String?) ?? const Duration(hours: 4, minutes: 30),
          maghribTime: _parseHm(c.clock?['maghrib'] as String?) ?? const Duration(hours: 18, minutes: 30),
        );


  final GoldenCase c;
  final FixedDayClock clock;
  FiqhTime get time => FiqhTime(clock);

  static final DateTime base = DateTime(2026, 3, 1);

  /// منتصف ليل اليوم التقويمي للرقم (قد يكون سالبًا لما قبل اليوم ١).
  DateTime date(int day) => base.add(Duration(days: day - 1));
  DateTime fajr(int day) => clock.fajr(date(day));
  DateTime maghrib(int day) => clock.maghrib(date(day));

  /// رقم اليوم الفقهي للحظة.
  int dayOf(DateTime t) => time.fiqhDayOf(t).difference(base).inDays + 1;

  static final _instantRe = RegExp(r'^D(\d{1,3}) (fajr|maghrib|noon|(?:[01]\d|2[0-3]):[0-5]\d)$');

  DateTime instant(String s) {
    final m = _instantRe.firstMatch(s)!;
    final day = int.parse(m.group(1)!);
    final tok = m.group(2)!;
    return switch (tok) {
      'fajr' => fajr(day),
      'maghrib' => maghrib(day),
      'noon' => date(day).add(const Duration(hours: 12)),
      _ => date(day).add(_parseHm(tok)!),
    };
  }

  static Duration? _parseHm(String? s) {
    if (s == null) return null;
    final p = s.split(':');
    return Duration(hours: int.parse(p[0]), minutes: int.parse(p[1]));
  }

  // ------------------------------------------------------------ الخط الزمني

  /// أول لحظة دم في السيناريو (مقطع يبدأ عند الفجر، أو حدث bloodStart).
  DateTime? firstBloodAt() {
    DateTime? first;
    for (final item in c.timeline) {
      DateTime? t;
      if (item['event'] == 'bloodStart') t = instant(item['at'] as String);
      if (item['days'] != null && item['blood'] != false) t = fajr(GoldenCase.dayRangeStart(item['days'] as String));
      if (t != null && (first == null || t.isBefore(first))) first = t;
    }
    return first;
  }

  /// آخر لحظة دم (نهاية آخر مقطع دم عند المغرب، أو حدث bloodStop).
  DateTime? lastBloodAt() {
    DateTime? last;
    for (final item in c.timeline) {
      DateTime? t;
      if (item['event'] == 'bloodStop') t = instant(item['at'] as String);
      if (item['days'] != null && item['blood'] != false) t = maghrib(GoldenCase.dayRangeEnd(item['days'] as String));
      if (t != null && (last == null || t.isAfter(last))) last = t;
    }
    return last;
  }

  /// أول انقطاع صريح (bloodStop) أو بداية أول مقطع نقاء بعد دم.
  DateTime? firstStopAt() {
    for (final item in c.timeline) {
      if (item['event'] == 'bloodStop') return instant(item['at'] as String);
    }
    var seenBlood = false;
    for (final item in c.timeline) {
      if (item['days'] == null) continue;
      if (item['blood'] != false) {
        seenBlood = true;
      } else if (seenBlood) {
        return fajr(GoldenCase.dayRangeStart(item['days'] as String));
      }
    }
    return null;
  }

  // ------------------------------------------------------------ العادة

  /// الحالة الابتدائية من `profile.declared` أو `profile.habit`، وإلا المبتدئة.
  HabitState initialHabit() {
    final p = c.profile;
    final declared = p['declared'] as Map<String, dynamic>?;
    final habit = p['habit'] as Map<String, dynamic>?;
    final typeCode = (declared?['womanType'] as String?) ?? (p['womanType'] != 'ANY' ? p['womanType'] as String : null);
    if (typeCode == null) return HabitState.initial;
    final type = WomanType.fromCode(typeCode);
    final startDay = (declared?['start'] ?? habit?['start']) as int?;
    final endDay = habit?['end'] as int?;
    final anchor = (habit?['anchor'] as String?) == 'end' ? HabitAnchor.end : HabitAnchor.start;
    final def = habit?['deficient'] as Map<String, dynamic>?;
    final mem = habit?['memory'] as Map<String, dynamic>?;
    return HabitState(
      type: type,
      anchor: anchor,
      anchorDate: anchor == HabitAnchor.end && endDay != null
          ? maghrib(endDay)
          : startDay != null
              ? fajr(startDay)
              : null,
      count: (declared?['count'] ?? habit?['count']) as int?,
      deficient: def == null ? null : DeficientBounds(min: def['min'] as int?, max: def['max'] as int?),
      memory: mem == null
          ? null
          : NasiyaMemory(
              countMin: mem['countMin'] as int?,
              countMax: mem['countMax'] as int?,
              knownDays: (mem['knownDays'] as List<dynamic>? ?? const []).cast<int>(),
            ),
      origin: HabitOrigin.declared,
    );
  }

  /// نافذة الوقت المحصور للناسية بأرقام أيام السيناريو.
  (int, int)? memoryTimeWindow() {
    final mem = (c.profile['habit'] as Map<String, dynamic>?)?['memory'] as Map<String, dynamic>?;
    final w = mem?['timeWindow'] as String?;
    if (w == null) return null;
    return (GoldenCase.dayRangeStart(w), GoldenCase.dayRangeEnd(w));
  }

  /// مدخلات الأهلية من الملف الشخصي.
  EligibilityInputs eligibilityInputs() {
    final p = c.profile;
    Tri<bool> tri(Object? v) => switch (v) {
          true => const Tri.known(true),
          false => const Tri.known(false),
          'dont_understand' => const Tri.unknown(UnknownKind.dontUnderstand),
          _ => const Tri.unknown(UnknownKind.dontRemember),
        };
    final age = p['ageHijri'] as num?;
    return EligibilityInputs(
      ageLunarYears: age == null ? const Tri.unknown(UnknownKind.dontRemember) : Tri.known(age.toDouble()),
      doubtsNine: p['ageDoubt'] == 'nine',
      doubtsSixty: p['ageDoubt'] == 'sixty',
      hysterectomy: tri(p['hysterectomy']),
      pregnant: tri(p['pregnant']),
      isQurashi: tri(p['isQurashi']),
    );
  }

  /// مدخلات تعيين العدد من الملف الشخصي والأجوبة.
  CountInputs countInputs() {
    final p = c.profile;
    final a = c.answers;
    Tri<bool>? tri(Object? v) => switch (v) {
          null => null,
          true => const Tri.known(true),
          false => const Tri.known(false),
          'dont_understand' => const Tri.unknown(UnknownKind.dontUnderstand),
          _ => const Tri.unknown(UnknownKind.dontRemember),
        };
    return CountInputs(
      kinCount: p['kinCount'] as int?,
      kinConditionsMet: tri(a['kinConditionsMet']),
      chosenCount: p['chosenCount'] as int?,
    );
  }

  /// الملف الشخصي الفقهي لآلة الأسئلة من `profile` و`answers`.
  FiqhProfile questionProfile(HabitState habit) {
    final p = c.profile;
    final a = c.answers;
    Tri<bool> tri(Object? v) => switch (v) {
          true => const Tri.known(true),
          false => const Tri.known(false),
          'dont_understand' => const Tri.unknown(UnknownKind.dontUnderstand),
          _ => const Tri.unknown(UnknownKind.dontRemember),
        };
    final age = p['ageHijri'] as num?;
    final doubt = p['ageDoubt'] as String?;
    final lastEnd = p['lastBloodEnd'] as int?;
    final tw = memoryTimeWindow();
    final mem = (p['habit'] as Map<String, dynamic>?)?['memory'] as Map<String, dynamic>?;
    return FiqhProfile(
      habit: habit,
      // السن التقريبي على الحافة يُشتق منه الشك في التسع أو الستين.
      approxAgeYears: doubt == 'nine'
          ? const Tri.known(9)
          : doubt == 'sixty'
              ? const Tri.known(60)
              : age == null
                  ? const Tri.unknown(UnknownKind.dontRemember)
                  : Tri.known(age.toDouble()),
      hysterectomy: tri(p['hysterectomy']),
      pregnant: tri(p['pregnant']),
      isQurashi: tri(p['isQurashi']),
      lastBloodEnd: lastEnd == null ? const Tri.unknown(UnknownKind.dontRemember) : Tri.known(maghrib(lastEnd)),
      kinCount: p['kinCount'] == null ? const Tri.unknown(UnknownKind.dontRemember) : Tri.known(p['kinCount'] as int),
      kinConditionsMet: a.containsKey('kinConditionsMet') ? tri(a['kinConditionsMet']) : const Tri.unknown(UnknownKind.dontRemember),
      chosenCount: p['chosenCount'] == null ? const Tri.unknown(UnknownKind.dontRemember) : Tri.known(p['chosenCount'] as int),
      knownTimeDays: [for (final d in (mem?['knownDays'] as List<dynamic>? ?? const [])) fajr(d as int)],
      timeWindow: tw == null ? null : (fajr(tw.$1), fajr(tw.$2 + 1)),
    );
  }

  /// ما يُعدّ مسوًّى في حالة ذهبية: الملف يصف مستخدمة أكملت التهيئة، فلا يُسأل
  /// عن الميلاد ولا عن آخر انتهاء ولا عن الأقارب إلا إذا ذُكر المفتاح بقيمة `null`
  /// (= لم تُجب بعد).
  Set<String> questionSettled() {
    final p = c.profile;
    final a = c.answers;
    return {
      if (!p.containsKey('ageHijri')) 'birthDate',
      if (!p.containsKey('lastBloodEnd')) 'lastBloodEnd',
      if (p.containsKey('kinCount')) 'kinCount',
      if (a.containsKey('kinConditionsMet')) 'kinConditions',
      if (p['chosenCount'] != null) 'chosenCount',
    };
  }

  /// حيضات `profile.history` بترتيبها.
  List<JudgedCycle> historyCycles() {
    final h = (c.profile['history'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return [
      for (final e in h)
        JudgedCycle(
          start: fajr(e['start'] as int),
          end: e['end'] != null
              ? maghrib(e['end'] as int)
              : fajr(e['start'] as int).add(Duration(minutes: ((e['bloodDays'] as num) * 1440).round())),
          bloodDays: (e['bloodDays'] as num).toDouble(),
        ),
    ];
  }
}
