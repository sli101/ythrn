import '../fiqh/fiqh.dart';
import 'app_settings.dart';

/// حدث مخزَّن بمعرّفه (للتعديل والحذف من الخط الزمني).
class StoredEvent {
  const StoredEvent(this.id, this.event);
  final String id;
  final FiqhEvent event;
}

/// كل ما يحفظه التطبيق محليًّا.
class StoredState {
  const StoredState({
    this.profile = const FiqhProfile(),
    this.events = const [],
    this.settled = const {},
    this.explained = const {},
    this.settings = const AppSettings(),
    this.marks = const [],
  });

  final FiqhProfile profile;

  /// أحداث الأجوبة والولادة والسقط؛ أما بدء الدم وانقطاعه فمن [marks].
  final List<StoredEvent> events;

  /// أيام الدم على التقويم (`docs/UX.md` §٢.٢).
  final List<BloodDay> marks;
  final Set<String> settled;
  final Set<String> explained;
  final AppSettings settings;

  StoredState copyWith({
    FiqhProfile? profile,
    List<StoredEvent>? events,
    Set<String>? settled,
    Set<String>? explained,
    AppSettings? settings,
    List<BloodDay>? marks,
  }) =>
      StoredState(
        profile: profile ?? this.profile,
        events: events ?? this.events,
        settled: settled ?? this.settled,
        explained: explained ?? this.explained,
        settings: settings ?? this.settings,
        marks: marks ?? this.marks,
      );
}

/// المخزن المحلي الوحيد (الخيار أ: لا خادم). التنفيذ بـ drift في
/// `drift_fiqh_store.dart`، وفي الذاكرة للاختبارات هنا.
abstract class FiqhStore {
  Future<StoredState> load();
  Future<void> saveProfile(FiqhProfile profile);
  Future<void> saveSettled(Set<String> settled);
  Future<void> saveExplained(Set<String> explained);
  Future<void> saveSettings(AppSettings settings);
  Future<void> saveMarks(List<BloodDay> marks);
  Future<void> upsertEvent(StoredEvent e);
  Future<void> deleteEvent(String id);

  /// حذف كل البيانات (الإعدادات تبقى).
  Future<void> clearAll();

  /// استبدال كل البيانات بنسخة مستوردة (الاستيراد).
  Future<void> replaceAll(StoredState s);
}

/// مخزن في الذاكرة للاختبارات والمستكشف.
class MemoryFiqhStore implements FiqhStore {
  MemoryFiqhStore([StoredState? initial]) : state = initial ?? const StoredState();
  StoredState state;

  @override
  Future<StoredState> load() async => state;

  @override
  Future<void> saveProfile(FiqhProfile profile) async => state = state.copyWith(profile: profile);

  @override
  Future<void> saveSettled(Set<String> settled) async => state = state.copyWith(settled: settled);

  @override
  Future<void> saveExplained(Set<String> explained) async => state = state.copyWith(explained: explained);

  @override
  Future<void> saveSettings(AppSettings settings) async => state = state.copyWith(settings: settings);

  @override
  Future<void> saveMarks(List<BloodDay> marks) async => state = state.copyWith(marks: marks);

  @override
  Future<void> upsertEvent(StoredEvent e) async {
    final events = [...state.events.where((x) => x.id != e.id), e];
    state = state.copyWith(events: events);
  }

  @override
  Future<void> deleteEvent(String id) async => state = state.copyWith(events: state.events.where((x) => x.id != id).toList());

  @override
  Future<void> clearAll() async => state = StoredState(settings: state.settings);

  @override
  Future<void> replaceAll(StoredState s) async => state = s;
}
