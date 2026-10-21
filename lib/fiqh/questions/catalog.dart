import '../model/rule_ref.dart';
import 'question.dart';

/// فهرس الأسئلة (`docs/SPEC.md` §٦): نصوصها من حقل `unknownPolicy` في
/// القواعد، وكل سؤال يحمل قاعدته. لا مصطلح طبي؛ «الدم» و«الحيض» و«الاستحاضة»
/// و«النفاس» و«الطهر» فقط (§١٣).
///
/// معرّفات الأسئلة المرتبطة بالمحرك تطابق أسماء `pendingInput` فيه
/// (`kursufTest`، `chosenCount`، `istihadhaTest`، `miscarriageStage`، `virginityTest`).
class QuestionCatalog {
  const QuestionCatalog._();

  static Question byId(String id, {DateTime? at}) {
    final q = _all[id];
    if (q == null) throw ArgumentError('سؤال غير معرَّف: $id');
    return at == null ? q : q.copyWith(at: at);
  }

  static bool has(String id) => _all.containsKey(id);

  static Iterable<Question> get all => _all.values;

  // ------------------------------------------------------------ الملف الشخصي

  static const womanType = Question(
    id: 'womanType',
    text: 'كيف كانت عادتك في الحيض؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H4-01'),
    options: [
      QuestionOption('VW', 'تأتي في وقت معلوم من الشهر وبعدد أيام معلوم'),
      QuestionOption('V', 'تأتي في وقت معلوم فقط، وعدد الأيام يختلف'),
      QuestionOption('W', 'بعدد أيام معلوم فقط، والوقت يختلف'),
      QuestionOption('MUB', 'هذه أول مرة أرى فيها الدم'),
      QuestionOption('MUD', 'رأيته مرات ولم يستقر على وقت ولا عدد'),
    ],
    hasLadder: true,
    dontRememberLabel: 'نسيت كيف كانت',
  );

  static const firstTime = Question(
    id: 'firstTime',
    text: 'هل هذه أول مرة ترين فيها الدم في حياتك؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H4-01'),
    parentId: 'womanType',
  );

  static const sameCount = Question(
    id: 'sameCount',
    text: 'آخر مرتين رأيتِ فيهما الدم: هل استمر فيهما عدد الأيام نفسه تقريبًا؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H4-01'),
    parentId: 'womanType',
  );

  static const sameTime = Question(
    id: 'sameTime',
    text: 'وهل بدأتا في اليوم نفسه تقريبًا من الشهر، بفارق نحو شهر بينهما؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H4-01'),
    parentId: 'womanType',
  );

  static const nasiyaForgot = Question(
    id: 'nasiyaForgot',
    text: 'ماذا نسيتِ من عادتك؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H4-05'),
    options: [
      QuestionOption('time', 'نسيت وقتها وأذكر عدد أيامها'),
      QuestionOption('count', 'نسيت عدد أيامها وأذكر وقتها'),
      QuestionOption('both', 'نسيتهما معًا'),
    ],
    parentId: 'womanType',
  );

  static const habitStart = Question(
    id: 'habitStart',
    text: 'متى بدأ دم عادتك آخر مرة؟ اختاري اليوم الأول',
    kind: QuestionKind.date,
    rule: RuleRef('H4-09'),
    explanation: 'وقت العادة هو اليوم الذي يبدأ فيه الدم كل شهر تقريبًا. نحتاج آخر مرة بدأ فيها لنعرف موعد عادتك القادم.',
    dontRememberLabel: 'نسيت وقتها',
  );

  static const habitCount = Question(
    id: 'habitCount',
    text: 'كم يومًا يستمر دم عادتك؟',
    kind: QuestionKind.number,
    min: 3,
    max: 10,
    defaultValue: 6,
    rule: RuleRef('H4-01'),
    explanation: 'عدد العادة هو أيام الدم التي تتكرر كل مرة بالعدد نفسه، من أول خروجه إلى انقطاعه، بلا احتساب أيام النقاء بينها.',
    dontRememberLabel: 'نسيت عددها',
  );

  static const nasiyaCountMin = Question(
    id: 'nasiyaCountMin',
    text: 'هل تتذكرين أن حيضك لم يكن يقل عن عدد معين من الأيام؟ اكتبيه',
    kind: QuestionKind.number,
    min: 1,
    max: 10,
    rule: RuleRef('H7-05a'),
    dontRememberLabel: 'لا أتذكر حدًّا أدنى',
  );

  static const nasiyaCountMax = Question(
    id: 'nasiyaCountMax',
    text: 'وهل تتذكرين أنه لم يكن يزيد على عدد معين من الأيام؟ اكتبيه',
    kind: QuestionKind.number,
    min: 1,
    max: 10,
    rule: RuleRef('H7-05a'),
    dontRememberLabel: 'لا أتذكر حدًّا أعلى',
  );

  static const nasiyaHalfMonth = Question(
    id: 'nasiyaHalfMonth',
    text: 'هل تتذكرين أن حيضك كان يأتي دائمًا في النصف الأول من الشهر أو في النصف الثاني؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H7-05a'),
    options: [
      QuestionOption('first', 'في النصف الأول من الشهر'),
      QuestionOption('second', 'في النصف الثاني من الشهر'),
    ],
    dontRememberLabel: 'لا أتذكر نصفًا معينًا',
  );

  static const birthDate = Question(
    id: 'birthDate',
    text: 'متى وُلدتِ؟',
    kind: QuestionKind.date,
    rule: RuleRef('H1-01a'),
    hasLadder: true,
    dontRememberLabel: 'لا أعرف تاريخ ميلادي',
  );

  static const approxAge = Question(
    id: 'approxAge',
    text: 'كم عمرك تقريبًا بالسنين؟',
    kind: QuestionKind.number,
    min: 1,
    max: 100,
    defaultValue: 25,
    rule: RuleRef('H1-01a'),
    parentId: 'birthDate',
  );

  static const lastBloodEnd = Question(
    id: 'lastBloodEnd',
    text: 'متى انتهى آخر حيض أو نفاس قبل هذا الدم؟',
    kind: QuestionKind.date,
    rule: RuleRef('T-04'),
    hasLadder: true,
    dontRememberLabel: 'لا أتذكر التاريخ',
  );

  static const lastGhuslDate = Question(
    id: 'lastGhuslDate',
    text: 'متى آخر مرة اغتسلتِ من الحيض تقريبًا؟',
    kind: QuestionKind.date,
    rule: RuleRef('T-04'),
    parentId: 'lastBloodEnd',
  );

  static const moreThanTenDays = Question(
    id: 'moreThanTenDays',
    text: 'هل مضى أكثر من عشرة أيام بين انتهاء الدم السابق وبدء هذا الدم؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('T-04'),
    parentId: 'lastBloodEnd',
  );

  static const daysSinceLastBlood = Question(
    id: 'daysSinceLastBlood',
    text: 'كم يومًا تقريبًا مضى بين انتهاء الدم السابق وبدء هذا الدم؟',
    kind: QuestionKind.number,
    min: 0,
    max: 10,
    defaultValue: 5,
    rule: RuleRef('T-04'),
    parentId: 'lastBloodEnd',
  );

  static const kinCount = Question(
    id: 'kinCount',
    text: 'كم يومًا يستمر حيض أمك أو أختك أو إحدى قريباتك عادةً؟',
    kind: QuestionKind.number,
    min: 3,
    max: 10,
    defaultValue: 6,
    rule: RuleRef('H7-07'),
    explanation: 'القريبات: من جهة الأب أو الأم، حية كانت أو ميتة. إن عرفتِ عدد أيام حيض إحداهن فاكتبيه، وإلا فاختاري «لا أعرف عادة قريبة».',
    dontRememberLabel: 'لا أعرف عادة قريبة',
  );

  static const kinConditions = Question(
    id: 'kinConditions',
    text: 'هل تعلمين أن حيض هذه القريبة يختلف عن حيضك اختلافًا واضحًا، أو أنه يختلف عن سائر قريباتك؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H7-07'),
    explanation: 'كأن تكون القريبة قريبة من سن اليأس وأنتِ شابة أو العكس. إن لم تعلمي بالاختلاف فالشرط متحقق وتُرجعين إلى عادتها.',
    dontRememberLabel: 'لا أعلم بالاختلاف',
  );

  static const chosenCount = Question(
    id: 'chosenCount',
    text: 'اختاري عددًا تتحيضين به في هذا الشهر بين ثلاثة أيام وعشرة؛ والأفضل سبعة',
    kind: QuestionKind.number,
    min: 3,
    max: 10,
    defaultValue: 7,
    rule: RuleRef('H7-04a'),
    explanation: 'لا تمييز في صفات الدم ولا عادة قريبة تُرجعين إليها، فأنتِ مخيَّرة في كل شهر أن تجعلي حيضك عددًا بين الثلاثة والعشرة.',
    dontRememberLabel: 'لا أستطيع الاختيار',
  );

  static const pregnant = Question(
    id: 'pregnant',
    text: 'هل أنتِ حامل الآن؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H1-03b'),
    dontRememberLabel: 'لا أعلم',
  );

  // ------------------------------------------------------------ بدء الدم

  static const isEarlyHabit = Question(
    id: 'isEarlyHabit',
    text: 'جاء الدم قبل موعد عادتك بأكثر من يومين؛ هل تعدّين هذا تقدمًا لعادتك كما تعدّه النساء عادةً؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H5-01'),
    explanation: 'ذات العادة الوقتية تترك العبادة بمجرد رؤية الدم في وقتها أو قبله بيوم أو يومين. وإن تقدم أكثر فالمرجع ما تعدّينه أنتِ تقدمًا لعادتك.',
    dontRememberLabel: 'لا أدري',
  );

  static const bloodProps = Question(
    id: 'bloodProps',
    text: 'هل في الدم صفات الحيض؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H0-05'),
    options: [
      QuestionOption('wajid', 'نعم: أسود أو أحمر، فيه حرارة، يخرج بدفع؛ وتكفي صفة واحدة'),
      QuestionOption('faqid', 'لا: أصفر أو بارد أو يخرج بلا دفع'),
    ],
    hasLadder: true,
    dontRememberLabel: 'لم أنتبه إلى صفاته',
  );

  static const propsDark = Question(
    id: 'propsDark',
    text: 'ما لون الدم؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H0-05'),
    options: [
      QuestionOption('dark', 'أسود أو أحمر'),
      QuestionOption('light', 'أصفر أو بني فاتح أو وردي'),
    ],
    parentId: 'bloodProps',
  );

  static const propsWarm = Question(
    id: 'propsWarm',
    text: 'هل تشعرين بحرارته عند خروجه؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H0-05'),
    parentId: 'bloodProps',
  );

  static const propsThrust = Question(
    id: 'propsThrust',
    text: 'هل يخرج بدفع أو حرقة؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H0-05'),
    parentId: 'bloodProps',
  );

  static const willLastThreeDays = Question(
    id: 'willLastThreeDays',
    text: 'هل تعرفين الآن أن هذا الدم سيستمر ثلاثة أيام، ولو في الداخل؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H3-06'),
    hasLadder: true,
    dontRememberLabel: 'لا أعلم',
  );

  static const bloodUsuallyLasts = Question(
    id: 'bloodUsuallyLasts',
    text: 'هل جرت عادتك أن الدم إذا نزل بقي ثلاثة أيام أو أكثر؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H3-06'),
    parentId: 'willLastThreeDays',
  );

  // ------------------------------------------------------------ الانقطاع

  static const innerContinuity = Question(
    id: 'innerContinuity',
    text: 'انقطع الدم من الخارج؛ هل تحتملين أنه ما زال موجودًا في الداخل؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H6-01'),
    hasLadder: true,
    dontRememberLabel: 'لا أدري',
  );

  static const innerTrace = Question(
    id: 'innerTrace',
    text: 'أدخلي قطنة في موضع الدم ثم أخرجيها: هل ترين عليها أثرًا للدم ولو يسيرًا؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H6-01'),
    parentId: 'innerContinuity',
  );

  static const kursufTest = Question(
    id: 'kursufTest',
    text: 'ما نتيجة اختبار القطنة؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H6-01'),
    options: [
      QuestionOption('clean', 'خرجت نظيفة تمامًا'),
      QuestionOption('stained', 'خرجت ملوثة ولو بصفرة'),
    ],
    explanation: 'أدخلي قطنة في موضع الدم واتركيها مدة أطول من الانقطاع اليسير المعتاد، ثم أخرجيها برفق وانظري: نظيفة تمامًا، أم عليها أثر ولو صفرة؟',
    dontRememberLabel: 'لم أُجرِ الاختبار بعد',
  );

  static const willReturnBeforeTen = Question(
    id: 'willReturnBeforeTen',
    text: 'خرجت القطنة نظيفة؛ هل تعرفين من عادتك، بيقين أو اطمئنان، أن الدم يعود قبل تمام العشرة من بدء الحيض؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H6-02'),
    hasLadder: true,
    dontRememberLabel: 'أظن فقط أو لا أدري',
  );

  static const bloodUsuallyReturns = Question(
    id: 'bloodUsuallyReturns',
    text: 'في المرات السابقة: هل كان الدم ينقطع ثم يعود قبل عشرة أيام من بدايته؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H6-02'),
    parentId: 'willReturnBeforeTen',
  );

  static const willExceedTen = Question(
    id: 'willExceedTen',
    text: 'انتهت أيام عادتك والقطنة ملوثة؛ هل تعرفين ما سيكون؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H6-03'),
    options: [
      QuestionOption('stop', 'سينقطع قبل تمام العشرة أو عليها'),
      QuestionOption('exceed', 'سيتجاوز العشرة'),
    ],
    dontRememberLabel: 'لا أعرف',
  );

  // ------------------------------------------------------------ الاستحاضة

  static const istihadhaTest = Question(
    id: 'istihadhaTest',
    text: 'اختبري حالك بالقطنة قبل الصلاة: ماذا رأيتِ؟',
    kind: QuestionKind.choice,
    rule: RuleRef('I2-01'),
    options: [
      QuestionOption('qalila', 'تلوثت القطنة ولم يغمسها الدم'),
      QuestionOption('mutawassita', 'غمسها الدم ولم يتجاوزها إلى الخرقة'),
      QuestionOption('kathira', 'غمسها وتجاوزها إلى الخرقة'),
    ],
    explanation: 'ضعي قطنة في موضع الدم وانتظري قليلًا ثم أخرجيها. إن تلوثت من غير أن ينفذ فيها الدم فهي القليلة، وإن نفذ فيها ولم يتجاوزها إلى ما وراءها فالمتوسطة، وإن تجاوزها فالكثيرة.',
    dontRememberLabel: 'لم أختبر بعد',
  );

  static const istihadhaFlow = Question(
    id: 'istihadhaFlow',
    text: 'كيف يظهر الدم؟',
    kind: QuestionKind.choice,
    rule: RuleRef('I2-04'),
    options: [
      QuestionOption('continuous', 'يظهر على القطنة باستمرار بلا انقطاع'),
      QuestionOption('intermittent', 'تمرّ فترات أستطيع فيها الغسل والصلاة قبل أن يظهر مرة أخرى'),
    ],
    dontRememberLabel: 'لا أدري',
  );

  // ------------------------------------------------------------ النفاس والسقط

  static const miscarriageStage = Question(
    id: 'miscarriageStage',
    text: 'ما مرحلة الجنين عند السقط؟',
    kind: QuestionKind.choice,
    rule: RuleRef('M-01'),
    options: [
      QuestionOption('nutfa', 'نطفة'),
      QuestionOption('alaqa', 'علقة'),
      QuestionOption('mudgha', 'مضغة'),
      QuestionOption('formed', 'له صورة إنسان: أعضاء ظاهرة'),
    ],
    hasLadder: true,
    guidance: 'إن لم تعرفي فاسألي من حضر السقط أو من يعرف حاله؛ لا يُحكم بالنفاس ولا بغيره قبل ذلك.',
    dontRememberLabel: 'لا أعرف',
  );

  static const humanForm = Question(
    id: 'humanForm',
    text: 'هل كان للساقط صورة إنسان، بأعضاء ظاهرة؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('M-01'),
    parentId: 'miscarriageStage',
  );

  static const ensouled = Question(
    id: 'ensouled',
    text: 'هل كانت الروح قد ولجت في الجنين عند السقط؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('M-06'),
    hasLadder: true,
    dontRememberLabel: 'لا أعلم',
  );

  static const fourMonths = Question(
    id: 'fourMonths',
    text: 'هل كان الحمل قد بلغ نحو أربعة أشهر عند السقط؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('M-06'),
    parentId: 'ensouled',
  );

  // ------------------------------------------------------------ تمييز الدم

  static const virginityTest = Question(
    id: 'virginityTest',
    text: 'ما نتيجة اختبار القطنة؟',
    kind: QuestionKind.choice,
    rule: RuleRef('H2-01'),
    options: [
      QuestionOption('ringed', 'الدم على أطرافها فقط: مطوّقة'),
      QuestionOption('soaked', 'غمرها كلها: مستنقعة'),
    ],
    explanation: 'أدخلي قطنة وانتظري حتى ينفذ فيها الدم ثم أخرجيها برفق: إن كان الدم على أطرافها فقط فهي مطوّقة ودمها دم البكارة، وإن غمرها كلها فهي مستنقعة ودمها حيض.',
    dontRememberLabel: 'تعذّر الاختبار',
  );

  // ------------------------------------------------------------ الوظائف

  static const ramadanTomorrow = Question(
    id: 'ramadanTomorrow',
    text: 'هل أنتِ صائمة غدًا صوم رمضان أو قضاءه؟',
    kind: QuestionKind.yesNo,
    rule: RuleRef('H9-15'),
    dontRememberLabel: 'لا أدري',
  );

  static const Map<String, Question> _all = {
    'womanType': womanType,
    'firstTime': firstTime,
    'sameCount': sameCount,
    'sameTime': sameTime,
    'nasiyaForgot': nasiyaForgot,
    'habitStart': habitStart,
    'habitCount': habitCount,
    'nasiyaCountMin': nasiyaCountMin,
    'nasiyaCountMax': nasiyaCountMax,
    'nasiyaHalfMonth': nasiyaHalfMonth,
    'birthDate': birthDate,
    'approxAge': approxAge,
    'lastBloodEnd': lastBloodEnd,
    'lastGhuslDate': lastGhuslDate,
    'moreThanTenDays': moreThanTenDays,
    'daysSinceLastBlood': daysSinceLastBlood,
    'kinCount': kinCount,
    'kinConditions': kinConditions,
    'chosenCount': chosenCount,
    'pregnant': pregnant,
    'isEarlyHabit': isEarlyHabit,
    'bloodProps': bloodProps,
    'propsDark': propsDark,
    'propsWarm': propsWarm,
    'propsThrust': propsThrust,
    'willLastThreeDays': willLastThreeDays,
    'bloodUsuallyLasts': bloodUsuallyLasts,
    'innerContinuity': innerContinuity,
    'innerTrace': innerTrace,
    'kursufTest': kursufTest,
    'willReturnBeforeTen': willReturnBeforeTen,
    'bloodUsuallyReturns': bloodUsuallyReturns,
    'willExceedTen': willExceedTen,
    'istihadhaTest': istihadhaTest,
    'istihadhaFlow': istihadhaFlow,
    'miscarriageStage': miscarriageStage,
    'humanForm': humanForm,
    'ensouled': ensouled,
    'fourMonths': fourMonths,
    'virginityTest': virginityTest,
    'ramadanTomorrow': ramadanTomorrow,
  };
}
