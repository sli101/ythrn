import '../engine/hayd_engine.dart';
import '../engine/nifas_engine.dart';
import '../engine/segments.dart';
import '../model/day_state.dart';
import '../model/events.dart';
import '../model/habit_state.dart';
import '../model/tri.dart';
import '../model/woman_type.dart';
import '../time/fiqh_time.dart';
import 'catalog.dart';
import 'question.dart';
import 'session.dart';

/// آلة الأسئلة (`docs/SPEC.md` §١٠، `PLAN.md` §٢.٣).
///
/// `next(session)` تقيّم المحرك وتستخرج سؤالًا واحدًا: نوع العادة إن لم يُصرَّح
/// به، ثم آخر انتهاء إن لزم لأقل الطهر، ثم المدخل المعلَّق في حكم اليوم، ثم
/// ما يرفع احتياط اليوم بمعلومة، ثم الميلاد. لا يُسأل عن شيء لا يغيّر حكمًا:
/// لا صفات لذات الوقت في وقتها (H5-05)، ولا أقارب إلا عند التجاوز بلا تمييز.
///
/// لكل سؤال مخرجان غير الجواب: «لا أفهم» يفتح سلّم مشاهدة أو يعرض شرحًا،
/// و«لا أتذكر» يطبّق المسار المنصوص في §٦. `apply` تحوّل الجواب إلى حدث أو
/// تعديل في الملف وتعيد جلسة جديدة.
class QuestionMachine {
  QuestionMachine(this.time, {FiqhEngine? engine}) : engine = engine ?? FiqhEngine(time);

  final FiqhTime time;
  final FiqhEngine engine;

  /// العدد المختار عند العجز عن الاختيار (H7-04: «الأفضل سبعة»؛ الافتراض ٤٥).
  static const defaultChosenCount = 7;

  EngineResult evaluate(QuestionSession s) => engine.evaluateProfile(s.profile, s.events, s.now);

  // ================================================================ السؤال التالي

  Question? next(QuestionSession s) {
    final ladder = s.ladder;
    if (ladder != null) {
      final step = _ladderStep(ladder);
      if (step != null) return step.copyWith(explained: s.explained.contains(step.key));
      // سلّم مكتمل بلا طيّ (لا يقع إلا بجلسة مركّبة يدويًّا): يُهمل.
      return next(s.copyWith(clearLadder: true));
    }
    final r = evaluate(s);
    final q = _onboarding(s) ?? _lastBloodEnd(s) ?? _profileFollowUps(s) ?? _pendingToday(s, r) ?? _liftToday(s, r) ?? _birth(s);
    if (q == null) return null;
    return q.copyWith(explained: s.explained.contains(q.key));
  }

  /// أول استخدام: نوع العادة مباشرة (اختصار)، ثم معطياتها، ثم ذاكرة الناسية.
  Question? _onboarding(QuestionSession s) {
    final h = s.profile.habit;
    if (h.origin == HabitOrigin.derived && h.history.isEmpty && h.type == WomanType.mub && !s.isSettled('womanType')) {
      return QuestionCatalog.womanType;
    }
    // ناسية العدد حافظة الوقت تحتاج وقتها أيضًا (م٢٢٣).
    if ((h.type.hasTime || h.type == WomanType.nasC) && h.anchorDate == null && !s.isSettled('habitStart')) return QuestionCatalog.habitStart;
    if (h.type.hasCount && h.count == null && !s.isSettled('habitCount')) return QuestionCatalog.habitCount;
    // ناسية الوقت حافظة العدد: العدد بعادتها (م٢٢٤).
    if (h.type == WomanType.nasT && h.count == null && !s.isSettled('habitCount')) return QuestionCatalog.habitCount;
    final forgotCount = h.type == WomanType.nasC || h.type == WomanType.nasB;
    if (forgotCount && h.memory?.countMin == null && !s.isSettled('nasiyaCountMin')) return QuestionCatalog.nasiyaCountMin;
    if (forgotCount && h.memory?.countMax == null && !s.isSettled('nasiyaCountMax')) return QuestionCatalog.nasiyaCountMax;
    final forgotTime = h.type == WomanType.nasT || h.type == WomanType.nasB;
    if (forgotTime &&
        s.profile.nasiyaHalfMonth == null &&
        s.profile.timeWindow == null &&
        (h.memory?.knownDays.isEmpty ?? true) &&
        !s.isSettled('nasiyaHalfMonth')) {
      return QuestionCatalog.nasiyaHalfMonth;
    }
    return null;
  }

  /// متابعة مدخل أُجيب عنه ويحتاج تتمة: شرطا الرجوع إلى الأقارب بعد عددها (H7-07).
  /// المحرك يبني على تحقق الشرطين ما لم يُعلم خلافه، فلا يبقى مدخل معلَّق يطلبهما.
  Question? _profileFollowUps(QuestionSession s) {
    final p = s.profile;
    if (p.kinCount.isKnown && !p.kinConditionsMet.isKnown && !s.isSettled('kinConditions')) return QuestionCatalog.kinConditions;
    return null;
  }

  /// آخر انتهاء قبل التنصيب (T-04): لغير المبتدئة، إذا بدأ دم ولا تاريخ محكوم به،
  /// ولم يكن في وقت عادتها (فإن كان فحيض بالرؤية والفاصل ظاهر؛ G-UNK-012).
  Question? _lastBloodEnd(QuestionSession s) {
    final p = s.profile;
    if (p.lastBloodEnd.isKnown || s.isSettled('lastBloodEnd')) return null;
    final h = p.habit;
    if (h.type == WomanType.mub || h.history.isNotEmpty) return null;
    final first = _firstBloodStart(s.events);
    if (first == null) return null;
    // بعد ولادة أو سقط الدم نفاس لا حيض، فلا حاجة إلى آخر انتهاء (أقل الطهر شأن الحيض).
    if (s.events.any((e) => (e is Birth || e is Miscarriage) && !e.at.isAfter(first.at))) return null;
    final pos = engine.hayd.habitWindowPosition(h, first.at);
    if (pos == HabitWindowPosition.inside || pos == HabitWindowPosition.earlyWithinCustom) return null;
    return QuestionCatalog.lastBloodEnd;
  }

  /// المدخل الذي يطلبه المحرك صراحة لحكم اليوم (`StateInterval.pendingInput`).
  Question? _pendingToday(QuestionSession s, EngineResult r) {
    final today = _today(r, s.now);
    final input = today?.pendingInput;
    if (today == null || input == null) return null;
    switch (input) {
      case 'kursufTest':
        // قبل القطنة: «هل تحتملين بقاءه في الداخل؟» (H6-01؛ SPEC §٥.٣ خطوة ٣).
        final stop = today.from;
        if (!_has<InnerContinuity>(s.events, stop) && !s.isSettled(Question.keyFor('innerContinuity', stop))) {
          return QuestionCatalog.byId('innerContinuity', at: stop);
        }
        return _unlessSettled(s, 'kursufTest', stop);
      case 'chosenCount':
        // الأقارب بشرطيهما قبل العدد المختار (H7-07 ثم H7-04).
        final p = s.profile;
        if (!p.kinCount.isKnown && !s.isSettled('kinCount')) return QuestionCatalog.kinCount;
        if (p.kinCount.isKnown && !p.kinConditionsMet.isKnown && !s.isSettled('kinConditions')) return QuestionCatalog.kinConditions;
        return _unlessSettled(s, 'chosenCount', null);
      case 'istihadhaTest':
        // إن كانت الاستحاضة بالتردد بعد العادة (H6-03) فسؤال التجاوز أولًا؛ جوابه قد يعيدها حيضًا.
        return _willExceedTen(s, r, today) ?? _unlessSettled(s, 'istihadhaTest', today.from);
      case 'miscarriageStage':
        final m = s.events.whereType<Miscarriage>().where((m) => m.stage == null && !m.at.isAfter(s.now)).lastOrNull;
        if (m == null) return null;
        return _unlessSettled(s, 'miscarriageStage', m.at);
      case 'virginityTest':
        return _unlessSettled(s, 'virginityTest', today.from);
      default:
        return null;
    }
  }

  /// حكم اليوم احتياطي أو ظاهري يمكن رفعه بمعلومة: بالأثر على اليوم أولًا.
  Question? _liftToday(QuestionSession s, EngineResult r) {
    final today = _today(r, s.now);
    if (today == null) return null;
    final p = s.profile;
    final seg = _segmentAt(r.segments, s.now);

    // ١) تقدم على العادة بأزيد من التعجيل العرفي: هل يصدق التعجيل؟ (H5-01).
    if (seg != null && today.trace.any((t) => t.id == 'H5-03' && t.note == HaydEngine.noteEarlyBeyondCustom)) {
      if (!_has<IsEarlyHabit>(s.events, seg.start) && !s.isSettled(Question.keyFor('isEarlyHabit', seg.start))) {
        return QuestionCatalog.byId('isEarlyHabit', at: seg.start);
      }
    }

    // ٢) جمع احتياطي عند البدء: الصفات ثم العلم بالاستمرار (H5-02، H3-06).
    if (seg != null && today.state == DayState.jam3M && today.trace.any((t) => t.id == 'H5-02b')) {
      if (seg.propsAt(seg.start) == null && !s.isSettled(Question.keyFor('bloodProps', seg.start))) {
        return QuestionCatalog.byId('bloodProps', at: seg.start);
      }
      if (!_hasExpectation(s.events, ExpectationKind.willLastThreeDays, seg.start) &&
          !s.isSettled(Question.keyFor('willLastThreeDays', seg.start))) {
        return QuestionCatalog.byId('willLastThreeDays', at: seg.start);
      }
    }

    // ٣) قطنة نظيفة قبل العشرة بلا اطمئنان بالعود: هل تعرفين أنه يعود؟ (H6-02).
    if (today.state == DayState.tahir && today.trace.any((t) => t.id == 'H6-02' && t.note == HaydEngine.noteNoReturnConfidence)) {
      final stop = today.from;
      final prev = _segmentEndingAt(r.segments, stop);
      if (prev != null &&
          s.now.isBefore(time.tenDaysEndAt(prev.start).value) &&
          !_hasExpectation(s.events, ExpectationKind.willReturnBeforeTen, stop, after: true) &&
          !s.isSettled(Question.keyFor('willReturnBeforeTen', stop))) {
        return QuestionCatalog.byId('willReturnBeforeTen', at: stop);
      }
    }

    // ٤) بعد العادة والقطنة ملوثة والتردد: هل تعرفين أنه سيتجاوز العشرة؟ (H6-03).
    final exceed = _willExceedTen(s, r, today);
    if (exceed != null) return exceed;

    // ٥) الكثيرة: صبيب أم متقطع (I2-04).
    if (today.state == DayState.istK) {
      final test = s.events.whereType<IstihadhaTest>().where((t) => !t.at.isAfter(s.now)).lastOrNull;
      if (test != null && test.flow == null && !s.isSettled(Question.keyFor('istihadhaFlow', test.at))) {
        return QuestionCatalog.byId('istihadhaFlow', at: test.at);
      }
    }

    // ٦) السقط المتخلق: ولوج الروح لتنبيه غسل مس الميت (M-06).
    for (final m in s.events.whereType<Miscarriage>()) {
      if (m.countsAsBirth && !m.ensouled.isKnown && !s.isSettled(Question.keyFor('ensouled', m.at))) {
        return QuestionCatalog.byId('ensouled', at: m.at);
      }
    }

    // ٧) الحامل ذات الوقت بعد عشرين يومًا من أول عادتها بصفات الحيض (H1-03b).
    final h = p.habit;
    if (seg != null &&
        today.state == DayState.hayd &&
        h.type.hasTime &&
        h.anchorDate != null &&
        !p.pregnant.isKnown &&
        !s.isSettled('pregnant') &&
        seg.propsAt(seg.start) == BloodProps.wajid) {
      final diff = FiqhTime.daysBetween(h.anchorDate!, seg.start);
      final sinceHabit = diff - 30 * (diff / 30).floor();
      if (sinceHabit >= 20) return QuestionCatalog.pregnant;
    }

    // ٨) نقاء ليلًا: هل الغد من رمضان أو قضائه؟ (H9-15).
    if (p.ramadan.isEmpty && !today.state.isBloodRuling) {
      final stop = s.events.whereType<BloodStop>().where((e) => !e.at.isAfter(s.now)).lastOrNull;
      if (stop != null && !time.isDaytime(stop.at)) {
        final nextFajr = time.clock.fajr(time.fiqhDayOf(stop.at).add(const Duration(days: 1)));
        if (s.now.isBefore(nextFajr) &&
            !_has<RamadanNote>(s.events, stop.at) &&
            !s.isSettled(Question.keyFor('ramadanTomorrow', stop.at))) {
          return QuestionCatalog.byId('ramadanTomorrow', at: stop.at);
        }
      }
    }
    return null;
  }

  /// سؤال التجاوز لفترة الاستحاضة بالتردد (H6-03)، بلحظة بدء التردد (أول فترة
  /// متصلة تحمل أثره؛ تقسيم الفترة باختبارات الاستحاضة لا يغيّر اللحظة).
  Question? _willExceedTen(QuestionSession s, EngineResult r, StateInterval today) {
    bool hesitant(StateInterval iv) => iv.state.isIstihadha && iv.trace.any((t) => t.id == 'H6-03' && t.note == HaydEngine.noteHesitation);
    if (!hesitant(today)) return null;
    final sorted = [...r.intervals]..sort((a, b) => a.from.compareTo(b.from));
    DateTime? runStart;
    DateTime? prevEnd;
    for (final iv in sorted) {
      if (hesitant(iv)) {
        if (runStart == null || prevEnd == null || iv.from.isAfter(prevEnd)) runStart = iv.from;
      } else {
        runStart = null;
      }
      prevEnd = iv.to;
      if (iv.from == today.from) break;
    }
    final at = runStart ?? today.from;
    if (_hasExpectation(s.events, ExpectationKind.willExceedTen, at) || s.isSettled(Question.keyFor('willExceedTen', at))) return null;
    return QuestionCatalog.byId('willExceedTen', at: at);
  }

  /// الميلاد آخرًا: لا يغيّر حكم اليوم إلا عند حافتي التسع والستين.
  Question? _birth(QuestionSession s) {
    final p = s.profile;
    if (p.birth.isKnown || p.approxAgeYears.isKnown || s.isSettled('birthDate')) return null;
    return QuestionCatalog.birthDate;
  }

  // ================================================================ تطبيق الجواب

  QuestionSession apply(QuestionSession s, Question q, Reply reply) {
    final ladder = s.ladder;
    if (ladder != null && q.isLadderStep) return _applyLadderStep(s, ladder, q, reply);
    switch (reply) {
      case ValueReply(:final value):
        return _applyValue(s, q, value).settle(q.key);
      case DontUnderstandReply():
        if (q.hasLadder) return s.copyWith(ladder: Ladder(parent: q, kind: LadderKind.understand));
        return s.copyWith(explained: {...s.explained, q.key});
      case DontRememberReply():
        return _applyDontRemember(s, q);
      case SkipReply():
        return s.settle(q.key);
    }
  }

  QuestionSession _applyValue(QuestionSession s, Question q, Object v) {
    final p = s.profile;
    final h = p.habit;
    final at = q.at;
    switch (q.id) {
      // ---- الملف الشخصي
      case 'womanType':
        return s.copyWith(profile: p.copyWith(habit: h.copyWith(type: WomanType.fromCode(v as String), origin: HabitOrigin.declared)));
      case 'habitStart':
        final day = _dateOnly(v as DateTime);
        return s.copyWith(profile: p.copyWith(habit: h.copyWith(anchor: HabitAnchor.start, anchorDate: time.clock.fajr(day), origin: HabitOrigin.declared)));
      case 'habitCount':
        return s.copyWith(profile: p.copyWith(habit: h.copyWith(count: v as int, origin: HabitOrigin.declared)));
      case 'nasiyaCountMin':
        return s.copyWith(profile: p.copyWith(habit: h.copyWith(memory: _memory(h.memory, countMin: v as int))));
      case 'nasiyaCountMax':
        return s.copyWith(profile: p.copyWith(habit: h.copyWith(memory: _memory(h.memory, countMax: v as int))));
      case 'nasiyaHalfMonth':
        return s.copyWith(profile: p.copyWith(nasiyaHalfMonth: v == 'first' ? 1 : 2));
      case 'birthDate':
        return s.copyWith(profile: p.copyWith(birth: Tri.known(_dateOnly(v as DateTime))));
      case 'lastBloodEnd':
        // اليوم المدخل: انتهاؤه عند مغربه (نهاية النهار الفقهي، T-01).
        return s.copyWith(profile: p.copyWith(lastBloodEnd: Tri.known(time.clock.maghrib(_dateOnly(v as DateTime)))));
      case 'kinCount':
        return s.copyWith(profile: p.copyWith(kinCount: Tri.known(v as int)));
      case 'kinConditions':
        // السؤال عن العلم بالمخالفة؛ الشرط عدمه (م٢٢٢).
        return s.copyWith(profile: p.copyWith(kinConditionsMet: Tri.known(!(v as bool))));
      case 'chosenCount':
        return s.copyWith(profile: p.copyWith(chosenCount: Tri.known(v as int)));
      case 'pregnant':
        return s.copyWith(profile: p.copyWith(pregnant: Tri.known(v as bool)));

      // ---- بدء الدم: الجواب يتعلق بلحظة البدء
      case 'isEarlyHabit':
        return s.addEvent(IsEarlyHabit(at!, Tri.known(v as bool)));
      case 'bloodProps':
        return s.addEvent(PropsChange(at!, v == 'wajid' ? BloodProps.wajid : BloodProps.faqid));
      case 'willLastThreeDays':
        return s.addEvent(Expectation(at!, ExpectationKind.willLastThreeDays, Tri.known(v as bool)));

      // ---- الانقطاع
      case 'innerContinuity':
        return s.addEvent(InnerContinuity(at!, Tri.known(v as bool)));
      case 'kursufTest':
        return s.addEvent(KursufTest(_actionTime(s, at), v == 'clean' ? KursufResult.clean : KursufResult.stained));
      case 'willReturnBeforeTen':
        // يُسجَّل بعد القطنة التي أثارته (المحرك يبحث عنه بعدها، H6-02).
        return s.addEvent(Expectation(_actionTime(s, at), ExpectationKind.willReturnBeforeTen, Tri.known(v as bool)));
      case 'willExceedTen':
        return s.addEvent(Expectation(at!, ExpectationKind.willExceedTen, Tri.known(v == 'exceed')));

      // ---- الاستحاضة
      case 'istihadhaTest':
        return s.addEvent(IstihadhaTest(_actionTime(s, at), IstihadhaLevel.values.byName(v as String)));
      case 'istihadhaFlow':
        final test = s.events.whereType<IstihadhaTest>().where((t) => !t.at.isAfter(s.now)).lastOrNull;
        if (test == null) return s;
        return s.addEvent(IstihadhaTest(_actionTime(s, test.at), test.level, flow: IstihadhaFlow.values.byName(v as String)));

      // ---- النفاس والسقط: تعديل حدث السقط نفسه
      case 'miscarriageStage':
        return _replaceMiscarriage(s, at!, (m) => Miscarriage(m.at, stage: MiscarriageStage.values.byName(v as String), ensouled: m.ensouled));
      case 'ensouled':
        return _replaceMiscarriage(s, at!, (m) => Miscarriage(m.at, stage: m.stage, ensouled: Tri.known(v as bool)));

      // ---- تمييز الدم
      case 'virginityTest':
        return s.addEvent(VirginityTest(_actionTime(s, at), v == 'ringed' ? VirginityTestResult.ringed : VirginityTestResult.soaked));

      // ---- الوظائف
      case 'ramadanTomorrow':
        return s.addEvent(RamadanNote(at!, isRamadan: v as bool));
      default:
        throw ArgumentError('لا تطبيق لجواب السؤال ${q.id}');
    }
  }

  /// «لا أتذكر»: المسار المنصوص لكل مدخل (`SPEC` §٦).
  QuestionSession _applyDontRemember(QuestionSession s, Question q) {
    final p = s.profile;
    final h = p.habit;
    final at = q.at;
    switch (q.id) {
      case 'womanType':
        // نسيت → ناسية بصورها (H4-05).
        return s.copyWith(ladder: Ladder(parent: q, kind: LadderKind.remember));
      case 'habitStart':
        // ذات وقت نسيت وقتها → ناسية الوقت؛ وإن كان عددها محفوظًا بقي (م٢٢٤).
        return s.settle(q.key).copyWith(profile: p.copyWith(habit: h.copyWith(type: WomanType.nasT, clearAnchorDate: true, origin: HabitOrigin.declared)));
      case 'habitCount':
        // نسيت العدد: مع حفظ الوقت ناسية العدد، ومع نسيانه ناسيتهما (H4-05).
        final type = h.type == WomanType.nasT ? WomanType.nasB : WomanType.nasC;
        return s.settle(q.key).copyWith(profile: p.copyWith(habit: h.copyWith(type: type, clearCount: true, origin: HabitOrigin.declared)));
      case 'birthDate':
      case 'lastBloodEnd':
        return s.copyWith(ladder: Ladder(parent: q, kind: LadderKind.remember));
      case 'kinCount':
        // لا أقارب → اختيار العدد (H7-04، م٢٢٢).
        return s.settle(q.key).copyWith(profile: p.copyWith(kinCount: const Tri.unknown(UnknownKind.dontRemember)));
      case 'kinConditions':
        // عدم العلم بالمخالفة يحقق الشرط (م٢٢٢).
        return s.settle(q.key).copyWith(profile: p.copyWith(kinConditionsMet: const Tri.unknown(UnknownKind.dontRemember)));
      case 'chosenCount':
        return s.settle(q.key).copyWith(profile: p.copyWith(chosenCount: const Tri.known(defaultChosenCount)));
      case 'isEarlyHabit':
        return s.settle(q.key).addEvent(IsEarlyHabit(at!, const Tri.unknown(UnknownKind.dontRemember)));
      case 'willLastThreeDays':
        // «لا أعلم» = احتمال الاستمرار → الجمع (H3-06).
        return s.settle(q.key).addEvent(Expectation(at!, ExpectationKind.willLastThreeDays, const Tri.unknown(UnknownKind.dontRemember)));
      case 'innerContinuity':
        // الشك في البقاء = احتماله → الاستبراء (H6-01).
        return s.settle(q.key).addEvent(InnerContinuity(at!, const Tri.unknown(UnknownKind.dontRemember)));
      case 'willReturnBeforeTen':
        // ظن فقط أو لا تدري → طهر (ج م٦٠٨).
        return s.settle(q.key).addEvent(Expectation(_actionTime(s, at), ExpectationKind.willReturnBeforeTen, const Tri.unknown(UnknownKind.dontRemember)));
      case 'willExceedTen':
        return s.settle(q.key).addEvent(Expectation(at!, ExpectationKind.willExceedTen, const Tri.unknown(UnknownKind.dontRemember)));
      case 'kursufTest':
      case 'istihadhaTest':
        // «لم يُجرَ» → يبقى معلَّقًا ويُعاد الطلب (H6-01، I2-01).
        return s;
      case 'ramadanTomorrow':
        // يُعرض التنبيه احتياطًا؛ لا ضرر في الغسل (H9-15).
        return s.settle(q.key).addEvent(RamadanNote(at!, isRamadan: true));
      case 'miscarriageStage':
        // «لا أعرف» → يبقى معلَّقًا مع التوجيه إلى من يعرف (SPEC §٦).
        return s.settle(q.key);
      default:
        // الصفات (تُعامل فاقدة)، نمط الكثيرة (صبيب)، الحمل، ذاكرة الناسية،
        // ولوج الروح، البكارة (الطهارة): الافتراضي المنصوص قائم في المحرك.
        return s.settle(q.key);
    }
  }

  // ================================================================ السلالم

  Question? _ladderStep(Ladder l) {
    final a = l.answers;
    final at = l.parent.at;
    Question step(String id) => QuestionCatalog.byId(id, at: at);
    bool missing(String id) => !a.containsKey(id);
    switch ((l.parent.id, l.kind)) {
      case ('womanType', LadderKind.understand):
        if (missing('firstTime')) return step('firstTime');
        if (a['firstTime'] == true) return null;
        if (missing('sameCount')) return step('sameCount');
        if (missing('sameTime')) return step('sameTime');
        return null;
      case ('womanType', LadderKind.remember):
        return missing('nasiyaForgot') ? step('nasiyaForgot') : null;
      case ('bloodProps', LadderKind.understand):
        // تكفي صفة واحدة (H0-05): أول «نعم» تُنهي السلّم.
        if (missing('propsDark')) return step('propsDark');
        if (a['propsDark'] == 'dark') return null;
        if (missing('propsWarm')) return step('propsWarm');
        if (a['propsWarm'] == true) return null;
        if (missing('propsThrust')) return step('propsThrust');
        return null;
      case ('willLastThreeDays', LadderKind.understand):
        return missing('bloodUsuallyLasts') ? step('bloodUsuallyLasts') : null;
      case ('innerContinuity', LadderKind.understand):
        return missing('innerTrace') ? step('innerTrace') : null;
      case ('willReturnBeforeTen', LadderKind.understand):
        return missing('bloodUsuallyReturns') ? step('bloodUsuallyReturns') : null;
      case ('miscarriageStage', LadderKind.understand):
        return missing('humanForm') ? step('humanForm') : null;
      case ('ensouled', LadderKind.understand):
        return missing('fourMonths') ? step('fourMonths') : null;
      case ('birthDate', _):
        return missing('approxAge') ? step('approxAge') : null;
      case ('lastBloodEnd', LadderKind.understand):
        return missing('lastGhuslDate') ? step('lastGhuslDate') : null;
      case ('lastBloodEnd', LadderKind.remember):
        if (missing('moreThanTenDays')) return step('moreThanTenDays');
        if (a['moreThanTenDays'] == true) return null;
        if (missing('daysSinceLastBlood')) return step('daysSinceLastBlood');
        return null;
      default:
        return null;
    }
  }

  QuestionSession _applyLadderStep(QuestionSession s, Ladder l, Question q, Reply reply) {
    switch (reply) {
      case ValueReply(:final value):
        final next = l.withAnswer(q.id, value);
        if (_ladderStep(next) != null) return s.copyWith(ladder: next);
        return _fold(s.copyWith(clearLadder: true), next);
      case DontUnderstandReply():
        return s.copyWith(explained: {...s.explained, q.key});
      case DontRememberReply():
        // في سلّم المشاهدة: جهل بالموضوع → مسار الأصل؛ في سلّم التذكر: تسوية الأصل.
        final cleared = s.copyWith(clearLadder: true);
        if (l.kind == LadderKind.understand && l.parent.id != 'birthDate' && l.parent.id != 'lastBloodEnd') {
          return _applyDontRemember(cleared, l.parent);
        }
        return cleared.settle(l.parent.key);
      case SkipReply():
        return s.copyWith(clearLadder: true).settle(l.parent.key);
    }
  }

  /// طيّ أجوبة السلّم إلى جواب الأصل.
  QuestionSession _fold(QuestionSession s, Ladder l) {
    final a = l.answers;
    final parent = l.parent;
    QuestionSession value(Object v) => _applyValue(s, parent, v).settle(parent.key);
    switch ((parent.id, l.kind)) {
      case ('womanType', LadderKind.understand):
        if (a['firstTime'] == true) return value('MUB');
        final c = a['sameCount'] == true;
        final t = a['sameTime'] == true;
        return value(c && t ? 'VW' : c ? 'W' : t ? 'V' : 'MUD');
      case ('womanType', LadderKind.remember):
        final type = switch (a['nasiyaForgot']) { 'time' => WomanType.nasT, 'count' => WomanType.nasC, _ => WomanType.nasB };
        return s.settle(parent.key).copyWith(profile: s.profile.copyWith(habit: s.profile.habit.copyWith(type: type, origin: HabitOrigin.declared)));
      case ('bloodProps', _):
        final wajid = a['propsDark'] == 'dark' || a['propsWarm'] == true || a['propsThrust'] == true;
        return value(wajid ? 'wajid' : 'faqid');
      case ('willLastThreeDays', _):
        return value(a['bloodUsuallyLasts'] == true);
      case ('innerContinuity', _):
        return value(a['innerTrace'] == true);
      case ('willReturnBeforeTen', _):
        return value(a['bloodUsuallyReturns'] == true);
      case ('miscarriageStage', _):
        return value(a['humanForm'] == true ? 'formed' : 'mudgha');
      case ('ensouled', _):
        return value(a['fourMonths'] == true);
      case ('birthDate', _):
        final age = a['approxAge'] as int;
        return s.settle(parent.key).copyWith(profile: s.profile.copyWith(approxAgeYears: Tri.known(age.toDouble())));
      case ('lastBloodEnd', LadderKind.understand):
        return value(a['lastGhuslDate'] as DateTime);
      case ('lastBloodEnd', LadderKind.remember):
        if (a['moreThanTenDays'] == true) return s.settle(parent.key);
        final days = a['daysSinceLastBlood'] as int;
        final first = _firstBloodStart(s.events);
        if (first == null) return s.settle(parent.key);
        return s.settle(parent.key).copyWith(profile: s.profile.copyWith(lastBloodEnd: Tri.known(first.at.subtract(Duration(days: days)))));
      default:
        return s.settle(parent.key);
    }
  }

  // ================================================================ أدوات

  Question? _unlessSettled(QuestionSession s, String id, DateTime? at) =>
      s.isSettled(Question.keyFor(id, at)) ? null : QuestionCatalog.byId(id, at: at);

  /// الفترة التي تغطي الآن، وإلا الأخيرة.
  StateInterval? _today(EngineResult r, DateTime now) {
    final at = r.at(now);
    if (at != null) return at;
    StateInterval? last;
    for (final iv in r.intervals) {
      if (last == null || iv.from.isAfter(last.from)) last = iv;
    }
    return last;
  }

  /// المقطع الذي يحوي الآن، وإلا آخر مقطع بدأ قبله.
  BloodSegment? _segmentAt(List<BloodSegment> segments, DateTime now) {
    BloodSegment? found;
    for (final s in segments) {
      if (!s.start.isAfter(now) && (found == null || s.start.isAfter(found.start))) found = s;
    }
    return found;
  }

  BloodSegment? _segmentEndingAt(List<BloodSegment> segments, DateTime stop) {
    BloodSegment? found;
    for (final s in segments) {
      if (s.end != null && !s.end!.isAfter(stop) && (found == null || s.end!.isAfter(found.end!))) found = s;
    }
    return found;
  }

  BloodStart? _firstBloodStart(List<FiqhEvent> events) {
    BloodStart? first;
    for (final e in events) {
      if (e is BloodStart && (first == null || e.at.isBefore(first.at))) first = e;
    }
    return first;
  }

  static const _tolerance = Duration(days: 1);

  /// هل سُجّل حدث من النوع حول اللحظة (بتسامح يوم كما يبحث المحرك)؟
  bool _has<T extends FiqhEvent>(List<FiqhEvent> events, DateTime at) =>
      events.any((e) => e is T && e.at.difference(at).abs() <= _tolerance);

  bool _hasExpectation(List<FiqhEvent> events, ExpectationKind kind, DateTime at, {bool after = false}) => events.any((e) =>
      e is Expectation && e.kind == kind && (after ? !e.at.isBefore(at.subtract(_tolerance)) : e.at.difference(at).abs() <= _tolerance));

  /// لحظة فعلٍ يُجرى الآن (قطنة، اختبار): الآن إن كان بعد لحظة السؤال.
  DateTime _actionTime(QuestionSession s, DateTime? at) => at == null || s.now.isAfter(at) ? s.now : at;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static NasiyaMemory _memory(NasiyaMemory? m, {int? countMin, int? countMax}) => NasiyaMemory(
        countMin: countMin ?? m?.countMin,
        countMax: countMax ?? m?.countMax,
        knownDays: m?.knownDays ?? const [],
      );

  QuestionSession _replaceMiscarriage(QuestionSession s, DateTime at, Miscarriage Function(Miscarriage) f) {
    final events = [for (final e in s.events) if (e is Miscarriage && e.at == at) f(e) else e];
    return s.copyWith(events: events);
  }
}
