import 'dart:convert';

import 'package:drift/drift.dart';

import '../fiqh/fiqh.dart';
import 'app_settings.dart';
import 'db/app_database.dart';
import 'fiqh_store.dart';

/// المخزن المحلي بـ drift. المفاتيح: `profile`، `settled`، `explained`، `settings`.
class DriftFiqhStore implements FiqhStore {
  DriftFiqhStore(this._db);
  final AppDatabase _db;

  static const _profileKey = 'profile';
  static const _settledKey = 'settled';
  static const _explainedKey = 'explained';
  static const _settingsKey = 'settings';
  static const _marksKey = 'marks';

  @override
  Future<StoredState> load() async {
    final rows = await (_db.select(_db.fiqhEvents)..where((t) => t.deletedAt.isNull())).get();
    final kv = {for (final r in await _db.select(_db.keyValues).get()) r.key: r.value};
    Object? json(String key) => kv[key] == null ? null : jsonDecode(kv[key]!);
    final profileJson = json(_profileKey) as Map?;
    final settingsJson = json(_settingsKey) as Map?;
    return StoredState(
      profile: profileJson == null ? const FiqhProfile() : FiqhCodec.decodeProfile(profileJson.cast<String, Object?>()),
      events: [for (final r in rows) StoredEvent(r.id, FiqhCodec.decodeEvent((jsonDecode(r.payload) as Map).cast<String, Object?>()))],
      settled: ((json(_settledKey) as List?) ?? const []).cast<String>().toSet(),
      explained: ((json(_explainedKey) as List?) ?? const []).cast<String>().toSet(),
      settings: settingsJson == null ? const AppSettings() : AppSettings.fromJson(settingsJson.cast<String, Object?>()),
      marks: [for (final m in (json(_marksKey) as List?) ?? const []) BloodDay.fromJson((m as Map).cast<String, Object?>())],
    );
  }

  Future<void> _put(String key, Object value) => _db.into(_db.keyValues).insertOnConflictUpdate(
        KeyValuesCompanion.insert(key: key, value: jsonEncode(value), updatedAt: Value(DateTime.now())),
      );

  @override
  Future<void> saveProfile(FiqhProfile profile) => _put(_profileKey, FiqhCodec.encodeProfile(profile));

  @override
  Future<void> saveSettled(Set<String> settled) => _put(_settledKey, settled.toList());

  @override
  Future<void> saveExplained(Set<String> explained) => _put(_explainedKey, explained.toList());

  @override
  Future<void> saveSettings(AppSettings settings) => _put(_settingsKey, settings.toJson());

  @override
  Future<void> saveMarks(List<BloodDay> marks) => _put(_marksKey, [for (final m in marks) m.toJson()]);

  @override
  Future<void> upsertEvent(StoredEvent e) {
    final payload = FiqhCodec.encodeEvent(e.event);
    return _db.into(_db.fiqhEvents).insertOnConflictUpdate(FiqhEventsCompanion.insert(
          id: e.id,
          kind: payload['kind'] as String,
          at: e.event.at,
          payload: jsonEncode(payload),
          updatedAt: Value(DateTime.now()),
          deletedAt: const Value(null),
        ));
  }

  @override
  Future<void> deleteEvent(String id) =>
      (_db.update(_db.fiqhEvents)..where((t) => t.id.equals(id))).write(FiqhEventsCompanion(deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())));

  @override
  Future<void> clearAll() async {
    await _db.delete(_db.fiqhEvents).go();
    await (_db.delete(_db.keyValues)..where((t) => t.key.isNotValue(_settingsKey))).go();
  }

  @override
  Future<void> replaceAll(StoredState s) => _db.transaction(() async {
        await _db.delete(_db.fiqhEvents).go();
        await _db.delete(_db.keyValues).go();
        for (final e in s.events) {
          await upsertEvent(e);
        }
        await saveProfile(s.profile);
        await saveSettled(s.settled);
        await saveExplained(s.explained);
        await saveSettings(s.settings);
        await saveMarks(s.marks);
      });
}
