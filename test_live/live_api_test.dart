// End-to-end contract test: the app's real HTTP client against a running JARVIS
// server. Skipped unless LIVE_API is set. See jarvis/devtools/e2e.sh.
//
//   LIVE_API=http://127.0.0.1:8765 flutter test test_live
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masomo/api/api_client.dart';

void main() {
  final base = Platform.environment['LIVE_API'];
  final skip = base == null ? 'set LIVE_API to run against a server' : false;
  // A fresh number per run so repeated runs don't hit the SMS rate limit.
  // It ends in 1: the mock AzamPay treats numbers ending in 9 as a customer who rejects the PIN.
  final phone = '07${(DateTime.now().millisecondsSinceEpoch % 10000000).toString().padLeft(7, '0')}1';

  test('full learner journey against the live server', () async {
    final api = HttpMasomoApi(baseUrl: base!);

    // 1. Sign in with an SMS code (a dev server returns the code in the response).
    final start = await api.startLogin(phone, 'TZ');
    expect(start.phone, startsWith('2557'));
    expect(start.devCode, isNotNull, reason: 'server must run with JARVIS_ENV=dev and console SMS');
    await expectLater(api.verifyLogin(phone, 'TZ', '000000'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'bad_code')));
    // The wrong guess above counts as an attempt, but the right code still works.
    final auth = await api.verifyLogin(phone, 'TZ', start.devCode!);
    expect(auth.isNew, isTrue);
    api.token = auth.token;

    // 2. Profile.
    var me = await api.me();
    expect(me.needsProfile, isTrue);
    me = await api.updateProfile(name: 'Neema', level: 'B1');
    expect(me.name, 'Neema');
    expect(me.pro, isFalse);
    final freeTurns = me.turnsLeftToday;
    expect(freeTurns, greaterThan(0));

    // 3. Tutor (demo model on the dev server).
    final turn = await api.tutorChat('She go to work every day', 'free_talk');
    expect(turn.corrected, 'She goes to work every day');
    expect(turn.mistakes.first.right, 'She goes');
    expect(turn.turnsLeft, freeTurns - 1);

    // 4. Lessons: week 1 free from the seed content, week 2 locked.
    final lessons = await api.lessons();
    expect(lessons.first.published, isTrue);
    expect(lessons[1].locked, isTrue);
    final week1 = await api.lesson(1);
    expect(week1.title, 'Jitambulishe kwa Kiingereza');
    await expectLater(api.lesson(2), throwsA(isA<ApiException>().having((e) => e.isProRequired, '402', true)));

    // 5. Videos come through from the (mock) legacy backend.
    final videos = await api.videos(1);
    expect(videos, isNotEmpty);
    await expectLater(api.videos(2), throwsA(isA<ApiException>().having((e) => e.isProRequired, '402', true)));

    // 6. Pay TSh 7,000 by M-Pesa; the mock AzamPay "customer" confirms and calls back.
    final plans = await api.plans();
    expect(plans.map((p) => p.code), containsAll(['tz_week', 'tz_month', 'tz_quarter']));
    final pay = await api.payMobile('tz_month', 'mpesa', phone);
    var status = 'pending';
    for (var i = 0; i < 20 && status == 'pending'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = await api.paymentStatus(pay.externalId);
    }
    expect(status, 'success');
    me = await api.me();
    expect(me.pro, isTrue);
    expect(me.proUntil!.difference(DateTime.now()).inDays, inInclusiveRange(29, 30));
    expect(me.turnsLeftToday, me.dailyLimit - 1);
    expect((await api.lesson(2)).title, 'Kazi yangu na ratiba ya kila siku');

    // 7. Support escalates a payment question to a human.
    final help = await api.support('Nimelipa mara mbili, naomba msaada');
    expect(help.escalated, isTrue);

    // 8. Sign out invalidates the token.
    await api.logout();
    await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
