import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:masomo/api/api_client.dart';
import 'package:masomo/api/models.dart';

void main() {
  late List<http.Request> requests;

  HttpMasomoApi apiReturning(int status, Object? body) {
    requests = [];
    return HttpMasomoApi(
      baseUrl: 'https://api.test',
      client: MockClient((req) async {
        requests.add(req);
        return http.Response(
          body == null ? '' : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  test('login start and verify send the right JSON', () async {
    final api = apiReturning(200, {'phone': '255754000001', 'sent': true, 'dev_code': '123456'});
    final start = await api.startLogin('0754 000 001', 'TZ');
    expect(start.phone, '255754000001');
    expect(start.devCode, '123456');
    expect(requests.single.url.toString(), 'https://api.test/v1/auth/start');
    expect(jsonDecode(requests.single.body), {'phone': '0754 000 001', 'country': 'TZ'});
    expect(requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('authenticated calls send the bearer token', () async {
    final api = apiReturning(200, {
      'id': 1,
      'name': 'Asha',
      'phone': '255754000001',
      'level': 'A2',
      'native_lang': 'sw',
      'country': 'TZ',
      'pro': true,
      'pro_until': '2026-10-24T12:00:00+00:00',
      'turns_left_today': 40,
      'daily_limit': 40,
    })..token = 'abc';
    final me = await api.me();
    expect(requests.single.headers['Authorization'], 'Bearer abc');
    expect(me.pro, isTrue);
    expect(me.proUntil, DateTime.utc(2026, 10, 24, 12));
    expect(me.needsProfile, isFalse);
  });

  test('profile update only sends the fields given', () async {
    final api = apiReturning(200, {'id': 1, 'name': 'A', 'phone': '', 'level': 'B1', 'native_lang': 'sw'})..token = 't';
    await api.updateProfile(level: 'B1');
    expect(requests.single.method, 'PATCH');
    expect(jsonDecode(requests.single.body), {'level': 'B1'});
  });

  test('daily limit is recognised with its bilingual message', () async {
    final api = apiReturning(429, {
      'detail': {'code': 'daily_limit', 'upgrade': true, 'message_sw': 'Umemaliza', 'message_en': 'Used up'},
    })..token = 't';
    final e = await api
        .tutorChat('hi', 'free_talk')
        .then<ApiException?>((_) => null, onError: (e) => e as ApiException);
    expect(e!.isDailyLimit, isTrue);
    expect(e.message('sw'), 'Umemaliza');
    expect(e.message('en'), 'Used up');
  });

  test('402 and 401 map to the right flags', () async {
    var api = apiReturning(402, {
      'detail': {'code': 'pro_required', 'upgrade': true},
    })..token = 't';
    await expectLater(api.lesson(3), throwsA(isA<ApiException>().having((e) => e.isProRequired, 'pro', true)));
    api = apiReturning(401, {'detail': 'invalid or missing token'});
    await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
  });

  test('network failure becomes status 0', () async {
    final api = HttpMasomoApi(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => throw http.ClientException('no route')),
    );
    await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)));
  });

  test('tutor turn parses corrections', () async {
    final api = apiReturning(200, {
      'reply': 'Nice!',
      'corrected': 'I am working.',
      'tip': 'Safi',
      'score': 70,
      'level': 'A2',
      'turns_left': 9,
      'mistakes': [
        {'wrong': 'I working', 'right': 'I am working', 'why': 'Tumia am'},
      ],
    })..token = 't';
    final t = await api.tutorChat('I working', 'job_interview');
    expect(jsonDecode(requests.single.body), {'message': 'I working', 'scenario': 'job_interview'});
    expect(t.mistakes.single.right, 'I am working');
    expect(t.turnsLeft, 9);
  });

  test('the shipped seed lessons parse into the app model', () {
    for (final week in [1, 2]) {
      final file = File('jarvis/jarvis/seed_content/sw/week_0$week.json');
      final lesson = Lesson.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      expect(lesson.week, week);
      expect(lesson.vocabulary.length, greaterThanOrEqualTo(10));
      expect(lesson.quiz.every((q) => q.answerIndex < q.options.length), isTrue);
      expect(lesson.grammarExplanation, isNotEmpty);
    }
  });

  test('catalog plans and video lists parse', () async {
    var api = apiReturning(200, {
      'plans': [
        {
          'code': 'tz_week',
          'channel': 'mobile_money',
          'currency': 'TZS',
          'amount': 2000,
          'days': 7,
          'label_sw': 'Wiki 1',
          'label_en': '1 week',
        },
        {
          'code': 'pro_monthly',
          'channel': 'play',
          'currency': 'USD',
          'amount': 4.99,
          'days': 30,
          'label_sw': 'Mwezi 1',
          'label_en': 'Monthly',
        },
      ],
    });
    final plans = await api.plans();
    expect(plans.first.isMobileMoney, isTrue);
    expect(plans.last.amount, 4.99);
    api = apiReturning(200, {
      'week': 1,
      'videos': [
        {'title': 'A', 'size': '1MB', 'url': 'https://x/a.mp4'},
      ],
    })..token = 't';
    expect((await api.videos(1)).single.url, 'https://x/a.mp4');
  });
}
