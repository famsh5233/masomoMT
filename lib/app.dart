import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'screens/home_shell.dart';
import 'screens/login/phone_screen.dart';
import 'screens/profile_screen.dart';
import 'services/billing.dart';
import 'services/token_store.dart';
import 'services/voice.dart';
import 'state/session.dart';
import 'theme.dart';

class MasomoApp extends StatelessWidget {
  const MasomoApp({
    super.key,
    required this.api,
    required this.tokens,
    required this.voice,
    required this.billing,
    this.session,
  });

  final MasomoApi api;
  final TokenStore tokens;
  final Voice voice;
  final StoreBilling billing;
  final Session? session; // tests pass a pre-built session

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<MasomoApi>.value(value: api),
        Provider<Voice>.value(value: voice),
        Provider<StoreBilling>.value(value: billing),
        ChangeNotifierProvider<Session>(
          create: (_) => (session ?? Session(api: api, tokens: tokens))..start(),
        ),
      ],
      child: MaterialApp(
        title: 'Masomo',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const RootGate(),
      ),
    );
  }
}

/// Sends the user to sign-in, profile setup or the main app.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return switch (session.status) {
      SessionStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      SessionStatus.signedOut => const PhoneScreen(),
      SessionStatus.signedIn when session.me == null || session.me!.needsProfile =>
        session.me == null ? const _Reconnect() : const ProfileScreen(firstRun: true),
      SessionStatus.signedIn => const HomeShell(),
    };
  }
}

/// Signed in but the profile could not be loaded (offline at launch).
class _Reconnect extends StatefulWidget {
  const _Reconnect();

  @override
  State<_Reconnect> createState() => _ReconnectState();
}

class _ReconnectState extends State<_Reconnect> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await context.read<Session>().refresh();
    } on ApiException catch (e) {
      if (e.isUnauthorized && mounted) await context.read<Session>().expired();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>().s;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 44, color: Brand.muted),
              const SizedBox(height: 12),
              Text(s.network, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              _busy ? const CircularProgressIndicator() : OutlinedButton(onPressed: _retry, child: Text(s.retry)),
            ],
          ),
        ),
      ),
    );
  }
}
