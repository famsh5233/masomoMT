import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masomo/app.dart';
import 'package:masomo/screens/lessons/lesson_screen.dart';
import 'package:masomo/screens/pay/paywall_screen.dart';
import 'package:masomo/screens/profile_screen.dart';
import 'package:masomo/services/token_store.dart';
import 'package:masomo/services/voice.dart';
import 'package:masomo/widgets/common.dart';

import 'support/fakes.dart';

Future<(FakeApi, FakeVoice, MemoryTokenStore)> launch(
  WidgetTester tester, {
  FakeApi? api,
  FakeVoice? voice,
  bool signedIn = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final a = api ?? FakeApi(name: 'Asha');
  final v = voice ?? FakeVoice();
  final store = MemoryTokenStore(signedIn ? 'tok-1' : null);
  await tester.pumpWidget(MasomoApp(api: a, tokens: store, voice: v, billing: FakeBilling()));
  await tester.pumpAndSettle();
  return (a, v, store);
}

/// Scrolls the main list of [screen] (other screens stay mounted underneath) until [target] is visible.
Future<void> scrollTo(WidgetTester tester, Finder target, Type screen, {double delta = 250}) async {
  final list = find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(target, delta, scrollable: list);
  await tester.ensureVisible(target); // bring it fully on screen, not just partly
  await tester.pumpAndSettle();
}

/// The tutor's "turns left" pill shows the number; its full sentence is the accessibility label.
Finder turnsLeftPill(String label) => find.bySemanticsLabel(label);

void main() {
  testWidgets('new user signs in with an SMS code and sets up a profile', (tester) async {
    final (api, _, store) = await launch(tester, api: FakeApi(), signedIn: false);
    expect(find.text('Ongea Kiingereza kwa kujiamini'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('phoneField')), '12');
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    expect(find.text('Andika namba sahihi ya simu'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('phoneField')), '0754 000 001');
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    expect(find.textContaining('+255754000001'), findsOneWidget);

    // A wrong code shows the server's message and does not sign in.
    await tester.enterText(find.byKey(const Key('codeField')), '000000');
    await tester.pumpAndSettle();
    expect(find.text('Namba si sahihi au imeisha muda.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('codeField')), FakeApi.validCode);
    await tester.pumpAndSettle();
    expect(store.value, 'tok-1');
    expect(find.text('Tukufahamu'), findsOneWidget); // profile setup

    await scrollTo(tester, find.byKey(const Key('saveProfile')), ProfileScreen, delta: 300);
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('nameField')), ProfileScreen, delta: -300);
    expect(find.text('Andika jina lako'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('nameField')), 'Juma');
    await scrollTo(tester, find.text('Naelewa, lakini kuongea ni kugumu'), ProfileScreen, delta: 200);
    await tester.tap(find.text('Naelewa, lakini kuongea ni kugumu'));
    await scrollTo(tester, find.byKey(const Key('saveProfile')), ProfileScreen, delta: 300);
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect(api.name, 'Juma');
    expect(api.level, 'B1');
    expect(find.text('Mwalimu'), findsOneWidget);
  });

  testWidgets('interface switches to English before sign-in', (tester) async {
    await launch(tester, api: FakeApi(), signedIn: false);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Speak English with confidence'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('non-Swahili learners get an English interface', (tester) async {
    await launch(
      tester,
      api: FakeApi(name: 'Musa', nativeLang: 'ha'),
    );
    expect(find.text('Speak'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(turnsLeftPill('10 turns left today'), findsOneWidget);
  });

  testWidgets('typed message gets corrections, a reply and a spoken answer', (tester) async {
    final (api, voice, _) = await launch(tester);
    expect(turnsLeftPill('Mazungumzo 10 yamebaki leo'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tutorInput')), 'I working in a hotel');
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();

    expect(api.sentMessages.single, ('I working in a hotel', 'free_talk'));
    expect(find.text('I am working in a hotel'), findsOneWidget);
    expect(find.text('Tumia am kabla ya -ing.'), findsOneWidget);
    expect(find.text('Nice! Where do you work?'), findsOneWidget);
    expect(voice.spoken, ['Nice! Where do you work?']);
    expect(turnsLeftPill('Mazungumzo 9 yamebaki leo'), findsOneWidget);
  });

  testWidgets('speaking into the mic sends what was heard', (tester) async {
    final (api, _, _) = await launch(tester, voice: FakeVoice(heard: 'She works at a bank'));
    await tester.tap(find.text('Usaili wa kazi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('micButton')));
    await tester.pumpAndSettle();
    expect(api.sentMessages.single, ('She works at a bank', 'job_interview'));
    expect(find.text('Nice! Where do you work?'), findsOneWidget);
  });

  testWidgets('mic without permission explains what to do', (tester) async {
    await launch(tester, voice: FakeVoice(status: VoiceStatus.denied));
    await tester.tap(find.byKey(const Key('micButton')));
    await tester.pump();
    expect(find.text('Ruhusu kipaza sauti ili uongee.'), findsOneWidget);
  });

  testWidgets('daily limit shows the upgrade card, and paying by M-Pesa unlocks Pro', (tester) async {
    final (api, _, _) = await launch(tester, api: FakeApi(name: 'Asha', freeTurns: 1));
    await tester.enterText(find.byKey(const Key('tutorInput')), 'Hello');
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tutorInput')), 'Second message');
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('limitCard')), findsOneWidget);
    expect(api.sentMessages.length, 1);

    await tester.tap(find.byKey(const Key('limitGoPro')));
    await tester.pumpAndSettle();
    expect(find.text('Masomo Pro'), findsOneWidget);
    expect(find.text('TSh 7,000'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('payButton')), PaywallScreen, delta: 300);
    expect(find.text('Lipa TSh 7,000'), findsOneWidget); // monthly is pre-selected
    await scrollTo(tester, find.byKey(const Key('plan-tz_week')), PaywallScreen, delta: -300);

    await tester.tap(find.byKey(const Key('plan-tz_week')));
    await scrollTo(tester, find.byKey(const Key('net-airtel')), PaywallScreen, delta: 200);
    await tester.tap(find.byKey(const Key('net-airtel')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('payButton')), PaywallScreen, delta: 300);
    expect(find.text('Lipa TSh 2,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payButton')));
    await tester.pump();
    await tester.pump();
    expect(api.paymentRequests.single, ('tz_week', 'airtel', '0754000001'));
    expect(find.byKey(const Key('payState-pending')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // first status poll
    await tester.pump();
    expect(find.byKey(const Key('payState-success')), findsOneWidget);
    await tester.tap(find.byKey(const Key('payDone')));
    await tester.pumpAndSettle();

    // Back on the tutor: Pro allowance applies and the limit card is gone.
    expect(find.byKey(const Key('limitCard')), findsNothing);
    expect(turnsLeftPill('Mazungumzo 39 yamebaki leo'), findsOneWidget);
  });

  testWidgets('lessons: week 1 opens with its quiz, week 2 needs Pro', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Masomo').last);
    await tester.pumpAndSettle();
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('Inakuja hivi karibuni'), findsWidgets); // weeks 3-12 not written yet

    await tester.tap(find.byKey(const Key('lesson-2')));
    await tester.pumpAndSettle();
    expect(find.text('Masomo Pro'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('lesson-1')));
    await tester.pumpAndSettle();
    expect(find.text('Jitambulishe kwa Kiingereza'), findsOneWidget);

    final lesson = seedLesson(1);
    await scrollTo(tester, find.byKey(const Key('checkAnswers')), LessonScreen, delta: 400);
    await tester.tap(find.byKey(const Key('checkAnswers')));
    await tester.pump();
    expect(find.text('Jibu maswali yote kwanza'), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('quiz-0-0')), LessonScreen, delta: -200);
    for (final (i, q) in lesson.quiz.indexed) {
      // Answer every question correctly except the first.
      final pick = i == 0 ? (q.answerIndex + 1) % q.options.length : q.answerIndex;
      final chip = find.byKey(Key('quiz-$i-$pick'));
      await scrollTo(tester, chip, LessonScreen, delta: 200);
      await tester.tap(chip);
    }
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('checkAnswers')), LessonScreen, delta: 200);
    await tester.tap(find.byKey(const Key('checkAnswers')));
    await tester.pumpAndSettle();
    expect(find.text('Umepata ${lesson.quiz.length - 1} kati ya ${lesson.quiz.length}'), findsOneWidget);
  });

  testWidgets('practise button opens the tutor in the lesson scenario', (tester) async {
    final (api, _, _) = await launch(tester);
    await tester.tap(find.text('Masomo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson-1')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('practiseButton')), LessonScreen, delta: 400);
    await tester.tap(find.byKey(const Key('practiseButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tutorInput')).last, 'My name is Asha');
    await tester.tap(find.byKey(const Key('sendButton')).last);
    await tester.pumpAndSettle();
    expect(api.sentMessages.single, ('My name is Asha', 'free_talk'));
  });

  testWidgets('videos: free week lists videos, locked week opens Pro', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Video').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('videoWeek-1')));
    await tester.pumpAndSettle();
    expect(find.text('Greetings'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('videoWeek-2')));
    await tester.pumpAndSettle();
    expect(find.text('Masomo Pro'), findsOneWidget);
  });

  testWidgets('account shows Pro status, support escalates payment problems, sign-out works', (tester) async {
    final (api, _, store) = await launch(tester, api: FakeApi(name: 'Asha', pro: true));
    await tester.tap(find.text('Akaunti'));
    await tester.pumpAndSettle();
    expect(find.text('Pro hadi ${formatDate(DateTime.utc(2026, 10, 24))}'), findsOneWidget);
    expect(find.byKey(const Key('accountGoPro')), findsNothing);

    await tester.tap(find.text('Msaada'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('supportInput')), 'Nimelipa lakini Pro haijawaka');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Tumepokea. Mtu wa timu yetu atakujibu hivi karibuni.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();
    expect(api.loggedOut, isTrue);
    expect(store.value, isNull);
    expect(find.byKey(const Key('phoneField')), findsOneWidget);
  });

  testWidgets('a token rejected by the server sends the user back to sign-in', (tester) async {
    final api = FakeApi(name: 'Asha');
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MasomoApp(api: api, tokens: MemoryTokenStore('stale'), voice: FakeVoice(), billing: FakeBilling()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phoneField')), findsOneWidget);
  });

  test('money formatting', () {
    expect(formatMoney(2000, 'TZS'), 'TSh 2,000');
    expect(formatMoney(18000, 'TZS'), 'TSh 18,000');
    expect(formatMoney(4.99, 'USD'), '\$4.99');
    expect(formatMoney(1250000, 'KES'), 'KSh 1,250,000');
  });
}
