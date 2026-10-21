import 'judged_cycle.dart';
import 'woman_type.dart';

/// كيف ثبتت الحالة: تصريح المستخدمة عند أول استخدام، أو اشتقاق من التاريخ.
enum HabitOrigin { declared, derived }

/// الحد الأدنى أو الأعلى للعادة الناقصة (H4-06)؛ يثبت بالتكرار الكثير لا بالآلة.
class DeficientBounds {
  const DeficientBounds({this.min, this.max});
  final int? min;
  final int? max;

  /// قصّ ناتج الضوابط إلى [min, max] (ج م٥٨١).
  int clamp(int count) {
    var c = count;
    if (min != null && c < min!) c = min!;
    if (max != null && c > max!) c = max!;
    return c;
  }
}

/// ذاكرة الناسية الجزئية (H7-05).
class NasiyaMemory {
  const NasiyaMemory({this.countMin, this.countMax, this.knownDays = const []});
  final int? countMin;
  final int? countMax;
  final List<int> knownDays;
}

/// حالة العادة: آلة حالات فوق تاريخ الحيضات المحكوم بها (`docs/SPEC.md` §٤).
///
/// لا تُقارَن آخر حيضتان فحسب؛ العادة تثبت بمرتين، ولا تزول بحيضة واحدة
/// مخالفة (ج م٥٥٠)، وتتبدل بمرتين متماثلتين مخالفتين (ج م٥٤٩)، وتزول بمرتين
/// مخالفتين مختلفتين (ج م٥٥١).
class HabitState {
  const HabitState({
    required this.type,
    this.anchor = HabitAnchor.start,
    this.anchorDate,
    this.count,
    this.deficient,
    this.memory,
    this.origin = HabitOrigin.derived,
    this.history = const [],
  });

  /// الحالة الابتدائية لمن ترى الدم لأول مرة أو لم تصرّح بشيء.
  static const initial = HabitState(type: WomanType.mub);

  final WomanType type;

  /// محدد الوقت: بأولها أو بآخرها (H4-09).
  final HabitAnchor anchor;

  /// تاريخ آخر وقتٍ وافق العادة (بداية الحيضة أو نهايتها بحسب [anchor]).
  /// منه يُسقَط الموعد القادم: `anchorDate + 30` (H0-04).
  final DateTime? anchorDate;

  /// عدد أيام العادة (لذات العدد).
  final int? count;

  final DeficientBounds? deficient;
  final NasiyaMemory? memory;
  final HabitOrigin origin;

  /// كل الحيضات المحكوم بها بترتيب الزمن.
  final List<JudgedCycle> history;

  /// الموعد المتوقع لبدء العادة القادمة (لذات الوقت).
  DateTime? get expectedNextStart =>
      type.hasTime && anchorDate != null ? anchorDate!.add(const Duration(days: 30)) : null;

  HabitState copyWith({
    WomanType? type,
    HabitAnchor? anchor,
    DateTime? anchorDate,
    bool clearAnchorDate = false,
    int? count,
    bool clearCount = false,
    DeficientBounds? deficient,
    NasiyaMemory? memory,
    HabitOrigin? origin,
    List<JudgedCycle>? history,
  }) =>
      HabitState(
        type: type ?? this.type,
        anchor: anchor ?? this.anchor,
        anchorDate: clearAnchorDate ? null : (anchorDate ?? this.anchorDate),
        count: clearCount ? null : (count ?? this.count),
        deficient: deficient ?? this.deficient,
        memory: memory ?? this.memory,
        origin: origin ?? this.origin,
        history: history ?? this.history,
      );

  @override
  String toString() =>
      'HabitState(${type.code}, anchor=${anchor.name}, anchorDate=$anchorDate, count=$count, origin=${origin.name}, history=${history.length})';
}
