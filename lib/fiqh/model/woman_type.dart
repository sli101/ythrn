/// أقسام النساء (`docs/SPEC.md` §٢.٢؛ H4-01، H4-05).
enum WomanType {
  /// ذات العادة الوقتية والعددية.
  vw,

  /// ذات العادة الوقتية فقط.
  v,

  /// ذات العادة العددية فقط.
  w,

  /// المبتدئة: ترى الدم لأول مرة.
  mub,

  /// المضطربة: تكررت رؤيتها ولم تستقر لها عادة، أو زالت عادتها.
  mud,

  /// ناسية الوقت.
  nasT,

  /// ناسية العدد.
  nasC,

  /// ناسيتهما.
  nasB;

  bool get hasTime => this == vw || this == v;
  bool get hasCount => this == vw || this == w;
  bool get hasHabit => hasTime || hasCount;
  bool get isNasiya => this == nasT || this == nasC || this == nasB;

  /// الرمز كما في `rules.json` والحالات الذهبية.
  String get code => switch (this) {
        vw => 'VW',
        v => 'V',
        w => 'W',
        mub => 'MUB',
        mud => 'MUD',
        nasT => 'NAS_T',
        nasC => 'NAS_C',
        nasB => 'NAS_B',
      };

  static WomanType fromCode(String code) =>
      values.firstWhere((t) => t.code == code);
}

/// محدد العادة الوقتية: بأولها أو بآخرها (H4-09).
enum HabitAnchor { start, end }
