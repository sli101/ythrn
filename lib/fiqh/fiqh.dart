/// محرك الأحكام: Dart خالص بلا Flutter (`docs/SPEC.md` §٩).
///
/// الفقه بيانات في `assets/fiqh/rules.json`، وهذا الكود محرك عام يطبّقها
/// ويُخرج كل حكم بأثره (معرّفات القواعد).
library;

export 'calendar/blood_days.dart';
export 'codec.dart';
export 'engine/duties.dart';
export 'engine/eligibility.dart';
export 'engine/hayd_engine.dart';
export 'engine/istihadha.dart';
export 'engine/nifas_engine.dart';
export 'engine/overflow_resolver.dart';
export 'engine/segments.dart';
export 'habit/habit_derivation.dart';
export 'habit/habit_machine.dart';
export 'model/day_state.dart';
export 'model/events.dart';
export 'model/habit_state.dart';
export 'model/judged_cycle.dart';
export 'model/profile.dart';
export 'model/rule_ref.dart';
export 'model/tri.dart';
export 'model/woman_type.dart';
export 'questions/catalog.dart';
export 'questions/question.dart';
export 'questions/question_machine.dart';
export 'questions/session.dart';
export 'questions/what_if.dart';
export 'time/day_clock.dart';
export 'time/fiqh_time.dart';
export 'time/hijri.dart';
