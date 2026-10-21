import 'package:drift/drift.dart';

import 'connection/connection.dart';

part 'app_database.drift.dart';

/// لا مزامنة عبر خادم (قرار المالك ٢٠٢٦/١٠/٠١، الخيار أ): البيانات لا تغادر
/// الجهاز إلا بتصدير يدوي. يُحتفظ بـ [id] الفريد و[updatedAt] في كل صف لأن
/// أي مزامنة مستقبلية لا تحتاج أكثر منهما.

/// أحداث السجل الحي (`docs/SPEC.md` §٣.٢) بترميز `FiqhCodec` في [payload].
class FiqhEvents extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  DateTimeColumn get at => dateTime()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// قيم مفردة بالمفتاح: الملف الشخصي، المفاتيح المسوّاة، الإعدادات (JSON).
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [FiqhEvents, KeyValues])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  /// للاختبارات: قاعدة في الذاكرة أو أي منفّذ آخر.
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 4) {
            // الإصدارات ١–٣ كانت نموذجًا أوليًّا (جدولا case_records و
            // question_answers) سبق المحرك؛ تُستبدل بجداول السجل الحي.
            await migrator.createTable(fiqhEvents);
            await migrator.createTable(keyValues);
            await customStatement('DROP TABLE IF EXISTS question_answers');
            await customStatement('DROP TABLE IF EXISTS case_records');
          }
        },
      );
}
