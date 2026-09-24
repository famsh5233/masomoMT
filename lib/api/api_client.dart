import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Error from the Masomo API, with a message in Swahili and English when the
/// server provides one.
class ApiException implements Exception {
  ApiException(this.statusCode, {this.code, this.messageSw, this.messageEn, this.detail});

  final int statusCode; // 0 = no connection
  final String? code;
  final String? messageSw;
  final String? messageEn;
  final String? detail;

  bool get isNetwork => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;
  bool get isDailyLimit => statusCode == 429 && code == 'daily_limit';
  bool get isProRequired => statusCode == 402;

  String? message(String lang) => lang == 'sw' ? (messageSw ?? messageEn) : (messageEn ?? messageSw);

  @override
  String toString() => 'ApiException($statusCode, $code, ${detail ?? messageEn ?? ''})';
}

/// Everything the app asks the server for. Widget tests use a fake implementation.
abstract class MasomoApi {
  String? get token;
  set token(String? value);

  Future<AuthStart> startLogin(String phone, String country);
  Future<AuthResult> verifyLogin(String phone, String country, String code);
  Future<void> logout();
  Future<Me> me();
  Future<Me> updateProfile({String? name, String? nativeLang, String? level});
  Future<TutorTurn> tutorChat(String message, String scenario);
  Future<List<LessonSummary>> lessons();
  Future<Lesson> lesson(int week);
  Future<List<VideoWeek>> videoWeeks();
  Future<List<Video>> videos(int week);
  Future<List<Plan>> plans();
  Future<PaymentStart> payMobile(String plan, String provider, String phone);
  Future<String> paymentStatus(String externalId);
  Future<void> verifyPlayPurchase(String purchaseToken);
  Future<SupportReply> support(String message);
}

class HttpMasomoApi implements MasomoApi {
  HttpMasomoApi({required this.baseUrl, http.Client? client, this.timeout = const Duration(seconds: 30)})
    : _http = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  @override
  String? token;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final request = http.Request(method, _uri(path))..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw ApiException(0, detail: 'timeout');
    } on http.ClientException catch (e) {
      throw ApiException(0, detail: e.message);
    } catch (e) {
      // SocketException and friends (dart:io is not available on web, so catch broadly).
      throw ApiException(0, detail: e.toString());
    }
    dynamic data;
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        data = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final detail = data is Map ? data['detail'] : null;
    if (detail is Map) {
      throw ApiException(
        res.statusCode,
        code: detail['code'] as String?,
        messageSw: detail['message_sw'] as String?,
        messageEn: detail['message_en'] as String?,
      );
    }
    throw ApiException(res.statusCode, detail: detail?.toString());
  }

  @override
  Future<AuthStart> startLogin(String phone, String country) async =>
      AuthStart.fromJson(await _send('POST', '/v1/auth/start', {'phone': phone, 'country': country}));

  @override
  Future<AuthResult> verifyLogin(String phone, String country, String code) async =>
      AuthResult.fromJson(await _send('POST', '/v1/auth/verify', {'phone': phone, 'country': country, 'code': code}));

  @override
  Future<void> logout() async {
    await _send('POST', '/v1/auth/logout');
  }

  @override
  Future<Me> me() async => Me.fromJson(await _send('GET', '/v1/me'));

  @override
  Future<Me> updateProfile({String? name, String? nativeLang, String? level}) async =>
      Me.fromJson(await _send('PATCH', '/v1/me', {'name': ?name, 'native_lang': ?nativeLang, 'level': ?level}));

  @override
  Future<TutorTurn> tutorChat(String message, String scenario) async =>
      TutorTurn.fromJson(await _send('POST', '/v1/tutor/chat', {'message': message, 'scenario': scenario}));

  @override
  Future<List<LessonSummary>> lessons() async {
    final data = await _send('GET', '/v1/lessons') as Map<String, dynamic>;
    return [for (final l in data['lessons'] as List) LessonSummary.fromJson(l as Map<String, dynamic>)];
  }

  @override
  Future<Lesson> lesson(int week) async => Lesson.fromJson(await _send('GET', '/v1/lessons/$week'));

  @override
  Future<List<VideoWeek>> videoWeeks() async {
    final data = await _send('GET', '/v1/videos') as Map<String, dynamic>;
    return [
      for (final w in data['weeks'] as List) VideoWeek((w as Map)['week'] as int, (w['locked'] ?? false) as bool),
    ];
  }

  @override
  Future<List<Video>> videos(int week) async {
    final data = await _send('GET', '/v1/videos/$week') as Map<String, dynamic>;
    return [for (final v in data['videos'] as List) Video.fromJson(v as Map<String, dynamic>)];
  }

  @override
  Future<List<Plan>> plans() async {
    final data = await _send('GET', '/v1/catalog') as Map<String, dynamic>;
    return [for (final p in data['plans'] as List) Plan.fromJson(p as Map<String, dynamic>)];
  }

  @override
  Future<PaymentStart> payMobile(String plan, String provider, String phone) async => PaymentStart.fromJson(
    await _send('POST', '/v1/pay/mobile', {'plan': plan, 'provider': provider, 'phone': phone}),
  );

  @override
  Future<String> paymentStatus(String externalId) async =>
      ((await _send('GET', '/v1/pay/status/$externalId')) as Map)['status'] as String;

  @override
  Future<void> verifyPlayPurchase(String purchaseToken) async {
    await _send('POST', '/v1/pay/play/verify', {'purchase_token': purchaseToken});
  }

  @override
  Future<SupportReply> support(String message) async =>
      SupportReply.fromJson(await _send('POST', '/v1/support', {'message': message}));
}
