import '../engine/hayd_engine.dart';
import '../model/day_state.dart';
import '../model/profile.dart';
import '../model/rule_ref.dart';
import '../model/tri.dart';
import 'question.dart';
import 'question_machine.dart';
import 'session.dart';

/// فرق بين حكمين في مدى زمني واحد.
class WhatIfDiff {
  const WhatIfDiff(this.from, this.to, this.base, this.variant);
  final DateTime from;

  /// `null` = مفتوح.
  final DateTime? to;
  final DayState base;
  final DayState variant;
}

/// بديل واحد لمجهول واحد: الجواب المفترض وناتجه.
class WhatIfVariant {
  const WhatIfVariant({required this.label, required this.session, required this.result, required this.diffs});
  final String label;
  final QuestionSession session;
  final EngineResult result;

  /// المدد التي يختلف فيها الحكم عن الأصل (فارغة = لا أثر).
  final List<WhatIfDiff> diffs;

  bool get changesAnything => diffs.isNotEmpty;

  DayState? stateAt(DateTime t) => result.at(t)?.state;
}

/// مجهول واحد ببدائله.
class WhatIfItem {
  const WhatIfItem({required this.id, required this.text, required this.rule, required this.variants});
  final String id;
  final String text;
  final RuleRef rule;
  final List<WhatIfVariant> variants;
}

/// «ماذا لو؟» (`docs/SPEC.md` §٥.٤، §١١ ٥): `evaluate()` نفسها على نسخة من
/// المدخلات بتبديل مجهول واحد، ويُعرض الفرق. لا يُحفظ شيء.
///
/// المجاهيل: السؤال التالي من الآلة ببدائل جوابه، ثم مجاهيل الملف ذات الأثر
/// المباشر في الحكم (الحمل، القرشية، استئصال الرحم) إذا لم تُجَب.
class WhatIf {
  const WhatIf(this.machine);
  final QuestionMachine machine;

  List<WhatIfItem> items(QuestionSession s) {
    final base = machine.evaluate(s.copyWith(clearLadder: true));
    final out = <WhatIfItem>[];
    final q = machine.next(s.copyWith(clearLadder: true));
    if (q != null) {
      final variants = <WhatIfVariant>[];
      for (final (label, value) in _answers(q)) {
        final after = machine.apply(s.copyWith(clearLadder: true), q, Reply.value(value)).copyWith(clearLadder: true);
        variants.add(_variant(label, after, base, s.now));
      }
      if (variants.isNotEmpty) out.add(WhatIfItem(id: q.id, text: q.text, rule: q.rule, variants: variants));
    }
    final p = s.profile;
    void profileToggle(String id, String text, RuleRef rule, Tri<bool> current, FiqhProfile Function(bool) set) {
      if (current.isKnown || id == q?.id) return;
      out.add(WhatIfItem(id: id, text: text, rule: rule, variants: [
        for (final (label, v) in [('نعم', true), ('لا', false)]) _variant(label, s.copyWith(profile: set(v), clearLadder: true), base, s.now),
      ]));
    }

    profileToggle('pregnant', 'هل أنتِ حامل؟', const RuleRef('H1-03'), p.pregnant, (v) => p.copyWith(pregnant: Tri.known(v)));
    profileToggle('isQurashi', 'هل أنتِ قرشية؟', const RuleRef('H1-02'), p.isQurashi, (v) => p.copyWith(isQurashi: Tri.known(v)));
    profileToggle('hysterectomy', 'هل استُؤصل رحمك؟', const RuleRef('H1-05'), p.hysterectomy, (v) => p.copyWith(hysterectomy: Tri.known(v)));
    return out;
  }

  WhatIfVariant _variant(String label, QuestionSession after, EngineResult base, DateTime now) {
    final r = machine.evaluate(after);
    return WhatIfVariant(label: label, session: after, result: r, diffs: diff(base, r, now));
  }

  /// بدائل الجواب بحسب نوع السؤال؛ التاريخ لا بدائل له.
  List<(String, Object)> _answers(Question q) => switch (q.kind) {
        QuestionKind.yesNo => const [('نعم', true), ('لا', false)],
        QuestionKind.choice => [for (final o in q.options) (o.label, o.value)],
        QuestionKind.number => _numbers(q),
        QuestionKind.date => const [],
      };

  List<(String, Object)> _numbers(Question q) {
    final values = <int>{q.min ?? 0, if (q.defaultValue != null) q.defaultValue!, q.max ?? 10}.toList()..sort();
    return [for (final v in values) ('$v', v)];
  }

  /// المدد التي يختلف فيها الحكم بين ناتجين، من أول فترة إلى ما بعد الآن.
  static List<WhatIfDiff> diff(EngineResult a, EngineResult b, DateTime now) {
    final points = <DateTime>{};
    for (final r in [a, b]) {
      for (final iv in r.intervals) {
        points.add(iv.from);
        if (iv.to != null) points.add(iv.to!);
      }
    }
    final sorted = points.toList()..sort();
    final out = <WhatIfDiff>[];
    for (var i = 0; i < sorted.length; i++) {
      final from = sorted[i];
      final to = i + 1 < sorted.length ? sorted[i + 1] : null;
      final sa = a.at(from)?.state ?? DayState.tahir;
      final sb = b.at(from)?.state ?? DayState.tahir;
      if (sa == sb) continue;
      if (out.isNotEmpty && out.last.to == from && out.last.base == sa && out.last.variant == sb) {
        out[out.length - 1] = WhatIfDiff(out.last.from, to, sa, sb);
      } else {
        out.add(WhatIfDiff(from, to, sa, sb));
      }
    }
    return out;
  }
}
