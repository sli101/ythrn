/// حالة اليوم (`docs/SPEC.md` §٢.١).
enum DayState {
  hayd,
  nifas,
  istQ,
  istM,
  istK,

  /// استحاضة لم يُحدَّد قسمها بعد.
  istU,
  tahir,

  /// الجمع بين أحكام الطاهرة والحائض (النقاء المتخلل).
  jam3,

  /// الجمع بين تروك الحائض وأعمال المستحاضة (الدم المشكوك).
  jam3M,
  jam3N,
  jam3NM,

  /// دم ليس من الثلاثة.
  ghayr,

  /// ينتظر مدخلًا محددًا.
  pending;

  String get code => switch (this) {
        hayd => 'HAYD',
        nifas => 'NIFAS',
        istQ => 'IST_Q',
        istM => 'IST_M',
        istK => 'IST_K',
        istU => 'IST_U',
        tahir => 'TAHIR',
        jam3 => 'JAM3',
        jam3M => 'JAM3_M',
        jam3N => 'JAM3_N',
        jam3NM => 'JAM3_NM',
        ghayr => 'GHAYR',
        pending => 'PENDING',
      };

  bool get isIstihadha => this == istQ || this == istM || this == istK || this == istU;

  /// الجمع الاحتياطي بأنواعه.
  bool get isJam3 => this == jam3 || this == jam3M || this == jam3N || this == jam3NM;

  /// الحالات التي تُقدَّم عند تمثيل يوم مختلط.
  bool get isBloodRuling => this == hayd || this == nifas || this == jam3 || this == jam3M || this == jam3N || this == jam3NM;
}
