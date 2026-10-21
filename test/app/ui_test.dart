import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ythrn/app/app.dart';
import 'package:ythrn/app/clock.dart';
import 'package:ythrn/app/providers.dart';
import 'package:ythrn/app/screens/explorer_screen.dart';
import 'package:ythrn/app/screens/what_if_screen.dart';
import 'package:ythrn/app/widgets/date_picker.dart';
import 'package:ythrn/data/app_settings.dart';
import 'package:ythrn/data/backup.dart';
import 'package:ythrn/data/fiqh_store.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// واجهة `docs/UX.md`: اسألي → التقويم (تلوين، ورقة اليوم) → احسبي → الجواب؛
/// وبطاقة «حالتي اليوم»؛ والإعدادات (التصدير والاستيراد، الحذف)؛ والمستكشف؛ ومنتقي التاريخ.
void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  const settings = AppSettings(manualFajrMinutes: 270, manualMaghribMinutes: 1110);
  final time = FiqhTime(clockFromSettings(settings));
  final today = time.fiqhDayOf(DateTime.now());
  DateTime day(int ago) => today.subtract(Duration(days: ago));

  StoredState mubtadia({List<BloodDay> marks = const []}) => StoredState(
        profile: FiqhProfile(
          habit: const HabitState(type: WomanType.mub, origin: HabitOrigin.declared),
          birth: Tri.known(DateTime(1996, 1, 1)),
          ramadan: [(DateTime(2030, 1, 1), DateTime(2030, 1, 30))],
        ),
        settled: const {'womanType', 'birthDate'},
        settings: settings,
        marks: marks,
      );

  StoredState vw({int anchorDaysAgo = 0, List<BloodDay> marks = const []}) => StoredState(
        profile: FiqhProfile(
          habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(anchorDaysAgo)), count: 7, origin: HabitOrigin.declared),
          birth: Tri.known(DateTime(1996, 1, 1)),
          ramadan: [(DateTime(2030, 1, 1), DateTime(2030, 1, 30))],
        ),
        settled: const {'womanType', 'habitStart', 'habitCount', 'birthDate', 'lastBloodEnd'},
        settings: settings,
        marks: marks,
      );

  Future<MemoryFiqhStore> pump(WidgetTester tester, StoredState initial, {Widget? home}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryFiqhStore(initial);
    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: home == null ? const YthrnApp() : MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: home)),
    ));
    await tester.pumpAndSettle();
    return store;
  }

  /// خلية يوم في شبكة الشهر بتسميتها الدلالية.
  Finder cell(DateTime d) {
    final h = HijriDate.fromDate(d);
    return find.bySemanticsLabel(RegExp('^${h.day} ${h.monthName}'));
  }

  testWidgets('أول فتح: شاشة «اسألي» ببطاقاتها، بلا تهيئة ولا بطاقة حالة', (tester) async {
    await pump(tester, const StoredState(settings: settings));
    expect(find.text('ماذا تريدين أن تعرفي؟'), findsOneWidget);
    expect(find.text('نزل دم، هل هو حيض؟'), findsOneWidget);
    expect(find.text('ما عليّ من قضاء؟'), findsOneWidget);
    expect(find.text('التهيئة'), findsNothing);
    expect(find.textContaining('حالتي اليوم'), findsNothing);
  });

  testWidgets('ذات العادة في وقتها: «نزل دم» → تلوين اليوم بالنقر → احسبي → حيض بلا سؤال', (tester) async {
    final handle = tester.ensureSemantics();
    final store = await pump(tester, vw());
    await tester.tap(find.text('نزل دم، هل هو حيض؟'));
    await tester.pumpAndSettle();
    expect(find.text('احسبي'), findsOneWidget);
    await tester.tap(cell(today));
    await tester.pumpAndSettle();
    expect(store.state.marks.map((m) => m.day), [today]);
    await tester.tap(find.text('احسبي'));
    await tester.pumpAndSettle();
    expect(find.text('هذا الدم حيض؛ اتركي الصلاة والصوم حتى ينقطع'), findsOneWidget);
    expect(find.text('ماذا لو؟'), findsOneWidget);
    expect(find.text('لماذا؟'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('مبتدئة: سبعة أيام بصفات الحيض → سؤال الاستبراء ثم «الأيام التي لوّنتِها حيض» بلا ساعة', (tester) async {
    final marks = [for (var i = 8; i >= 2; i--) BloodDay(day(i), props: i == 8 ? BloodProps.wajid : null)];
    await pump(tester, mubtadia(marks: marks));
    await tester.tap(find.text('نزل دم، هل هو حيض؟'));
    await tester.pumpAndSettle();
    // انقطع قبل العشرة: يُسأل عن احتمال بقاء الدم داخلًا (H6-01) لا عن الساعة.
    await tester.tap(find.textContaining('احسبي'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text(QuestionCatalog.innerContinuity.text), findsOneWidget);
    await tester.tap(find.text('لا'));
    await tester.pumpAndSettle();
    expect(find.text('الأيام التي لوّنتِها حيض'), findsOneWidget);
  });

  testWidgets('مبتدئة بدم جارٍ بلا صفات: الجواب معلَّق على سؤال الصفات، و«ماذا لو؟» يفتح', (tester) async {
    final store = await pump(tester, mubtadia(marks: [BloodDay(day(1)), BloodDay(day(0))]));
    expect(find.textContaining('حالتي اليوم'), findsOneWidget);
    await tester.tap(find.text('نزل دم، هل هو حيض؟'));
    await tester.pumpAndSettle();
    expect(find.textContaining('اجمعي بين أعمال المستحاضة'), findsOneWidget);
    expect(find.text('سؤال يحتاج جوابك'), findsOneWidget);
    await tester.tap(find.text('ماذا لو؟'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatIfScreen), findsOneWidget);
    expect(find.textContaining('لو: نعم: أسود'), findsOneWidget);
    expect(store.state.events, isEmpty);
  });

  testWidgets('ورقة اليوم: نقرة على يوم ملوَّن تفتحها، واختيار الصفات يُحفظ، و«ليس يوم دم» يحذفه', (tester) async {
    final handle = tester.ensureSemantics();
    final store = await pump(tester, mubtadia(marks: [BloodDay(day(0))]));
    await tester.tap(find.text('التقويم'));
    await tester.pumpAndSettle();
    await tester.tap(cell(today));
    await tester.pumpAndSettle();
    expect(find.text('صفات الدم في هذا اليوم'), findsOneWidget);
    expect(find.text('متى بدأ الدم؟'), findsOneWidget);
    await tester.tap(find.text('أسود أو أحمر'));
    await tester.pumpAndSettle();
    expect(store.state.marks.single.props, BloodProps.wajid);
    await tester.tap(find.text('في الليل').first);
    await tester.pumpAndSettle();
    expect(store.state.marks.single.startPart, DayPart.night);
    await tester.tap(find.text('ليس يوم دم'));
    await tester.pumpAndSettle();
    expect(store.state.marks, isEmpty);
    handle.dispose();
  });

  testWidgets('«حالتي اليوم»: «انقطع الدم اليوم» يسجّل الانقطاع الآن على يوم اليوم', (tester) async {
    final store = await pump(tester, vw(anchorDaysAgo: 4, marks: [for (var i = 4; i >= 0; i--) BloodDay(day(i))]));
    expect(find.text('حالتي اليوم: حيض'), findsOneWidget);
    await tester.tap(find.text('انقطع الدم اليوم'));
    await tester.pumpAndSettle();
    expect(store.state.marks.last.stopAt, isNotNull);
    expect(find.text('نزل الدم اليوم'), findsOneWidget);
  });

  testWidgets('«نزل الدم اليوم» يلوّن اليوم من شاشة اسألي', (tester) async {
    final store = await pump(tester, vw(marks: [BloodDay(day(40)), BloodDay(day(39))]));
    await tester.tap(find.text('نزل الدم اليوم'));
    await tester.pumpAndSettle();
    expect(store.state.marks.map((m) => m.day), contains(today));
    expect(find.text('انقطع الدم اليوم'), findsOneWidget);
  });

  testWidgets('الاستحاضة: البطاقة تعرض «اختبري القطنة الآن» وتسجّل النتيجة', (tester) async {
    final store = await pump(tester, mubtadia(marks: [for (var i = 12; i >= 0; i--) BloodDay(day(i), props: i == 12 ? BloodProps.faqid : null)]));
    await tester.tap(find.text('استحاضة: ماذا أفعل قبل الصلاة؟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اختبري القطنة الآن'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خرجت ملوثة ولو بصفرة'));
    await tester.pumpAndSettle();
    expect(store.state.events.map((e) => e.event).whereType<KursufTest>(), isNotEmpty);
  });

  testWidgets('المستكشف يشغّل الحالة النموذجية ويعرض حالات الأيام', (tester) async {
    await pump(tester, mubtadia(), home: const ExplorerScreen());
    await tester.tap(find.text('تشغيل'));
    await tester.pumpAndSettle();
    expect(find.textContaining('G-X-001 —'), findsOneWidget);
    expect(find.text('1: HAYD'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('الإعدادات: التصدير يعرض النسخة بأيام الدم والاستيراد يستبدل البيانات', (tester) async {
    final store = await pump(tester, vw(marks: [BloodDay(day(3))]));
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تصدير'));
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(text, contains('"format": "ythrn-backup"'));
    expect(text, contains('"marks"'));
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();

    final imported = mubtadia(marks: [BloodDay(day(10)), BloodDay(day(9))]);
    await tester.tap(find.text('استيراد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, Backup.encode(imported));
    await tester.tap(find.widgetWithText(FilledButton, 'استيراد'));
    await tester.pumpAndSettle();
    expect(find.text('استبدال البيانات الحالية؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'استيراد'));
    await tester.pumpAndSettle();
    expect(store.state.marks.length, 2);
    expect(store.state.profile.habit.type, WomanType.mub);
  });

  testWidgets('الإعدادات: حذف كل البيانات يعيد إلى «اسألي» بلا بطاقة حالة ويُبقي المواقيت', (tester) async {
    final store = await pump(tester, vw(marks: [BloodDay(day(0))]));
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف كل البيانات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(store.state.settings.manualFajrMinutes, 270);
    await tester.tap(find.text('اسألي'));
    await tester.pumpAndSettle();
    expect(find.text('ماذا تريدين أن تعرفي؟'), findsOneWidget);
    expect(find.textContaining('حالتي اليوم'), findsNothing);
  });

  testWidgets('منتقي التاريخ: الهجري يعيد اليوم الميلادي الموافق والتبديل يحفظ اليوم', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => picked = await pickDate(ctx, initial: DateTime(2025, 3, 1), first: DateTime(2000), last: DateTime(2026)),
          child: const Text('افتحي'),
        ),
      ),
    ));
    await tester.tap(find.text('افتحي'));
    await tester.pumpAndSettle();
    expect(find.text('رمضان'), findsOneWidget);
    await tester.tap(find.text('ميلادي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('هجري'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2025, 3, 1));
  });
}
