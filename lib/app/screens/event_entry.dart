import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/fiqh_store.dart';
import '../../fiqh/fiqh.dart';
import '../labels.dart';
import '../providers.dart';
import '../widgets/date_picker.dart';

/// اختيار لحظة الواقعة: الآن، أو وقت آخر (السجل حيّ: يُسجَّل الحدث ساعة وقوعه).
Future<DateTime?> pickMoment(BuildContext context, {required String title}) async {
  final now = DateTime.now();
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(leading: const Icon(Icons.bolt), title: const Text('الآن'), subtitle: Text(Labels.dateTime(now)), onTap: () => Navigator.pop(ctx, 'now')),
          ListTile(leading: const Icon(Icons.schedule), title: const Text('في وقت آخر'), onTap: () => Navigator.pop(ctx, 'pick')),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == 'now') return now;
  if (choice != 'pick' || !context.mounted) return null;
  return pickDateTime(context, initial: now);
}

/// تاريخ (هجري أو ميلادي) ثم وقت؛ لا مستقبل.
Future<DateTime?> pickDateTime(BuildContext context, {required DateTime initial}) async {
  final now = DateTime.now();
  final date = await pickDate(context, initial: initial, first: now.subtract(const Duration(days: 400)), last: now);
  if (date == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (t == null) return null;
  final at = DateTime(date.year, date.month, date.day, t.hour, t.minute);
  return at.isAfter(now) ? now : at;
}

/// تعديل وقت حدث مسجَّل (الحدث يُسجَّل ساعة وقوعه، T-06).
Future<void> editEventTime(BuildContext context, WidgetRef ref, StoredEvent e) async {
  final at = await pickDateTime(context, initial: e.event.at);
  if (at == null) return;
  final moved = FiqhCodec.decodeEvent({...FiqhCodec.encodeEvent(e.event), 'at': at.toIso8601String()});
  await ref.read(appStateProvider.notifier).updateEvent(StoredEvent(e.id, moved));
  ref.read(nowProvider.notifier).state = DateTime.now();
}

/// تسجيل صفات الدم الآن من شاشة اليوم: عبر سؤال الآلة إن كان هو التالي (ليُسوّى)،
/// وإلا حدث `PropsChange` مباشر.
Future<void> recordProps(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(QuestionCatalog.bloodProps.text, style: Theme.of(ctx).textTheme.titleMedium)),
          for (final o in QuestionCatalog.bloodProps.options) ListTile(leading: const Icon(Icons.water_drop_outlined), title: Text(o.label), onTap: () => Navigator.pop(ctx, o.value)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return;
  await _answerOrAdd(ref, 'bloodProps', choice, (now) => PropsChange(now, choice == 'wajid' ? BloodProps.wajid : BloodProps.faqid));
}

/// تسجيل نتيجة اختبار القطنة الآن من شاشة اليوم.
Future<void> recordKursuf(BuildContext context, WidgetRef ref) async {
  final q = QuestionCatalog.kursufTest;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(q.text, style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text(q.explanation ?? ''),
          ),
          for (final o in q.options) ListTile(leading: const Icon(Icons.science_outlined), title: Text(o.label), onTap: () => Navigator.pop(ctx, o.value)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return;
  await _answerOrAdd(ref, 'kursufTest', choice, (now) => KursufTest(now, choice == 'clean' ? KursufResult.clean : KursufResult.stained));
}

Future<void> _answerOrAdd(WidgetRef ref, String questionId, String value, FiqhEvent Function(DateTime now) build) async {
  final s = ref.read(sessionProvider);
  final q = ref.read(nextQuestionProvider);
  if (s != null && q != null && q.id == questionId) {
    await ref.read(appStateProvider.notifier).answer(s.copyWith(now: DateTime.now()), q, Reply.value(value));
  } else {
    await ref.read(appStateProvider.notifier).addEvent(build(DateTime.now()));
  }
  ref.read(nowProvider.notifier).state = DateTime.now();
}

Future<void> recordBirth(BuildContext context, WidgetRef ref) async {
  final at = await pickMoment(context, title: 'متى كانت الولادة؟');
  if (at == null) return;
  await ref.read(appStateProvider.notifier).addEvent(Birth(at));
  ref.read(nowProvider.notifier).state = DateTime.now();
}

Future<void> recordMiscarriage(BuildContext context, WidgetRef ref) async {
  final at = await pickMoment(context, title: 'متى كان السقط؟');
  if (at == null) return;
  // المرحلة تُسأل بعدُ عبر آلة الأسئلة (M-01).
  await ref.read(appStateProvider.notifier).addEvent(Miscarriage(at));
  ref.read(nowProvider.notifier).state = DateTime.now();
}

