import '../model/events.dart';
import '../model/rule_ref.dart';
import '../time/fiqh_time.dart';

/// مقطع دم متصل ظاهرًا أو باطنًا (`docs/SPEC.md` §٣.٣؛ T-06).
class BloodSegment {
  BloodSegment({required this.start, this.end, this.props, this.spots = false, this.negligibleGaps = const []});

  final DateTime start;

  /// لحظة الانقطاع الظاهر؛ `null` إن كان الدم جاريًا.
  final DateTime? end;

  /// صفات الدم عند أول المقطع (قد تتغير داخله عبر [propsAt]).
  final BloodProps? props;

  /// هل بدأ المقطع لطخات متقطعة (H3-05)؛ قد يتغير داخله عبر [spotsAt].
  final bool spots;

  /// الفترات اليسيرة المغتفرة داخل المقطع (H0-09).
  final List<DateTime> negligibleGaps;

  /// تغيّرات الصفات داخل المقطع.
  final List<PropsChange> propsChanges = [];

  bool get ongoing => end == null;

  bool contains(DateTime t) => !t.isBefore(start) && (end == null || t.isBefore(end!));

  /// صفات الدم في لحظة داخل المقطع.
  BloodProps? propsAt(DateTime t) {
    BloodProps? p = props;
    for (final c in propsChanges) {
      if (!c.at.isAfter(t)) p = c.props;
    }
    return p;
  }

  /// هل الدم لطخات في لحظة داخل المقطع.
  bool spotsAt(DateTime t) {
    var sp = spots;
    for (final c in propsChanges) {
      if (!c.at.isAfter(t)) sp = c.spots;
    }
    return sp;
  }

  /// أيام الدم كسريًّا (إلى [until] إن كان جاريًا).
  double bloodDays(DateTime until) => FiqhTime.daysBetween(start, end ?? until);

  @override
  String toString() => 'Segment($start → ${end ?? "…"}, ${props?.name})';
}

/// بناء المقاطع من الأحداث (H0-09): انقطاع ≤ نصف ساعة لا يقطع؛ ما زاد يقطع.
class SegmentBuilder {
  const SegmentBuilder(this.time);
  final FiqhTime time;

  Traced<List<BloodSegment>> build(List<FiqhEvent> events) {
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
    final segments = <BloodSegment>[];
    final trace = <RuleRef>[const RuleRef('T-06', 'المقاطع مشتقة من الأحداث')];

    DateTime? openStart;
    DateTime? lastStop;
    BloodProps? openProps;
    var openSpots = false;
    final gaps = <DateTime>[];
    final changes = <PropsChange>[];

    void close(DateTime end) {
      final start = openStart;
      if (start == null) return;
      segments.add(BloodSegment(start: start, end: end, props: openProps, spots: openSpots, negligibleGaps: [...gaps])
        ..propsChanges.addAll(changes));
      openStart = null;
      openProps = null;
      openSpots = false;
      gaps.clear();
      changes.clear();
    }

    for (final e in sorted) {
      switch (e) {
        case BloodStart():
          if (e.isBlood.valueOrNull == false) continue;
          if (openStart != null) {
            // بدء داخل مقطع مفتوح: تغيّر صفات لا غير.
            changes.add(PropsChange(e.at, e.props, spots: e.spots));
            continue;
          }
          if (lastStop != null && segments.isNotEmpty) {
            final gap = e.at.difference(lastStop);
            final neg = time.isNegligibleGap(gap);
            if (neg.value) {
              // فترة يسيرة: يُفتح المقطع السابق من جديد.
              final prev = segments.removeLast();
              openStart = prev.start;
              openProps = prev.props;
              openSpots = prev.spots;
              gaps.addAll([...prev.negligibleGaps, lastStop]);
              changes.addAll(prev.propsChanges);
              changes.add(PropsChange(e.at, e.props, spots: e.spots));
              trace.add(const RuleRef('H0-09', 'فترة يسيرة لا تخل بالاستمرار'));
              lastStop = null;
              continue;
            }
            trace.add(const RuleRef('H0-09', 'انقطاع غير يسير يقطع المقطع'));
          }
          openStart = e.at;
          openProps = e.props;
          openSpots = e.spots;
          lastStop = null;
        case BloodStop():
          if (openStart == null) continue;
          close(e.at);
          lastStop = e.at;
        case FullStop():
          if (openStart == null) continue;
          if (time.isNegligibleGap(e.duration).value) {
            gaps.add(e.at);
            trace.add(const RuleRef('H0-09', 'فترة يسيرة لا تخل بالاستمرار'));
          } else {
            final props = openProps;
            final sp = openSpots;
            final resume = e.at.add(e.duration);
            close(e.at);
            trace.add(const RuleRef('H0-09', 'انقطاع غير يسير يقطع المقطع'));
            openStart = resume;
            openProps = props;
            openSpots = sp;
            lastStop = null;
          }
        case PropsChange():
          if (openStart != null) changes.add(e);
        default:
          break;
      }
    }
    if (openStart != null) {
      segments.add(BloodSegment(start: openStart!, props: openProps, spots: openSpots, negligibleGaps: [...gaps])..propsChanges.addAll(changes));
    }
    return Traced(segments, trace);
  }
}
