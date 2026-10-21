import '../engine/hayd_engine.dart';
import '../model/day_state.dart';
import '../model/habit_state.dart';
import '../model/judged_cycle.dart';
import '../time/fiqh_time.dart';
import 'habit_machine.dart';

/// اشتقاق العادة من الحيضات المحكوم بها (`PLAN.md` §٢.١.١، `docs/UX.md` §٢.٢):
/// الحيضات المغلقة في ناتج المحرك تُغذّى إلى آلة الحالات بالترتيب، فلا يُسأل
/// عن نوع العادة ما دام التقويم يحمل الأشهر السابقة (`docs/fiqh/assumptions.md` ٥٩).
class HabitDerivation {
  const HabitDerivation({this.machine = const HabitMachine()});
  final HabitMachine machine;

  /// الحيضات المغلقة في [r]: الفترات المحكوم بالحيض المتصلة (أو التي بينها
  /// نقاء متخلل محكوم بالحيض) تُجمع حيضة واحدة. الحيضة التي تنتهي بعد [before]
  /// (الجارية) لا تدخل.
  List<JudgedCycle> closedCycles(EngineResult r, {DateTime? before}) {
    final sorted = r.intervals.where((iv) => iv.state == DayState.hayd || iv.state == DayState.jam3).toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    final out = <JudgedCycle>[];
    DateTime? start;
    DateTime? end;
    var blood = 0.0;
    void flush() {
      if (start != null && end != null && (before == null || !end!.isAfter(before))) {
        out.add(JudgedCycle(start: start!, end: end!, bloodDays: blood));
      }
      start = null;
      end = null;
      blood = 0;
    }

    for (final iv in sorted) {
      if (iv.to == null) {
        // جارية: تُغلق ما قبلها وتُهمل.
        flush();
        start = null;
        break;
      }
      if (start != null && iv.from.difference(end!) > const Duration(days: 10)) flush();
      start ??= iv.from;
      end = iv.to;
      if (iv.state == DayState.hayd) blood += FiqhTime.daysBetween(iv.from, iv.to!);
    }
    flush();
    return out;
  }

  /// العادة بعد تغذية الحيضات المغلقة التي لم تدخل تاريخها بعد.
  HabitState derive(HabitState base, EngineResult r, {DateTime? before}) {
    var s = base;
    final known = {for (final c in base.history) c.start};
    for (final c in closedCycles(r, before: before)) {
      if (known.contains(c.start)) continue;
      s = machine.update(s, c).value;
    }
    return s;
  }
}
