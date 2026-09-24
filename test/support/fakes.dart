import 'dart:convert';
import 'dart:io';

import 'package:masomo/api/api_client.dart';
import 'package:masomo/api/models.dart';
import 'package:masomo/services/billing.dart';
import 'package:masomo/services/voice.dart';

/// In-memory stand-in for the Masomo server, following the same rules
/// (free limits, locked weeks, payment states) as jarvis/jarvis/server.py.
class FakeApi implements MasomoApi {
  FakeApi({this.nativeLang = 'sw', this.name = '', this.freeTurns = 10, this.pro = false});

  @override
  String? token;

  String nativeLang;
  String name;
  String level = 'A2';
  int freeTurns;
  bool pro;
  int usedTurns = 0;
  final sentMessages = <(String, String)>[];
  final payments = <String, String>{}; // externalId -> status
  final paymentRequests = <(String, String, String)>[];
  int statusPollsBeforeSuccess = 1;
  int _polls = 0;
  bool loggedOut = false;

  static const validCode = '123456';

  int get limit => pro ? 40 : freeTurns;

  void _auth() {
    if (token != 'tok-1') throw ApiException(401);
  }

  Me _me() => Me(
    id: 1,
    name: name,
    phone: '255754000001',
    level: level,
    nativeLang: nativeLang,
    country: 'TZ',
    pro: pro,
    proUntil: pro ? DateTime.utc(2026, 10, 24) : null,
    turnsLeftToday: (limit - usedTurns).clamp(0, 999),
    dailyLimit: limit,
  );

  @override
  Future<AuthStart> startLogin(String phone, String country) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) throw ApiException(422, detail: 'bad phone');
    return AuthStart(phone: '255${digits.substring(digits.length - 9)}', devCode: validCode);
  }

  @override
  Future<AuthResult> verifyLogin(String phone, String country, String code) async {
    if (code != validCode) {
      throw ApiException(
        401,
        code: 'bad_code',
        messageSw: 'Namba si sahihi au imeisha muda.',
        messageEn: 'Wrong code.',
      );
    }
    return AuthResult(token: 'tok-1', isNew: name.isEmpty);
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  Future<Me> me() async {
    _auth();
    return _me();
  }

  @override
  Future<Me> updateProfile({String? name, String? nativeLang, String? level}) async {
    _auth();
    this.name = name ?? this.name;
    this.nativeLang = nativeLang ?? this.nativeLang;
    this.level = level ?? this.level;
    return _me();
  }

  @override
  Future<TutorTurn> tutorChat(String message, String scenario) async {
    _auth();
    if (usedTurns >= limit) {
      throw ApiException(429, code: 'daily_limit', messageSw: 'Umemaliza mazungumzo ya leo.', messageEn: 'Limit.');
    }
    usedTurns++;
    sentMessages.add((message, scenario));
    final wrong = message.contains('I working');
    return TutorTurn(
      reply: 'Nice! Where do you work?',
      corrected: wrong ? message.replaceAll('I working', 'I am working') : '',
      mistakes: wrong ? [Mistake(wrong: 'I working', right: 'I am working', why: 'Tumia am kabla ya -ing.')] : [],
      tip: 'Umefanya vizuri!',
      score: wrong ? 70 : 95,
      level: 'A2',
      turnsLeft: limit - usedTurns,
    );
  }

  @override
  Future<List<LessonSummary>> lessons() async {
    _auth();
    return [
      for (var w = 1; w <= 12; w++)
        LessonSummary(week: w, theme: 'Theme $w', scenario: 'free_talk', published: w <= 2, locked: w > 1 && !pro),
    ];
  }

  @override
  Future<Lesson> lesson(int week) async {
    _auth();
    if (week > 1 && !pro) throw ApiException(402, code: 'pro_required');
    return seedLesson(week);
  }

  @override
  Future<List<VideoWeek>> videoWeeks() async {
    _auth();
    return [for (var w = 1; w <= 12; w++) VideoWeek(w, w > 1 && !pro)];
  }

  @override
  Future<List<Video>> videos(int week) async {
    _auth();
    return [Video(title: 'Greetings', size: '12MB', url: 'https://example.com/v.mp4')];
  }

  @override
  Future<List<Plan>> plans() async => [
    Plan(code: 'tz_week', channel: 'mobile_money', currency: 'TZS', amount: 2000, days: 7, labelSw: '', labelEn: ''),
    Plan(code: 'tz_month', channel: 'mobile_money', currency: 'TZS', amount: 7000, days: 30, labelSw: '', labelEn: ''),
    Plan(
      code: 'tz_quarter',
      channel: 'mobile_money',
      currency: 'TZS',
      amount: 18000,
      days: 90,
      labelSw: '',
      labelEn: '',
    ),
    Plan(code: 'pro_monthly', channel: 'play', currency: 'USD', amount: 4.99, days: 30, labelSw: '', labelEn: ''),
  ];

  @override
  Future<PaymentStart> payMobile(String plan, String provider, String phone) async {
    _auth();
    paymentRequests.add((plan, provider, phone));
    final id = 'MSM${payments.length + 1}';
    payments[id] = 'pending';
    return PaymentStart(externalId: id, status: 'pending');
  }

  @override
  Future<String> paymentStatus(String externalId) async {
    _auth();
    _polls++;
    if (payments[externalId] == 'pending' && _polls >= statusPollsBeforeSuccess) {
      payments[externalId] = 'success';
      pro = true;
    }
    return payments[externalId]!;
  }

  @override
  Future<void> verifyPlayPurchase(String purchaseToken) async {}

  @override
  Future<SupportReply> support(String message) async {
    _auth();
    return SupportReply(reply: 'Asante kwa ujumbe wako.', escalated: message.toLowerCase().contains('nimelipa'));
  }
}

/// The real hand-written week 1 and 2 lessons that ship with the server.
Lesson seedLesson(int week) {
  final file = File('jarvis/jarvis/seed_content/sw/week_${week.toString().padLeft(2, '0')}.json');
  return Lesson.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
}

class FakeVoice implements Voice {
  FakeVoice({this.status = VoiceStatus.ready, this.heard = 'I working in a hotel'});

  VoiceStatus status;
  String heard;
  final spoken = <String>[];
  bool _listening = false;

  @override
  Future<VoiceStatus> init() async => status;

  @override
  bool get isListening => _listening;

  @override
  Future<void> listen({required void Function(String text) onText, required void Function(String text) onDone}) async {
    _listening = true;
    onText(heard);
    _listening = false;
    onDone(heard);
  }

  @override
  Future<void> stopListening() async => _listening = false;

  int cancels = 0;
  int speechStops = 0;

  @override
  Future<void> cancelListening() async {
    cancels++;
    _listening = false;
  }

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async => speechStops++;
}

class FakeBilling extends NoBilling {
  int restores = 0;

  @override
  Future<void> restore() async => restores++;
}
