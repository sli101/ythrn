import '../model/events.dart';
import '../model/profile.dart';
import 'question.dart';

/// نوع السلّم الجاري: مشاهدة بعد «لا أفهم»، أو تذكّر جزئي بعد «لا أتذكر».
enum LadderKind { understand, remember }

/// سلّم أسئلة أبسط فُتح تحت سؤال أصل؛ أجوبته تُطوى إلى جواب الأصل.
class Ladder {
  const Ladder({required this.parent, required this.kind, this.answers = const {}});
  final Question parent;
  final LadderKind kind;

  /// أجوبة الخطوات بمعرّفها (`bool`، `String`، `int`، `DateTime`).
  final Map<String, Object?> answers;

  Ladder withAnswer(String stepId, Object? value) => Ladder(parent: parent, kind: kind, answers: {...answers, stepId: value});
}

/// حالة الحوار: الملف والأحداث والآن، وما سُوّي من الأسئلة.
///
/// قيمة لا تتغير؛ كل جواب يعيد جلسة جديدة. التطبيق يحفظ [profile] و[events]
/// و[settled] و[explained] فقط؛ و[ladder] حالة عابرة داخل الشاشة.
class QuestionSession {
  const QuestionSession({
    required this.profile,
    required this.events,
    required this.now,
    this.settled = const {},
    this.explained = const {},
    this.ladder,
  });

  final FiqhProfile profile;
  final List<FiqhEvent> events;
  final DateTime now;

  /// مفاتيح أسئلة أُجيبت (بأي مخرج) أو تُخُطّيت؛ لا تُسأل ثانية.
  final Set<String> settled;

  /// مفاتيح أسئلة طُلب شرحها.
  final Set<String> explained;

  final Ladder? ladder;

  bool isSettled(String key) => settled.contains(key);

  QuestionSession copyWith({
    FiqhProfile? profile,
    List<FiqhEvent>? events,
    DateTime? now,
    Set<String>? settled,
    Set<String>? explained,
    Ladder? ladder,
    bool clearLadder = false,
  }) =>
      QuestionSession(
        profile: profile ?? this.profile,
        events: events ?? this.events,
        now: now ?? this.now,
        settled: settled ?? this.settled,
        explained: explained ?? this.explained,
        ladder: clearLadder ? null : (ladder ?? this.ladder),
      );

  QuestionSession settle(String key) => copyWith(settled: {...settled, key});

  QuestionSession addEvent(FiqhEvent e) => copyWith(events: [...events, e]);
}
