import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../fiqh/fiqh.dart';

/// نصوص الواجهة وألوانها. لا مصطلح طبي (`docs/SPEC.md` §١٣).
class Labels {
  const Labels._();

  static String state(DayState s) => switch (s) {
    DayState.hayd => 'حيض',
    DayState.nifas => 'نفاس',
    DayState.istQ => 'استحاضة قليلة',
    DayState.istM => 'استحاضة متوسطة',
    DayState.istK => 'استحاضة كثيرة',
    DayState.istU => 'استحاضة لم يُحدَّد قسمها',
    DayState.tahir => 'طهر',
    DayState.jam3 => 'جمع احتياطي: نقاء متخلل',
    DayState.jam3M => 'جمع احتياطي: دم مشكوك',
    DayState.jam3N => 'جمع احتياطي: نفاس',
    DayState.jam3NM => 'جمع احتياطي: نفاس ودم مشكوك',
    DayState.ghayr => 'ليس من الدماء الثلاثة',
    DayState.pending => 'ينتظر جوابًا',
  };

  static Color stateColor(DayState s) => switch (s) {
    DayState.hayd => const Color(0xFFB71C1C),
    DayState.nifas => const Color(0xFF6A1B9A),
    DayState.istQ || DayState.istM || DayState.istK || DayState.istU => const Color(0xFFE65100),
    DayState.tahir => const Color(0xFF2E7D32),
    DayState.jam3 || DayState.jam3M || DayState.jam3N || DayState.jam3NM => const Color(0xFFF9A825),
    DayState.ghayr => const Color(0xFF455A64),
    DayState.pending => const Color(0xFF757575),
  };

  static IconData stateIcon(DayState s) => switch (s) {
    DayState.hayd || DayState.nifas => Icons.water_drop,
    DayState.istQ || DayState.istM || DayState.istK || DayState.istU => Icons.opacity,
    DayState.tahir => Icons.check_circle_outline,
    DayState.jam3 || DayState.jam3M || DayState.jam3N || DayState.jam3NM => Icons.balance,
    DayState.ghayr => Icons.remove_circle_outline,
    DayState.pending => Icons.help_outline,
  };

  static String classification(String c) => switch (c) {
    'fatwa' => 'فتوى',
    'ihtiyat_wujubi' => 'احتياط وجوبي',
    'ishkal' => 'محل إشكال',
    'ihtiyat_istihbabi' => 'احتياط استحبابي',
    _ => 'غير محدد',
  };

  static String dutyKind(DutyKind k) => switch (k) {
    DutyKind.obligation => 'الواجبات',
    DutyKind.prohibition => 'المحرمات',
    DutyKind.permission => 'المباحات',
    DutyKind.alert => 'تنبيهات',
  };

  static String womanType(WomanType t) => switch (t) {
    WomanType.vw => 'ذات عادة وقتية وعددية',
    WomanType.v => 'ذات عادة وقتية',
    WomanType.w => 'ذات عادة عددية',
    WomanType.mub => 'مبتدئة',
    WomanType.mud => 'مضطربة',
    WomanType.nasT => 'ناسية الوقت',
    WomanType.nasC => 'ناسية العدد',
    WomanType.nasB => 'ناسية الوقت والعدد',
  };

  static String event(FiqhEvent e) => switch (e) {
    BloodStart() => e.spots ? 'لطخات' : 'نزل الدم',
    BloodStop() => 'انقطع الدم',
    FullStop() => 'انقطاع تام ${e.duration.inMinutes} دقيقة',
    PropsChange() =>
      e.props == BloodProps.wajid
          ? 'الدم بصفات الحيض'
          : e.props == BloodProps.faqid
          ? 'الدم بلا صفات الحيض'
          : 'تغيّر الصفات',
    KursufTest() => e.result == KursufResult.clean ? 'القطنة نظيفة' : 'القطنة ملوثة',
    InnerContinuity() => 'احتمال بقاء الدم داخلًا: ${tri(e.value)}',
    Expectation() => switch (e.kind) {
      ExpectationKind.willLastThreeDays => 'سيستمر ثلاثة أيام: ${tri(e.value)}',
      ExpectationKind.willReturnBeforeTen => 'يعود قبل العشرة: ${tri(e.value)}',
      ExpectationKind.willExceedTen => 'يتجاوز العشرة: ${tri(e.value)}',
    },
    IsEarlyHabit() => 'تعجيل العادة: ${tri(e.value)}',
    Ghusl() => 'اغتسلت',
    RamadanNote() => e.isRamadan ? 'الغد من رمضان' : 'الغد ليس من رمضان',
    Birth() => e.twins ? 'ولادة توأم' : 'ولادة',
    Miscarriage() => 'سقط${e.stage == null ? '' : ': ${miscarriageStage(e.stage!)}'}',
    IstihadhaTest() => 'اختبار الاستحاضة: ${istihadhaLevel(e.level)}',
    VirginityTest() => e.result == VirginityTestResult.ringed ? 'القطنة مطوّقة' : 'القطنة مستنقعة',
    SourceNote() => 'مصدر الدم',
  };

  static String tri(Tri<bool> t) => t.when(known: (v) => v ? 'نعم' : 'لا', unknown: (k) => k == UnknownKind.dontUnderstand ? 'لم أفهم' : 'لا أعلم');

  static String miscarriageStage(MiscarriageStage s) => switch (s) {
    MiscarriageStage.nutfa => 'نطفة',
    MiscarriageStage.alaqa => 'علقة',
    MiscarriageStage.mudgha => 'مضغة',
    MiscarriageStage.formed => 'متخلق',
  };

  static String istihadhaLevel(IstihadhaLevel l) => switch (l) {
    IstihadhaLevel.qalila => 'قليلة',
    IstihadhaLevel.mutawassita => 'متوسطة',
    IstihadhaLevel.kathira => 'كثيرة',
  };

  static final _dateFmt = DateFormat('EEEE d MMMM y', 'ar');
  static final _shortDateFmt = DateFormat('d MMM', 'ar');
  static final _timeFmt = DateFormat('h:mm a', 'ar');
  static final _monthYearFmt = DateFormat('MMMM y', 'ar');

  static String date(DateTime d) => _dateFmt.format(d);
  static String shortDate(DateTime d) => _shortDateFmt.format(d);
  static String time(DateTime d) => _timeFmt.format(d);
  static String monthYear(DateTime d) => _monthYearFmt.format(d);
  static String dateTime(DateTime d) => '${_shortDateFmt.format(d)} ${_timeFmt.format(d)}';
}
