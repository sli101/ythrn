import 'tri.dart';

/// صفات الدم (H0-05): واجد لصفات الحيض (حرارة، حمرة أو سواد، دفع) أو فاقد لها.
enum BloodProps { wajid, faqid }

/// نتيجة اختبار القطنة (H6-01، I1-04).
enum KursufResult { stained, clean }

/// ما تتوقعه المستخدمة أو تعلمه (H3-06، H6-02، H7-08).
enum ExpectationKind { willLastThreeDays, willReturnBeforeTen, willExceedTen }

/// الأحداث تُسجَّل ساعة وقوعها، والحالة تُشتق منها (`docs/SPEC.md` §٣.٢، T-06).
sealed class FiqhEvent {
  const FiqhEvent(this.at);

  /// لحظة الواقعة (لا لحظة التسجيل).
  final DateTime at;
}

/// أول خروج للدم.
final class BloodStart extends FiqhEvent {
  const BloodStart(super.at, {this.isBlood = const Tri.known(true), this.props, this.spots = false});
  final Tri<bool> isBlood;
  final BloodProps? props;

  /// لطخات أو قطرات متقطعة لا دم مستمر (H3-05).
  final bool spots;
}

/// آخر انقطاع ظاهر للدم.
final class BloodStop extends FiqhEvent {
  const BloodStop(super.at);
}

/// انقطاع تام (ظاهرًا وباطنًا) لمدة محددة ثم عاد الدم (H0-09).
final class FullStop extends FiqhEvent {
  const FullStop(super.at, this.duration);
  final Duration duration;
}

/// تغيّر صفات الدم من هذه اللحظة.
final class PropsChange extends FiqhEvent {
  const PropsChange(super.at, this.props, {this.spots = false});
  final BloodProps? props;
  final bool spots;
}

/// نتيجة اختبار القطنة.
final class KursufTest extends FiqhEvent {
  const KursufTest(super.at, this.result);
  final KursufResult result;
}

/// هل تحتمل بقاء الدم في الداخل بعد انقطاعه ظاهرًا (H6-01).
final class InnerContinuity extends FiqhEvent {
  const InnerContinuity(super.at, this.value);
  final Tri<bool> value;
}

/// توقع أو علم المستخدمة.
final class Expectation extends FiqhEvent {
  const Expectation(super.at, this.kind, this.value);
  final ExpectationKind kind;
  final Tri<bool> value;
}

/// هل تعدّ هذا البدء تعجيلًا لعادتها عرفًا (H5-01).
final class IsEarlyHabit extends FiqhEvent {
  const IsEarlyHabit(super.at, this.value);
  final Tri<bool> value;
}

/// اغتسلت من الحيض في هذه اللحظة (لأحكام الوظائف لاحقًا).
final class Ghusl extends FiqhEvent {
  const Ghusl(super.at);
}

/// هل اليوم التالي للحظة من رمضان أو قضائه (H9-15).
final class RamadanNote extends FiqhEvent {
  const RamadanNote(super.at, {required this.isRamadan});
  final bool isRamadan;
}

/// مرحلة الجنين عند السقط (M-01).
enum MiscarriageStage { nutfa, alaqa, mudgha, formed }

/// ولادة (أو قيصرية N1-07)؛ خروج أول جزء من الولد.
final class Birth extends FiqhEvent {
  const Birth(super.at, {this.twins = false, this.cesarean = false});
  final bool twins;
  final bool cesarean;
}

/// سقط؛ [stage] مجهولة = «لا أعرف».
final class Miscarriage extends FiqhEvent {
  const Miscarriage(super.at, {this.stage, this.ensouled = const Tri.unknown(UnknownKind.dontRemember)});
  final MiscarriageStage? stage;
  final Tri<bool> ensouled;

  /// يصدق عليه «ولادة» فيجري النفاس (تجاوز المضغة).
  bool get countsAsBirth => stage == MiscarriageStage.formed;
}

/// قسم الاستحاضة بنتيجة اختبار القطنة (I1-04).
enum IstihadhaLevel {
  /// تلوّث القطنة ولا تغمسها.
  qalila,

  /// تغمس القطنة ولا تتجاوزها إلى الخرقة.
  mutawassita,

  /// تغمسها وتتجاوزها إلى الخرقة.
  kathira,
}

/// نمط بروز الدم في الكثيرة (I2-04).
enum IstihadhaFlow { continuous, intermittent }

/// اختبار المستحاضة حالها قبل الصلاة (I2-01).
final class IstihadhaTest extends FiqhEvent {
  const IstihadhaTest(super.at, this.level, {this.flow});
  final IstihadhaLevel level;
  final IstihadhaFlow? flow;
}

/// مصدر الدم إذا عُلم أو احتُمل أنه ليس من الرحم (H2-01، H2-02، N1-06).
enum BloodSource {
  /// مُحرز أنه من جرح أو قرح.
  wound,

  /// مُحرز أنه دم البكارة.
  virginity,

  /// مُحرز أنه من المخاض.
  labor,

  /// مردد بين الجرح والحيض والاحتمالان معقولان (ج م٥٠٧).
  doubtWoundOrHayd,

  /// مردد بين البكارة والحيض (م٢١٢).
  doubtVirginityOrHayd,
}

/// اختبار القطنة للتردد بين البكارة والحيض (H2-01).
final class VirginityTest extends FiqhEvent {
  const VirginityTest(super.at, this.result);
  final VirginityTestResult result;
}

enum VirginityTestResult {
  /// مطوّقة بالدم: بكارة.
  ringed,

  /// مستنقعة: حيض.
  soaked,
}

/// بيان مصدر دم جارٍ (يُلحق بأقرب بدء دم قبله).
final class SourceNote extends FiqhEvent {
  const SourceNote(super.at, this.source);
  final BloodSource source;
}
