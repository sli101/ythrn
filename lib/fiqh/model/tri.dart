/// قيمة ثلاثية: معلومة، أو مجهولة بأحد نوعي الجهل (`docs/SPEC.md` §٢.٤).
///
/// «لا أعلم» قيمة أولى لا خطأ إدخال، ولها معنيان يجب التفريق بينهما:
/// - [UnknownKind.dontUnderstand]: جهل بالحكم (لا تفهم السؤال) → سؤال مشاهدة أبسط.
/// - [UnknownKind.dontRemember]: جهل بالموضوع (لا تتذكر الواقعة) → مسار منصوص.
sealed class Tri<T> {
  const Tri();

  const factory Tri.known(T value) = Known<T>;
  const factory Tri.unknown(UnknownKind kind) = Unknown<T>;

  /// الافتراضي لكل مدخل لم تُجب عنه بعد.
  static const Tri<Never> dontRemember = Unknown(UnknownKind.dontRemember);
  static const Tri<Never> dontUnderstand = Unknown(UnknownKind.dontUnderstand);

  bool get isKnown => this is Known<T>;

  T? get valueOrNull => switch (this) {
        Known<T>(:final value) => value,
        Unknown<T>() => null,
      };

  R when<R>({
    required R Function(T value) known,
    required R Function(UnknownKind kind) unknown,
  }) =>
      switch (this) {
        Known<T>(:final value) => known(value),
        Unknown<T>(:final kind) => unknown(kind),
      };
}

final class Known<T> extends Tri<T> {
  const Known(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is Known<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Known, value);

  @override
  String toString() => 'Known($value)';
}

final class Unknown<T> extends Tri<T> {
  const Unknown(this.kind);
  final UnknownKind kind;

  @override
  bool operator ==(Object other) => other is Unknown<T> && other.kind == kind;

  @override
  int get hashCode => Object.hash(Unknown, kind);

  @override
  String toString() => 'Unknown(${kind.name})';
}

enum UnknownKind { dontUnderstand, dontRemember }
