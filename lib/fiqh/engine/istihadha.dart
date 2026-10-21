import '../model/day_state.dart';
import '../model/events.dart';
import '../model/rule_ref.dart';
import 'hayd_engine.dart';

/// الاستحاضة: تعيين القسم بالاختبار، ووظائف كل قسم (الوحدة I).
///
/// القسم يُستخرج من آخر اختبار قطنة سجّلته المستحاضة في الفترة الجارية من
/// الاستحاضة (I1-04)؛ وما لم تختبر فالقسم غير معيَّن وعليها الاختبار قبل الصلاة
/// (I2-01، احتياط وجوبي).
class IstihadhaResolver {
  const IstihadhaResolver();

  /// يقسّم فترات الاستحاضة غير المعيَّنة بحسب الاختبارات ويعيّن أقسامها.
  List<StateInterval> refine(List<StateInterval> intervals, List<FiqhEvent> events) {
    final tests = events.whereType<IstihadhaTest>().toList()..sort((a, b) => a.at.compareTo(b.at));
    final sorted = [...intervals]..sort((a, b) => a.from.compareTo(b.from));
    final out = <StateInterval>[];
    DateTime? runStart; // بداية الفترة المتصلة الجارية من الاستحاضة
    DateTime? prevEnd;
    var prevWasIst = false;

    for (final iv in sorted) {
      if (!iv.state.isIstihadha) {
        out.add(iv);
        prevEnd = iv.to;
        prevWasIst = false;
        continue;
      }
      // فترة استحاضة جديدة إذا لم تكن متصلة بما قبلها من الاستحاضة.
      if (!prevWasIst || runStart == null || prevEnd == null || iv.from.isAfter(prevEnd)) runStart = iv.from;
      prevEnd = iv.to;
      prevWasIst = true;
      if (iv.state != DayState.istU) {
        out.add(iv);
        continue;
      }
      final rs = runStart;
      final inside = tests.where((t) => t.at.isAfter(iv.from) && (iv.to == null || t.at.isBefore(iv.to!))).toList();
      var cursor = iv.from;
      for (final t in [...inside, null]) {
        final to = t?.at ?? iv.to;
        final latest = _latestTest(tests, cursor, rs);
        out.add(_withLevel(iv, cursor, to, latest));
        if (t != null) cursor = t.at;
      }
    }
    return out;
  }

  IstihadhaTest? _latestTest(List<IstihadhaTest> tests, DateTime at, DateTime runStart) {
    IstihadhaTest? found;
    for (final t in tests) {
      if (!t.at.isAfter(at) && !t.at.isBefore(runStart)) found = t;
    }
    return found;
  }

  StateInterval _withLevel(StateInterval iv, DateTime from, DateTime? to, IstihadhaTest? test) {
    if (test == null) {
      return StateInterval(from, to, DayState.istU,
          [...iv.trace, const RuleRef('I2-01', 'تختبر حالها قبل الصلاة لتعرف قسمها')],
          classification: iv.classification, pendingInput: 'istihadhaTest');
    }
    final state = switch (test.level) {
      IstihadhaLevel.qalila => DayState.istQ,
      IstihadhaLevel.mutawassita => DayState.istM,
      IstihadhaLevel.kathira => DayState.istK,
    };
    return StateInterval(from, to, state, [...iv.trace, RuleRef('I1-04', 'القسم بالاختبار: ${test.level.name}')],
        classification: iv.classification);
  }
}

/// وظيفة من وظائف المستحاضة أو حكم من أحكامها، بأثرها.
class Duty {
  const Duty(this.text, this.rule, {this.classification = 'fatwa', this.kind = DutyKind.obligation});
  final String text;
  final RuleRef rule;
  final String classification;
  final DutyKind kind;

  @override
  String toString() => '[$kind] $text ($rule)';
}

enum DutyKind { obligation, prohibition, permission, alert }

/// وظائف الأقسام الثلاثة وأحكامها (I2-02 إلى I2-13) بيانات مرتبة للعرض.
class IstihadhaDuties {
  const IstihadhaDuties();

  List<Duty> forLevel(IstihadhaLevel? level, {IstihadhaFlow flow = IstihadhaFlow.continuous}) {
    final d = <Duty>[];
    if (level == null) {
      d.add(const Duty('اختبري حالك بالقطنة قبل كل صلاة لتعرفي قسم استحاضتك، أو اعملي بوظيفة القسم الأعلى احتياطًا', RuleRef('I2-01'), classification: 'ihtiyat_wujubi'));
      d.addAll(_common());
      return d;
    }
    switch (level) {
      case IstihadhaLevel.qalila:
        d.add(const Duty('الوضوء لكل صلاة، فريضة أو نافلة، وغسل ظاهر الفرج إن تلوث', RuleRef('I2-02')));
        d.add(const Duty('لا يُجمع بين صلاتين بوضوء واحد إلا في النقاء التام من أول الوضوء إلى آخر الثانية', RuleRef('I2-02')));
      case IstihadhaLevel.mutawassita:
        d.add(const Duty('الوضوء لكل صلاة كالقليلة', RuleRef('I2-03')));
        d.add(const Duty('غسل واحد في اليوم قبل الوضوء، للصلاة التي حدثت المتوسطة قبلها، ثم لصلاة الصبح كل يوم', RuleRef('I2-03'), classification: 'ihtiyat_wujubi'));
        d.add(const Duty('إن لم تغتسلي للصبح اغتسلي للظهرين وأعيدي الصبح', RuleRef('I2-03'), classification: 'ihtiyat_wujubi'));
      case IstihadhaLevel.kathira:
        if (flow == IstihadhaFlow.continuous) {
          d.add(const Duty('ثلاثة أغسال: للصبح، وللظهرين مجموعتين، وللعشاءين مجموعتين؛ والتفريق يوجب غسلًا لكل صلاة', RuleRef('I2-04')));
        } else {
          d.add(const Duty('الغسل عند كل بروز للدم على القطنة؛ وإن اتسعت الفترة لعدة صلوات كفى غسل واحد لها', RuleRef('I2-04'), classification: 'ihtiyat_wujubi'));
        }
        d.add(const Duty('لا وضوء', RuleRef('I2-04')));
        d.add(const Duty('تجديد القطنة والخرقة لكل صلاة مع الإمكان', RuleRef('I2-04'), classification: 'ihtiyat_wujubi'));
    }
    d.addAll(_common());
    return d;
  }

  List<Duty> _common() => const [
        Duty('المبادرة إلى الصلاة بعد الطهارة بلا فصل طويل؛ ويجوز الأذان والإقامة والمقدمات', RuleRef('I2-08'), classification: 'ihtiyat_wujubi'),
        Duty('التحفظ من خروج الدم من حين الشروع في الطهارة إلى تمام الصلاة مع أمن الضرر؛ والتقصير يوجب إعادة الصلاة', RuleRef('I2-09'), classification: 'ihtiyat_wujubi'),
        Duty('إن علمتِ بفترة ينقطع فيها الدم بما يسع الطهارة والصلاة فأخّري الصلاة إليها، إلا أن تكون أول الوقت فلا تؤخري عنها', RuleRef('I2-06'), classification: 'ihtiyat_wujubi'),
        Duty('إذا انتقل القسم إلى الأعلى قبل الصلاة فبوظيفة الأعلى، وفي أثنائها تستأنف؛ وإلى الأدنى فالصلاة الأولى بالأعلى والباقي بالأدنى', RuleRef('I2-07'), classification: 'ihtiyat_wujubi'),
        Duty('صلاة الآيات والقضاء بوظائف مستقلة', RuleRef('I2-11'), classification: 'ihtiyat_wujubi'),
        Duty('مس كتابة المصحف قبل تحصيل الطهارة؛ ويجوز في أثناء الصلاة دون ما بعدها', RuleRef('I2-10'), kind: DutyKind.prohibition),
        Duty('الصوم صحيح بلا توقف على الغسل', RuleRef('I2-10'), kind: DutyKind.permission),
        Duty('المقاربة جائزة', RuleRef('I2-10'), kind: DutyKind.permission),
        Duty('دخول المساجد وقراءة العزائم جائزان', RuleRef('I2-10'), kind: DutyKind.permission),
        Duty('الطلاق جائز', RuleRef('I2-12'), kind: DutyKind.permission),
        Duty('ترك ما وجب احتياطًا من الوظائف يُبطل الصلاة', RuleRef('I2-13'), classification: 'ihtiyat_wujubi', kind: DutyKind.alert),
      ];
}
