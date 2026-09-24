// Data returned by the Masomo API (jarvis/jarvis/server.py). Parsing is lenient
// about missing optional fields so an older server never crashes the app.

class Me {
  Me({
    required this.id,
    required this.name,
    required this.phone,
    required this.level,
    required this.nativeLang,
    required this.country,
    required this.pro,
    required this.proUntil,
    required this.turnsLeftToday,
    required this.dailyLimit,
  });

  final int id;
  final String name;
  final String phone;
  final String level;
  final String nativeLang;
  final String country;
  final bool pro;
  final DateTime? proUntil;
  final int turnsLeftToday;
  final int dailyLimit;

  bool get needsProfile => name.trim().isEmpty;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as int,
    name: (j['name'] ?? '') as String,
    phone: (j['phone'] ?? '') as String,
    level: (j['level'] ?? 'A2') as String,
    nativeLang: (j['native_lang'] ?? 'sw') as String,
    country: (j['country'] ?? 'TZ') as String,
    pro: (j['pro'] ?? false) as bool,
    proUntil: j['pro_until'] == null ? null : DateTime.tryParse(j['pro_until'] as String),
    turnsLeftToday: (j['turns_left_today'] ?? 0) as int,
    dailyLimit: (j['daily_limit'] ?? 0) as int,
  );
}

class AuthStart {
  AuthStart({required this.phone, this.devCode});
  final String phone;
  final String? devCode;

  factory AuthStart.fromJson(Map<String, dynamic> j) =>
      AuthStart(phone: j['phone'] as String, devCode: j['dev_code'] as String?);
}

class AuthResult {
  AuthResult({required this.token, required this.isNew});
  final String token;
  final bool isNew;

  factory AuthResult.fromJson(Map<String, dynamic> j) =>
      AuthResult(token: j['token'] as String, isNew: (j['is_new'] ?? false) as bool);
}

class Mistake {
  Mistake({required this.wrong, required this.right, required this.why});
  final String wrong;
  final String right;
  final String why;

  factory Mistake.fromJson(Map<String, dynamic> j) => Mistake(
    wrong: (j['wrong'] ?? '') as String,
    right: (j['right'] ?? '') as String,
    why: (j['why'] ?? '') as String,
  );
}

class TutorTurn {
  TutorTurn({
    required this.reply,
    required this.corrected,
    required this.mistakes,
    required this.tip,
    required this.score,
    required this.level,
    required this.turnsLeft,
  });

  final String reply;
  final String corrected;
  final List<Mistake> mistakes;
  final String tip;
  final int score;
  final String level;
  final int turnsLeft;

  factory TutorTurn.fromJson(Map<String, dynamic> j) => TutorTurn(
    reply: (j['reply'] ?? '') as String,
    corrected: (j['corrected'] ?? '') as String,
    mistakes: [for (final m in (j['mistakes'] as List? ?? const [])) Mistake.fromJson(m as Map<String, dynamic>)],
    tip: (j['tip'] ?? '') as String,
    score: (j['score'] ?? 0) as int,
    level: (j['level'] ?? '') as String,
    turnsLeft: (j['turns_left'] ?? 0) as int,
  );
}

class LessonSummary {
  LessonSummary({
    required this.week,
    required this.theme,
    this.title = '',
    required this.scenario,
    required this.published,
    required this.locked,
  });

  final int week;
  final String theme;
  final String title; // the lesson's own title (in the learner's language) once published
  final String scenario;
  final bool published;
  final bool locked;

  String get displayTitle => title.isNotEmpty ? title : theme;

  factory LessonSummary.fromJson(Map<String, dynamic> j) => LessonSummary(
    week: j['week'] as int,
    theme: (j['theme'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    scenario: (j['scenario'] ?? 'free_talk') as String,
    published: (j['published'] ?? false) as bool,
    locked: (j['locked'] ?? false) as bool,
  );
}

class VocabItem {
  VocabItem(this.word, this.meaning, this.example);
  final String word;
  final String meaning;
  final String example;
}

class Phrase {
  Phrase(this.english, this.meaning);
  final String english;
  final String meaning;
}

class DialogueLine {
  DialogueLine(this.speaker, this.line);
  final String speaker;
  final String line;
}

class QuizQuestion {
  QuizQuestion(this.question, this.options, this.answerIndex);
  final String question;
  final List<String> options;
  final int answerIndex;
}

class Lesson {
  Lesson({
    required this.week,
    required this.title,
    required this.theme,
    required this.scenario,
    required this.objectives,
    required this.vocabulary,
    required this.phrases,
    required this.dialogue,
    required this.grammarPoint,
    required this.grammarExplanation,
    required this.grammarExamples,
    required this.speakingTasks,
    required this.quiz,
  });

  final int week;
  final String title;
  final String theme;
  final String scenario;
  final List<String> objectives;
  final List<VocabItem> vocabulary;
  final List<Phrase> phrases;
  final List<DialogueLine> dialogue;
  final String grammarPoint;
  final String grammarExplanation;
  final List<String> grammarExamples;
  final List<String> speakingTasks;
  final List<QuizQuestion> quiz;

  factory Lesson.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(String k) => [
      for (final x in (j[k] as List? ?? const [])) x as Map<String, dynamic>,
    ];
    List<String> strings(dynamic v) => [for (final x in (v as List? ?? const [])) x.toString()];
    final grammar = (j['grammar'] ?? const <String, dynamic>{}) as Map<String, dynamic>;
    return Lesson(
      week: j['week'] as int,
      title: (j['title'] ?? '') as String,
      theme: (j['theme'] ?? '') as String,
      scenario: (j['scenario'] ?? 'free_talk') as String,
      objectives: strings(j['objectives']),
      vocabulary: [for (final v in maps('vocabulary')) VocabItem('${v['word']}', '${v['meaning']}', '${v['example']}')],
      phrases: [for (final p in maps('phrases')) Phrase('${p['english']}', '${p['meaning']}')],
      dialogue: [for (final d in maps('dialogue')) DialogueLine('${d['speaker']}', '${d['line']}')],
      grammarPoint: (grammar['point'] ?? '') as String,
      grammarExplanation: (grammar['explanation'] ?? '') as String,
      grammarExamples: strings(grammar['examples']),
      speakingTasks: strings(j['speaking_tasks']),
      quiz: [
        for (final q in maps('quiz'))
          QuizQuestion('${q['question']}', strings(q['options']), (q['answer_index'] ?? 0) as int),
      ],
    );
  }
}

class Plan {
  Plan({
    required this.code,
    required this.channel,
    required this.currency,
    required this.amount,
    required this.days,
    required this.labelSw,
    required this.labelEn,
  });

  final String code;
  final String channel; // mobile_money | play
  final String currency;
  final num amount;
  final int days;
  final String labelSw;
  final String labelEn;

  bool get isMobileMoney => channel == 'mobile_money';

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
    code: j['code'] as String,
    channel: j['channel'] as String,
    currency: j['currency'] as String,
    amount: j['amount'] as num,
    days: j['days'] as int,
    labelSw: (j['label_sw'] ?? '') as String,
    labelEn: (j['label_en'] ?? '') as String,
  );
}

class VideoWeek {
  VideoWeek(this.week, this.locked);
  final int week;
  final bool locked;
}

class Video {
  Video({required this.title, required this.size, required this.url});
  final String title;
  final String size;
  final String url;

  factory Video.fromJson(Map<String, dynamic> j) =>
      Video(title: (j['title'] ?? '') as String, size: (j['size'] ?? '') as String, url: j['url'] as String);
}

class PaymentStart {
  PaymentStart({required this.externalId, required this.status});
  final String externalId;
  final String status;

  factory PaymentStart.fromJson(Map<String, dynamic> j) =>
      PaymentStart(externalId: j['external_id'] as String, status: (j['status'] ?? 'pending') as String);
}

class SupportReply {
  SupportReply({required this.reply, required this.escalated});
  final String reply;
  final bool escalated;

  factory SupportReply.fromJson(Map<String, dynamic> j) =>
      SupportReply(reply: (j['reply'] ?? '') as String, escalated: (j['escalate'] ?? false) as bool);
}
