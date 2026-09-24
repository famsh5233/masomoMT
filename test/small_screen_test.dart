// Many learners use small, low-cost phones with large system text. Every main
// screen must lay out without overflow at 320dp wide and 130% text size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masomo/app.dart';
import 'package:masomo/screens/pay/paywall_screen.dart';
import 'package:masomo/services/token_store.dart';

import 'support/fakes.dart';

Future<void> launchSmall(WidgetTester tester, {bool signedIn = true, FakeApi? api}) async {
  tester.view.physicalSize = const Size(640, 1136); // 320 x 568 dp
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MasomoApp(
      api: api ?? FakeApi(name: 'Asha'),
      tokens: MemoryTokenStore(signedIn ? 'tok-1' : null),
      voice: FakeVoice(),
      billing: FakeBilling(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sign-in and code screens fit', (tester) async {
    await launchSmall(tester, signedIn: false, api: FakeApi());
    await tester.enterText(find.byKey(const Key('phoneField')), '0754000001');
    await tester.ensureVisible(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('codeField')), findsOneWidget);
  });

  testWidgets('profile setup fits', (tester) async {
    await launchSmall(tester, api: FakeApi());
    expect(find.byKey(const Key('nameField')), findsOneWidget);
  });

  testWidgets('tutor with feedback, lessons, a lesson, videos and account fit', (tester) async {
    await launchSmall(tester);
    await tester.enterText(find.byKey(const Key('tutorInput')), 'I working in a hotel');
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedback')), findsOneWidget);

    await tester.tap(find.text('Masomo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson-1')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Video').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Akaunti').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('planCard')), findsOneWidget);
  });

  testWidgets('paywall and payment dialog fit', (tester) async {
    await launchSmall(tester);
    await tester.tap(find.text('Akaunti').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accountGoPro')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('payButton')),
      300,
      scrollable: find.descendant(of: find.byType(PaywallScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(find.byKey(const Key('payButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payButton')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('payDialog')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byKey(const Key('payState-success')), findsOneWidget);
  });
}
