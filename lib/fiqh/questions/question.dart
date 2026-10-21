import '../model/rule_ref.dart';

/// نوع الجواب الذي ينتظره السؤال.
enum QuestionKind {
  /// نعم / لا.
  yesNo,

  /// اختيار من [Question.options].
  choice,

  /// عدد صحيح بين [Question.min] و[Question.max].
  number,

  /// تاريخ (اليوم).
  date,
}

/// خيار في سؤال اختيار. [value] هو ما تردّه الواجهة في [Reply.value].
class QuestionOption {
  const QuestionOption(this.value, this.label);
  final String value;
  final String label;
}

/// سؤال واحد تعرضه الواجهة (`docs/SPEC.md` §٦، §١٠).
///
/// لكل سؤال، إلى جانب الجواب، ثلاثة مخارج: «لا أفهم السؤال» (جهل بالحكم)
/// و«لا أتذكر» (جهل بالموضوع) وتخطٍّ مؤقت. كلها قيم أولى لا أخطاء إدخال.
class Question {
  const Question({
    required this.id,
    required this.text,
    required this.kind,
    required this.rule,
    this.at,
    this.options = const [],
    this.min,
    this.max,
    this.defaultValue,
    this.explanation,
    this.hasLadder = false,
    this.dontRememberLabel = 'لا أتذكر',
    this.guidance,
    this.parentId,
    this.explained = false,
  });

  /// معرّف السؤال في الفهرس (ثابت؛ تستعمله الاختبارات والتخزين).
  final String id;

  /// اللحظة التي يتعلق بها الجواب (بدء الدم، الانقطاع…)؛ `null` للملف الشخصي.
  final DateTime? at;

  final String text;
  final QuestionKind kind;
  final List<QuestionOption> options;
  final int? min;
  final int? max;

  /// القيمة التي يبدأ بها منتقي العدد (مثل سبعة للعدد المختار).
  final int? defaultValue;

  /// القاعدة التي يخدمها السؤال (لعرض «لماذا يُسأل؟» ولأثر الحكم).
  final RuleRef rule;

  /// شرح يُعرض عند «لا أفهم» إذا لم يكن للسؤال سلّم مشاهدة.
  final String? explanation;

  /// «لا أفهم» يفتح سلّم أسئلة مشاهدة أبسط يستنتج منها الجواب.
  final bool hasLadder;

  /// نص زر «لا أتذكر» حين يناسب غيره (مثل «لم أُجرِ الاختبار»).
  final String dontRememberLabel;

  /// توجيه يُعرض مع السؤال إذا كان الجواب يحتاج من يعرف (لا رأي طبي).
  final String? guidance;

  /// إن كان السؤال خطوة في سلّم: معرّف السؤال الأصل.
  final String? parentId;

  /// هل طُلب شرحه من قبل (فتعرضه الواجهة مع السؤال).
  final bool explained;

  /// مفتاح التسوية: المعرّف مع اللحظة إن وُجدت، حتى يُسأل السؤال نفسه مرة
  /// واحدة لكل واقعة ويُعاد في الواقعة التالية.
  String get key => keyFor(id, at);

  static String keyFor(String id, DateTime? at) => at == null ? id : '$id@${at.toIso8601String()}';

  bool get isLadderStep => parentId != null;

  Question copyWith({DateTime? at, String? text, bool? explained, String? parentId}) => Question(
        id: id,
        at: at ?? this.at,
        text: text ?? this.text,
        kind: kind,
        rule: rule,
        options: options,
        min: min,
        max: max,
        defaultValue: defaultValue,
        explanation: explanation,
        hasLadder: hasLadder,
        dontRememberLabel: dontRememberLabel,
        guidance: guidance,
        parentId: parentId ?? this.parentId,
        explained: explained ?? this.explained,
      );

  @override
  String toString() => 'Question($key)';
}

/// جواب المستخدمة على سؤال.
sealed class Reply {
  const Reply();

  /// جواب بقيمة: `bool` لنعم/لا، `String` للاختيار، `int` للعدد، `DateTime` للتاريخ.
  const factory Reply.value(Object value) = ValueReply;

  /// «لا أفهم السؤال»: جهل بالحكم → سلّم مشاهدة أو شرح.
  static const Reply dontUnderstand = DontUnderstandReply();

  /// «لا أتذكر / لا أعرف»: جهل بالموضوع → المسار المنصوص.
  static const Reply dontRemember = DontRememberReply();

  /// تخطٍّ مؤقت: لا يُسأل ثانية في هذه الواقعة حتى تُلغى التسوية.
  static const Reply skip = SkipReply();
}

final class ValueReply extends Reply {
  const ValueReply(this.value);
  final Object value;

  @override
  String toString() => 'Reply.value($value)';
}

final class DontUnderstandReply extends Reply {
  const DontUnderstandReply();

  @override
  String toString() => 'Reply.dontUnderstand';
}

final class DontRememberReply extends Reply {
  const DontRememberReply();

  @override
  String toString() => 'Reply.dontRemember';
}

final class SkipReply extends Reply {
  const SkipReply();

  @override
  String toString() => 'Reply.skip';
}
