import '../fiqh.dart';

import 'golden_case.dart';
import 'scenario.dart';

/// يحوّل الخط الزمني والأجوبة في حالة ذهبية إلى أحداث المحرك.
///
/// الاصطلاحات (`README.md`): مقطع دم بالأيام يبدأ عند فجر أول يوم وينتهي قبيل
/// فجر اليوم التالي لآخر يوم (الليلة تتبع يومها). مقطعان متتاليان من الدم
/// بلا نقاء بينهما مقطع واحد مع تغيّر الصفات. مقطع النقاء يحمل نتيجة القطنة
/// (الافتراضي: نظيفة = نقاء تام). الأجوبة تُلحق بأول لحظة تلزم فيها.
List<FiqhEvent> eventsFromScenario(GoldenCase c, Scenario sc) {
  final events = <FiqhEvent>[];
  final explicitStops = <DateTime>[];
  final explicitStarts = <DateTime>[];
  for (final item in c.timeline) {
    if (item['event'] == 'bloodStop') explicitStops.add(sc.instant(item['at'] as String));
    if (item['event'] == 'bloodStart') explicitStarts.add(sc.instant(item['at'] as String));
  }

  BloodProps? propsOf(Object? p) => switch (p) { 'wajid' => BloodProps.wajid, 'faqid' => BloodProps.faqid, _ => null };

  var inBlood = false;
  int? lastBloodDay;
  DateTime? firstStart;
  DateTime? firstStop;
  DateTime? pendingStop;

  for (final item in c.timeline) {
    final days = item['days'] as String?;
    if (days != null) {
      final from = GoldenCase.dayRangeStart(days);
      final to = GoldenCase.dayRangeEnd(days);
      final blood = item['blood'];
      if (blood != false) {
        final startAt = sc.fajr(from);
        final contiguous = inBlood && lastBloodDay == from - 1;
        final hasExplicitStart = explicitStarts.any((t) => !t.isAfter(startAt) && t.isAfter(sc.fajr(from - 1)));
        final spots = blood == 'spots';
        if (contiguous) {
          events.add(PropsChange(startAt, propsOf(item['props']), spots: spots));
        } else if (!hasExplicitStart) {
          events.add(BloodStart(startAt, props: propsOf(item['props']), spots: spots));
          firstStart ??= startAt;
        }
        if (item['nights'] == false) {
          // انقطاع تام في كل ليلة متوسطة من المقطع.
          for (var d = from; d < to; d++) {
            events.add(FullStop(sc.maghrib(d), sc.fajr(d + 1).difference(sc.maghrib(d))));
          }
        }
        final endAt = sc.fajr(to + 1).subtract(const Duration(minutes: 1));
        final hasExplicitStop = explicitStops.any((t) => !t.isBefore(sc.fajr(to)) && !t.isAfter(sc.fajr(to + 1)));
        if (!hasExplicitStop) {
          // يُغلق لاحقًا إذا جاء نقاء؛ وإلا يبقى جاريًا حتى آخر يوم.
          lastBloodDay = to;
          inBlood = true;
          pendingStop = endAt;
        } else {
          inBlood = false;
          lastBloodDay = to;
          pendingStop = null;
        }
      } else {
        if (inBlood && pendingStop != null) {
          events.add(BloodStop(pendingStop));
          firstStop ??= pendingStop;
          pendingStop = null;
        }
        inBlood = false;
        final kursuf = item['kursuf'] as String? ?? 'clean';
        final at = sc.fajr(from).add(const Duration(hours: 1));
        if (kursuf != 'none') {
          events.add(KursufTest(at, kursuf == 'stained' ? KursufResult.stained : KursufResult.clean));
        }
      }
      continue;
    }

    final at = sc.instant(item['at'] as String);
    switch (item['event'] as String) {
      case 'bloodStart':
        events.add(BloodStart(at, props: propsOf(item['props'])));
        firstStart ??= at;
        inBlood = true;
        pendingStop = null;
      case 'bloodStop':
        events.add(BloodStop(at));
        firstStop ??= at;
        inBlood = false;
        pendingStop = null;
      case 'fullStop':
        events.add(FullStop(at, Duration(minutes: item['minutes'] as int)));
      case 'kursufClean':
        events.add(KursufTest(at, KursufResult.clean));
      case 'kursufStained':
        events.add(KursufTest(at, KursufResult.stained));
      case 'birth':
        events.add(Birth(at, twins: item['twins'] as bool? ?? false));
      case 'miscarriage':
        events.add(Miscarriage(
          at,
          stage: switch (item['stage']) {
            'nutfa' => MiscarriageStage.nutfa,
            'alaqa' => MiscarriageStage.alaqa,
            'mudgha' => MiscarriageStage.mudgha,
            'formed' => MiscarriageStage.formed,
            _ => null,
          },
          ensouled: switch (item['ensouled']) {
            true => const Tri.known(true),
            false => const Tri.known(false),
            _ => const Tri.unknown(UnknownKind.dontRemember),
          },
        ));
      case 'ghusl':
        events.add(Ghusl(at));
      case 'sourceNote':
        events.add(SourceNote(at, BloodSource.values.byName(item['source'] as String)));
      case 'virginityTest':
        events.add(VirginityTest(at, item['result'] == 'ringed' ? VirginityTestResult.ringed : VirginityTestResult.soaked));
      case 'istihadhaTest':
        events.add(IstihadhaTest(
          at,
          switch (item['level']) {
            'mutawassita' => IstihadhaLevel.mutawassita,
            'kathira' => IstihadhaLevel.kathira,
            _ => IstihadhaLevel.qalila,
          },
          flow: item['flow'] == 'intermittent' ? IstihadhaFlow.intermittent : null,
        ));
      default:
        break;
    }
  }
  // مقطع دم في آخر الخط الزمني بلا نقاء بعده يُترك جاريًا (الدم مستمر إلى الآن).
  pendingStop = null;

  // الأجوبة.
  Tri<bool> tri(Object? v) => switch (v) {
        true => const Tri.known(true),
        false => const Tri.known(false),
        'dont_understand' => const Tri.unknown(UnknownKind.dontUnderstand),
        _ => const Tri.unknown(UnknownKind.dontRemember),
      };
  final a = c.answers;
  final startRef = firstStart ?? sc.fajr(1);
  final stopRef = firstStop ?? startRef;
  if (a.containsKey('ramadanTomorrow')) events.add(RamadanNote(stopRef, isRamadan: a['ramadanTomorrow'] == true));
  if (a.containsKey('willLastThreeDays')) events.add(Expectation(startRef, ExpectationKind.willLastThreeDays, tri(a['willLastThreeDays'])));
  if (a.containsKey('willReturnBeforeTen')) events.add(Expectation(stopRef, ExpectationKind.willReturnBeforeTen, tri(a['willReturnBeforeTen'])));
  if (a.containsKey('willExceedTen')) events.add(Expectation(stopRef, ExpectationKind.willExceedTen, tri(a['willExceedTen'])));
  if (a.containsKey('innerContinuity')) events.add(InnerContinuity(stopRef, tri(a['innerContinuity'])));
  if (a.containsKey('isEarlyHabit')) events.add(IsEarlyHabit(startRef, tri(a['isEarlyHabit'])));
  if (a.containsKey('isBlood')) {
    final idx = events.indexWhere((e) => e is BloodStart);
    if (idx >= 0) {
      final s = events[idx] as BloodStart;
      events[idx] = BloodStart(s.at, isBlood: tri(a['isBlood']), props: s.props);
    }
  }
  return events;
}

