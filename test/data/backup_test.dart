import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/data/app_settings.dart';
import 'package:ythrn/data/backup.dart';
import 'package:ythrn/data/fiqh_store.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// النسخ الاحتياطي: ذهابًا وإيابًا بالمعرّفات، ورفض الملفات الغريبة.
void main() {
  final state = StoredState(
    profile: FiqhProfile(habit: const HabitState(type: WomanType.vw, count: 7, origin: HabitOrigin.declared), birth: Tri.known(DateTime(1996, 5, 4))),
    events: [StoredEvent('a1', BloodStart(DateTime(2026, 3, 1, 6))), StoredEvent('a2', KursufTest(DateTime(2026, 3, 8, 9), KursufResult.clean))],
    settled: const {'womanType', 'habitCount'},
    explained: const {'bloodProps'},
    settings: const AppSettings(manualFajrMinutes: 270, manualMaghribMinutes: 1110, placeName: 'النجف'),
  );

  test('التصدير ثم الاستيراد يعيد الحالة نفسها', () {
    final text = Backup.encode(state, exportedAt: DateTime(2026, 10, 2));
    expect(text, contains('"format": "ythrn-backup"'));
    final back = Backup.decode(text);
    expect(back.events.map((e) => e.id), ['a1', 'a2']);
    expect(back.events[1].event, isA<KursufTest>());
    expect(back.profile.habit.type, WomanType.vw);
    expect(back.profile.birth, Tri.known(DateTime(1996, 5, 4)));
    expect(back.settled, {'womanType', 'habitCount'});
    expect(back.explained, {'bloodProps'});
    expect(back.settings.placeName, 'النجف');
    expect(back.settings.manualFajrMinutes, 270);
  });

  test('يرفض نصًّا ليس JSON أو ليس نسخة أو من إصدار أحدث أو حدثًا بلا معرّف', () {
    expect(() => Backup.decode('x'), throwsFormatException);
    expect(() => Backup.decode('{"a":1}'), throwsFormatException);
    expect(() => Backup.decode('{"format":"ythrn-backup","version":99}'), throwsFormatException);
    expect(() => Backup.decode('{"format":"ythrn-backup","version":1,"events":[{"kind":"ghusl","at":"2026-01-01T00:00:00.000"}]}'), throwsFormatException);
  });

  test('المخزن في الذاكرة يستبدل كل شيء بالاستيراد', () async {
    final store = MemoryFiqhStore(const StoredState(settled: {'x'}));
    await store.replaceAll(state);
    expect((await store.load()).events.length, 2);
    expect((await store.load()).settled, {'womanType', 'habitCount'});
  });
}
