import 'model/events.dart';
import 'model/habit_state.dart';
import 'model/judged_cycle.dart';
import 'model/profile.dart';
import 'model/tri.dart';
import 'model/woman_type.dart';

/// ترميز JSON للأحداث والملف الشخصي (للتخزين المحلي والتصدير). Dart خالص.
///
/// كل حدث: `{"kind": "...", "at": iso, ...}`؛ وكل `Tri`: `{"known": v}` أو
/// `{"unknown": "dontRemember" | "dontUnderstand"}`.
class FiqhCodec {
  const FiqhCodec._();

  // ------------------------------------------------------------ Tri

  static Map<String, Object?> encodeTri<T>(Tri<T> t, Object? Function(T) enc) => t.when(
        known: (v) => {'known': enc(v)},
        unknown: (k) => {'unknown': k.name},
      );

  static Tri<T> decodeTri<T>(Object? json, T Function(Object) dec) {
    if (json is! Map) return const Tri.unknown(UnknownKind.dontRemember);
    if (json.containsKey('known') && json['known'] != null) return Tri.known(dec(json['known'] as Object));
    final kind = json['unknown'] as String?;
    return Tri.unknown(kind == 'dontUnderstand' ? UnknownKind.dontUnderstand : UnknownKind.dontRemember);
  }

  static Map<String, Object?> _triBool(Tri<bool> t) => encodeTri(t, (v) => v);
  static Tri<bool> _boolTri(Object? j) => decodeTri(j, (v) => v as bool);
  static Map<String, Object?> _triDate(Tri<DateTime> t) => encodeTri(t, (v) => v.toIso8601String());
  static Tri<DateTime> _dateTri(Object? j) => decodeTri(j, (v) => DateTime.parse(v as String));
  static Map<String, Object?> _triInt(Tri<int> t) => encodeTri(t, (v) => v);
  static Tri<int> _intTri(Object? j) => decodeTri(j, (v) => (v as num).toInt());

  // ------------------------------------------------------------ الأحداث

  static Map<String, Object?> encodeEvent(FiqhEvent e) {
    final at = e.at.toIso8601String();
    return switch (e) {
      BloodStart() => {'kind': 'bloodStart', 'at': at, 'isBlood': _triBool(e.isBlood), 'props': e.props?.name, 'spots': e.spots},
      BloodStop() => {'kind': 'bloodStop', 'at': at},
      FullStop() => {'kind': 'fullStop', 'at': at, 'minutes': e.duration.inMinutes},
      PropsChange() => {'kind': 'propsChange', 'at': at, 'props': e.props?.name, 'spots': e.spots},
      KursufTest() => {'kind': 'kursufTest', 'at': at, 'result': e.result.name},
      InnerContinuity() => {'kind': 'innerContinuity', 'at': at, 'value': _triBool(e.value)},
      Expectation() => {'kind': 'expectation', 'at': at, 'expectation': e.kind.name, 'value': _triBool(e.value)},
      IsEarlyHabit() => {'kind': 'isEarlyHabit', 'at': at, 'value': _triBool(e.value)},
      Ghusl() => {'kind': 'ghusl', 'at': at},
      RamadanNote() => {'kind': 'ramadanNote', 'at': at, 'isRamadan': e.isRamadan},
      Birth() => {'kind': 'birth', 'at': at, 'twins': e.twins, 'cesarean': e.cesarean},
      Miscarriage() => {'kind': 'miscarriage', 'at': at, 'stage': e.stage?.name, 'ensouled': _triBool(e.ensouled)},
      IstihadhaTest() => {'kind': 'istihadhaTest', 'at': at, 'level': e.level.name, 'flow': e.flow?.name},
      VirginityTest() => {'kind': 'virginityTest', 'at': at, 'result': e.result.name},
      SourceNote() => {'kind': 'sourceNote', 'at': at, 'source': e.source.name},
    };
  }

  static FiqhEvent decodeEvent(Map<String, Object?> j) {
    final at = DateTime.parse(j['at'] as String);
    BloodProps? props(Object? v) => v == null ? null : BloodProps.values.byName(v as String);
    switch (j['kind'] as String) {
      case 'bloodStart':
        return BloodStart(at, isBlood: j.containsKey('isBlood') ? _boolTri(j['isBlood']) : const Tri.known(true), props: props(j['props']), spots: j['spots'] as bool? ?? false);
      case 'bloodStop':
        return BloodStop(at);
      case 'fullStop':
        return FullStop(at, Duration(minutes: (j['minutes'] as num).toInt()));
      case 'propsChange':
        return PropsChange(at, props(j['props']), spots: j['spots'] as bool? ?? false);
      case 'kursufTest':
        return KursufTest(at, KursufResult.values.byName(j['result'] as String));
      case 'innerContinuity':
        return InnerContinuity(at, _boolTri(j['value']));
      case 'expectation':
        return Expectation(at, ExpectationKind.values.byName(j['expectation'] as String), _boolTri(j['value']));
      case 'isEarlyHabit':
        return IsEarlyHabit(at, _boolTri(j['value']));
      case 'ghusl':
        return Ghusl(at);
      case 'ramadanNote':
        return RamadanNote(at, isRamadan: j['isRamadan'] as bool);
      case 'birth':
        return Birth(at, twins: j['twins'] as bool? ?? false, cesarean: j['cesarean'] as bool? ?? false);
      case 'miscarriage':
        return Miscarriage(at, stage: j['stage'] == null ? null : MiscarriageStage.values.byName(j['stage'] as String), ensouled: _boolTri(j['ensouled']));
      case 'istihadhaTest':
        return IstihadhaTest(at, IstihadhaLevel.values.byName(j['level'] as String), flow: j['flow'] == null ? null : IstihadhaFlow.values.byName(j['flow'] as String));
      case 'virginityTest':
        return VirginityTest(at, VirginityTestResult.values.byName(j['result'] as String));
      case 'sourceNote':
        return SourceNote(at, BloodSource.values.byName(j['source'] as String));
      default:
        throw FormatException('حدث غير معروف: ${j['kind']}');
    }
  }

  // ------------------------------------------------------------ العادة

  static Map<String, Object?> encodeHabit(HabitState h) => {
        'type': h.type.code,
        'anchor': h.anchor.name,
        'anchorDate': h.anchorDate?.toIso8601String(),
        'count': h.count,
        'deficient': h.deficient == null ? null : {'min': h.deficient!.min, 'max': h.deficient!.max},
        'memory': h.memory == null
            ? null
            : {'countMin': h.memory!.countMin, 'countMax': h.memory!.countMax, 'knownDays': h.memory!.knownDays},
        'origin': h.origin.name,
        'history': [
          for (final c in h.history) {'start': c.start.toIso8601String(), 'end': c.end.toIso8601String(), 'bloodDays': c.bloodDays},
        ],
      };

  static HabitState decodeHabit(Map<String, Object?> j) {
    final def = j['deficient'] as Map?;
    final mem = j['memory'] as Map?;
    return HabitState(
      type: WomanType.fromCode(j['type'] as String),
      anchor: HabitAnchor.values.byName(j['anchor'] as String? ?? 'start'),
      anchorDate: j['anchorDate'] == null ? null : DateTime.parse(j['anchorDate'] as String),
      count: (j['count'] as num?)?.toInt(),
      deficient: def == null ? null : DeficientBounds(min: (def['min'] as num?)?.toInt(), max: (def['max'] as num?)?.toInt()),
      memory: mem == null
          ? null
          : NasiyaMemory(
              countMin: (mem['countMin'] as num?)?.toInt(),
              countMax: (mem['countMax'] as num?)?.toInt(),
              knownDays: ((mem['knownDays'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
            ),
      origin: HabitOrigin.values.byName(j['origin'] as String? ?? 'derived'),
      history: [
        for (final c in (j['history'] as List?) ?? const [])
          JudgedCycle(
            start: DateTime.parse((c as Map)['start'] as String),
            end: DateTime.parse(c['end'] as String),
            bloodDays: (c['bloodDays'] as num).toDouble(),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ الملف الشخصي

  static Map<String, Object?> encodeProfile(FiqhProfile p) => {
        'habit': encodeHabit(p.habit),
        'birth': _triDate(p.birth),
        'approxAgeYears': encodeTri(p.approxAgeYears, (v) => v),
        'isQurashi': _triBool(p.isQurashi),
        'hysterectomy': _triBool(p.hysterectomy),
        'pregnant': _triBool(p.pregnant),
        'lastBloodEnd': _triDate(p.lastBloodEnd),
        'kinCount': _triInt(p.kinCount),
        'kinConditionsMet': _triBool(p.kinConditionsMet),
        'chosenCount': _triInt(p.chosenCount),
        'nasiyaHalfMonth': p.nasiyaHalfMonth,
        'knownTimeDays': [for (final d in p.knownTimeDays) d.toIso8601String()],
        'timeWindow': p.timeWindow == null ? null : [p.timeWindow!.$1.toIso8601String(), p.timeWindow!.$2.toIso8601String()],
        'ramadan': [
          for (final r in p.ramadan) [r.$1.toIso8601String(), r.$2.toIso8601String()],
        ],
      };

  static FiqhProfile decodeProfile(Map<String, Object?> j) {
    final tw = j['timeWindow'] as List?;
    return FiqhProfile(
      habit: j['habit'] == null ? HabitState.initial : decodeHabit((j['habit'] as Map).cast<String, Object?>()),
      birth: _dateTri(j['birth']),
      approxAgeYears: decodeTri(j['approxAgeYears'], (v) => (v as num).toDouble()),
      isQurashi: _boolTri(j['isQurashi']),
      hysterectomy: _boolTri(j['hysterectomy']),
      pregnant: _boolTri(j['pregnant']),
      lastBloodEnd: _dateTri(j['lastBloodEnd']),
      kinCount: _intTri(j['kinCount']),
      kinConditionsMet: _boolTri(j['kinConditionsMet']),
      chosenCount: _intTri(j['chosenCount']),
      nasiyaHalfMonth: (j['nasiyaHalfMonth'] as num?)?.toInt(),
      knownTimeDays: [for (final d in (j['knownTimeDays'] as List?) ?? const []) DateTime.parse(d as String)],
      timeWindow: tw == null ? null : (DateTime.parse(tw[0] as String), DateTime.parse(tw[1] as String)),
      ramadan: [
        for (final r in (j['ramadan'] as List?) ?? const []) (DateTime.parse((r as List)[0] as String), DateTime.parse(r[1] as String)),
      ],
    );
  }
}
