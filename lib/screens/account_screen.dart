import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'pay/paywall_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = session.s;
    final me = session.me;
    if (me == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: Text(s.tabAccount)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Brand.deep,
                    child: Text(
                      me.name.isEmpty ? 'M' : me.name.characters.first.toUpperCase(),
                      style: const TextStyle(color: Brand.gold, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text('+${me.phone}', style: const TextStyle(color: Brand.muted)),
                        const SizedBox(height: 2),
                        Text(
                          '${s.level}: ${me.level} · ${s.levelLabel(me.level)}',
                          style: const TextStyle(fontSize: 13, color: Brand.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            key: const Key('planCard'),
            color: me.pro ? Brand.goodSoft : Brand.primarySoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    me.pro && me.proUntil != null ? s.proUntil(formatDate(me.proUntil!)) : s.freePlan,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(s.turnsLeft(me.turnsLeftToday), style: const TextStyle(color: Brand.muted)),
                  if (!me.pro) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('accountGoPro'),
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen())),
                      child: Text(s.goPro),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: Text(s.editProfile),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                ),
                const Divider(height: 1, color: Brand.line),
                ListTile(
                  leading: const Icon(Icons.support_agent_rounded),
                  title: Text(s.help),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen())),
                ),
                const Divider(height: 1, color: Brand.line),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(s.privacy),
                  onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl), mode: LaunchMode.externalApplication),
                ),
                const Divider(height: 1, color: Brand.line),
                ListTile(
                  key: const Key('logout'),
                  leading: const Icon(Icons.logout_rounded, color: Brand.bad),
                  title: Text(s.logout, style: const TextStyle(color: Brand.bad)),
                  onTap: () => context.read<Session>().signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
