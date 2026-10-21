/// إحالة إلى قاعدة في `assets/fiqh/rules.json`. لا حكم بلا أثر.
class RuleRef {
  const RuleRef(this.id, [this.note]);

  /// معرّف السجل، مثل `T-03` أو `H4-04`.
  final String id;

  /// تفصيل اختياري لما طُبّق من القاعدة.
  final String? note;

  @override
  String toString() => note == null ? id : '$id ($note)';

  @override
  bool operator ==(Object other) =>
      other is RuleRef && other.id == id && other.note == note;

  @override
  int get hashCode => Object.hash(id, note);
}

/// ناتج مع أثره: القيمة والقواعد التي أنتجتها بترتيب التطبيق.
class Traced<T> {
  const Traced(this.value, this.trace);
  final T value;
  final List<RuleRef> trace;

  @override
  String toString() => '$value ← $trace';
}
