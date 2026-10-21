import '../engine/hayd_engine.dart';
import '../model/events.dart';
import '../model/day_state.dart';
import '../time/day_clock.dart';
import '../time/hijri.dart';
import '../time/fiqh_time.dart';

/// جزء اليوم الفقهي الذي وقع فيه البدء أو الانقطاع (T-01: النهار من الفجر إلى
/// المغرب، والليلة التي تليه تحمل رقمه).
enum DayPart { day, night }

/// يوم دم على التقويم (`docs/UX.md` §٢.٢): اليوم الفقهي بمنتصف ليله التقويمي،
/// وصفاته، وتفاصيل البدء والانقطاع الاختيارية (تؤثر فقط في أول يوم من المدى
/// وآخره).
class BloodDay {
  const BloodDay(this.day, {this.props, this.spots = false, this.startPart, this.startAt, this.stopPart, this.stopAt});

  /// منتصف ليل اليوم التقويمي الذي يحمل رقم اليوم الفقهي.
  final DateTime day;

  final BloodProps? props;
  final bool spots;

  /// بدأ الدم نهارًا أو ليلًا (إن كان أول يوم)؛ `null` = لا أذكر.
  final DayPart? startPart;

  /// الساعة الدقيقة للبدء إن عُلمت.
  final DateTime? startAt;

  /// انقطع نهارًا أو ليلًا (إن كان آخر يوم)؛ `null` = لا أذكر.
  final DayPart? stopPart;

  /// الساعة الدقيقة للانقطاع إن عُلمت.
  final DateTime? stopAt;

  static DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  BloodDay copyWith({
    BloodProps? props,
    bool clearProps = false,
    bool? spots,
    DayPart? startPart,
    bool clearStartPart = false,
    DateTime? startAt,
    bool clearStartAt = false,
    DayPart? stopPart,
    bool clearStopPart = false,
    DateTime? stopAt,
    bool clearStopAt = false,
  }) =>
      BloodDay(
        day,
        props: clearProps ? null : (props ?? this.props),
        spots: spots ?? this.spots,
        startPart: clearStartPart ? null : (startPart ?? this.startPart),
        startAt: clearStartAt ? null : (startAt ?? this.startAt),
        stopPart: clearStopPart ? null : (stopPart ?? this.stopPart),
        stopAt: clearStopAt ? null : (stopAt ?? this.stopAt),
      );

  Map<String, Object?> toJson() => {
        'day': day.toIso8601String(),
        'props': props?.name,
        'spots': spots,
        'startPart': startPart?.name,
        'startAt': startAt?.toIso8601String(),
        'stopPart': stopPart?.name,
        'stopAt': stopAt?.toIso8601String(),
      };

  static BloodDay fromJson(Map<String, Object?> j) => BloodDay(
        normalize(DateTime.parse(j['day'] as String)),
        props: j['props'] == null ? null : BloodProps.values.byName(j['props'] as String),
        spots: j['spots'] as bool? ?? false,
        startPart: j['startPart'] == null ? null : DayPart.values.byName(j['startPart'] as String),
        startAt: j['startAt'] == null ? null : DateTime.parse(j['startAt'] as String),
        stopPart: j['stopPart'] == null ? null : DayPart.values.byName(j['stopPart'] as String),
        stopAt: j['stopAt'] == null ? null : DateTime.parse(j['stopAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is BloodDay &&
      other.day == day &&
      other.props == props &&
      other.spots == spots &&
      other.startPart == startPart &&
      other.startAt == startAt &&
      other.stopPart == stopPart &&
      other.stopAt == stopAt;

  @override
  int get hashCode => Object.hash(day, props, spots, startPart, startAt, stopPart, stopAt);

  @override
  String toString() => 'BloodDay(${day.year}-${day.month}-${day.day}${props == null ? '' : ' ${props!.name}'}${spots ? ' spots' : ''})';
}

/// ما يحتاج إلى ساعة دقيقة لأن الحكم يختلف بها (`docs/UX.md` §٢.٢).
class PrecisionNeed {
  const PrecisionNeed(this.day, {required this.isStart});
  final DateTime day;

  /// بدء الدم في هذا اليوم (وإلا انقطاعه).
  final bool isStart;

  @override
  String toString() => 'PrecisionNeed(${day.year}-${day.month}-${day.day} ${isStart ? 'start' : 'stop'})';
}

/// تحويل أيام التقويم إلى أحداث المحرك (`docs/fiqh/assumptions.md` ٥٨).
///
/// المدى المتصل من الأيام → `BloodStart` في أوله و`BloodStop` في آخره
/// و`PropsChange` حيث تتغير الصفات. الافتراضات حين لا تُعطى الساعة:
/// البدء نهارًا أو مجهولًا = فجر اليوم، ليلًا = مغربه؛ الانقطاع نهارًا = زواله،
/// ليلًا أو مجهولًا = فجر اليوم التالي. المدى المنتهي باليوم الحالي بلا
/// انقطاع مصرَّح به = دم جارٍ.
class BloodCalendar {
  const BloodCalendar._();

  /// الأيام متصلةً: كل مدى قائمة مرتبة.
  static List<List<BloodDay>> runs(Iterable<BloodDay> days) {
    final sorted = days.toList()..sort((a, b) => a.day.compareTo(b.day));
    final out = <List<BloodDay>>[];
    for (final d in sorted) {
      if (out.isNotEmpty && HijriDate.nextDay(out.last.last.day) == d.day) {
        out.last.add(d);
      } else {
        out.add([d]);
      }
    }
    return out;
  }

  static DateTime startMoment(BloodDay d, DayClock clock) =>
      d.startAt ?? (d.startPart == DayPart.night ? clock.maghrib(d.day) : clock.fajr(d.day));

  static DateTime stopMoment(BloodDay d, DayClock clock) =>
      d.stopAt ?? (d.stopPart == DayPart.day ? clock.dhuhr(d.day) : clock.fajr(HijriDate.nextDay(d.day)));

  /// هل المدى المنتهي بـ [last] جارٍ إلى الآن؟
  static bool isOngoing(BloodDay last, DateTime today) => last.day == BloodDay.normalize(today) && last.stopAt == null && last.stopPart == null;

  /// [anchors]: لحظات الولادة أو السقط؛ المدى الذي يبدأ في يوم إحداها بلا ساعة
  /// صريحة يبدأ عندها (دم ما بعد الولادة لا ما قبلها).
  static List<FiqhEvent> toEvents(Iterable<BloodDay> days, DayClock clock, {required DateTime today, List<DateTime> anchors = const []}) {
    final out = <FiqhEvent>[];
    for (final run in runs(days)) {
      final first = run.first;
      var start = startMoment(first, clock);
      if (first.startAt == null) {
        final nextFajr = clock.fajr(HijriDate.nextDay(first.day));
        for (final a in anchors) {
          if (a.isAfter(start) && a.isBefore(nextFajr)) start = a;
        }
      }
      out.add(BloodStart(start, props: first.props, spots: first.spots));
      var props = first.props;
      var spots = first.spots;
      for (final d in run.skip(1)) {
        final p = d.props ?? props;
        if (p != props || d.spots != spots) {
          out.add(PropsChange(clock.fajr(d.day), p, spots: d.spots));
          props = p;
          spots = d.spots;
        }
      }
      final last = run.last;
      if (!isOngoing(last, today)) out.add(BloodStop(stopMoment(last, clock)));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// الأيام التي يختلف فيها حكم يوم ما باختلاف ساعة البدء أو الانقطاع داخل
  /// اليوم، فتُطلب الساعة لها وحدها (انزياح حدود الفترة بالساعات لا يُعدّ اختلافًا). [evaluate] يقيّم قائمة أحداث التقويم (مع بقية
  /// أحداث الجلسة) ويعيد الناتج.
  static List<PrecisionNeed> precisionNeeds(
    Iterable<BloodDay> days,
    DayClock clock, {
    required DateTime today,
    required DateTime now,
    required EngineResult Function(List<FiqhEvent> calendarEvents) evaluate,
  }) {
    final list = days.toList();
    if (list.isEmpty) return const [];
    final first0 = list.map((d) => d.day).reduce((a, b) => a.isBefore(b) ? a : b);
    final base = dayStates(evaluate(toEvents(list, clock, today: today)), clock, from: first0, to: today);
    final out = <PrecisionNeed>[];
    bool differs(List<BloodDay> variant) => !_sameStates(base, dayStates(evaluate(toEvents(variant, clock, today: today)), clock, from: first0, to: today));
    List<BloodDay> replace(BloodDay d) => [for (final x in list) x.day == d.day ? d : x];

    for (final run in runs(list)) {
      final first = run.first;
      if (first.startAt == null) {
        // مجهول = نهارًا (لوّنت اليوم لأنها رأت الدم فيه)؛ الليل فقط إذا صرّحت به.
        final candidates = first.startPart == DayPart.night
            ? [clock.maghrib(first.day), clock.midnight(first.day), clock.fajr(HijriDate.nextDay(first.day)).subtract(const Duration(minutes: 1))]
            : [clock.fajr(first.day), clock.dhuhr(first.day), clock.maghrib(first.day).subtract(const Duration(minutes: 1))];
        if (candidates.any((t) => differs(replace(first.copyWith(startAt: t))))) out.add(PrecisionNeed(first.day, isStart: true));
      }
      final last = run.last;
      if (last.stopAt == null && !isOngoing(last, today)) {
        // لوّنت اليوم لأنها رأت الدم فيه: الانقطاع من الزوال فصاعدًا، أو ليلًا إن صرّحت.
        final candidates = last.stopPart == DayPart.night
            ? [clock.maghrib(last.day), clock.midnight(last.day), clock.fajr(HijriDate.nextDay(last.day))]
            : [clock.dhuhr(last.day), clock.maghrib(last.day), clock.fajr(HijriDate.nextDay(last.day))];
        if (candidates.any((t) => differs(replace(last.copyWith(stopAt: t))))) out.add(PrecisionNeed(last.day, isStart: false));
      }
    }
    return out;
  }

  /// حكم كل يوم فقهي في [from, to]: حكم الدم إن وُجد في نهاره، وإلا الحالة
  /// الأطول (كما في الاختبارات الذهبية)، وإلا حكم الدم في ليلته؛ وإلا لا حالة.
  static Map<DateTime, DayState?> dayStates(EngineResult r, DayClock clock, {required DateTime from, required DateTime to}) {
    final out = <DateTime, DayState?>{};
    for (var d = BloodDay.normalize(from); !d.isAfter(to); d = HijriDate.nextDay(d)) {
      final a = clock.fajr(d);
      final b = clock.maghrib(d);
      DayState? best;
      var bestLen = 0;
      for (final iv in r.intervals) {
        final x = iv.from.isAfter(a) ? iv.from : a;
        final y = (iv.to == null || iv.to!.isAfter(b)) ? b : iv.to!;
        if (!y.isAfter(x)) continue;
        if (iv.state.isBloodRuling) {
          best = iv.state;
          bestLen = 1 << 30;
          break;
        }
        final len = y.difference(x).inMinutes;
        if (len > bestLen) {
          bestLen = len;
          best = iv.state;
        }
      }
      if (best == null) {
        // لا فترة في النهار (دم بدأ ليلًا): حكم الليلة التي تحمل رقم اليوم.
        final n0 = clock.maghrib(d);
        final n1 = clock.fajr(HijriDate.nextDay(d));
        for (final iv in r.intervals) {
          final x = iv.from.isAfter(n0) ? iv.from : n0;
          final y = (iv.to == null || iv.to!.isAfter(n1)) ? n1 : iv.to!;
          if (y.isAfter(x) && iv.state.isBloodRuling) {
            best = iv.state;
            break;
          }
        }
      }
      out[d] = best;
    }
    return out;
  }

  static bool _sameStates(Map<DateTime, DayState?> a, Map<DateTime, DayState?> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  /// أيام الدم من أحداث قديمة (ترحيل السجل الحي): كل مقطع دم → أيامه الفقهية.
  static List<BloodDay> fromEvents(Iterable<FiqhEvent> events, FiqhTime time, {required DateTime now}) {
    final sorted = events.where((e) => e is BloodStart || e is BloodStop).toList()..sort((a, b) => a.at.compareTo(b.at));
    final out = <BloodDay>[];
    DateTime? open;
    BloodProps? props;
    var spots = false;
    void close(DateTime end, {bool explicit = true}) {
      if (open == null) return;
      var d = time.fiqhDayOf(open!);
      final lastDay = time.fiqhDayOf(end.subtract(const Duration(minutes: 1)));
      while (!d.isAfter(lastDay)) {
        final isFirst = d == time.fiqhDayOf(open!);
        final isLast = d == lastDay;
        out.add(BloodDay(d, props: isFirst ? props : null, spots: isFirst && spots, startAt: isFirst ? open : null, stopAt: isLast && explicit ? end : null));
        d = HijriDate.nextDay(d);
      }
      open = null;
    }

    for (final e in sorted) {
      if (e is BloodStart) {
        if (open != null) close(e.at);
        open = e.at;
        props = e.props;
        spots = e.spots;
      } else if (e is BloodStop) {
        close(e.at);
      }
    }
    if (open != null) close(now.add(const Duration(minutes: 1)), explicit: false);
    return out;
  }
}
