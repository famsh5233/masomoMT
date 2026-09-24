import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../pay/paywall_screen.dart';
import 'lesson_screen.dart';

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  late Future<List<LessonSummary>> _future = _load();
  bool? _proWhenLoaded;

  Future<List<LessonSummary>> _load() {
    _proWhenLoaded = context.read<Session>().me?.pro;
    return context.read<MasomoApi>().lessons();
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _open(LessonSummary l) async {
    if (!l.published) return;
    if (l.locked) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(week: l.week)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = session.s;
    // Unlock weeks straight after the learner goes Pro.
    if (_proWhenLoaded != null && session.me?.pro != _proWhenLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
      _proWhenLoaded = session.me?.pro;
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.tabLessons)),
      body: FutureBuilder<List<LessonSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            if (handleAuthError(context, snap.error!)) return const SizedBox.shrink();
            return ErrorView(message: errorMessage(s, snap.error!), onRetry: _reload);
          }
          final lessons = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: lessons.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final l = lessons[i];
                return Card(
                  child: ListTile(
                    key: Key('lesson-${l.week}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: l.locked || !l.published ? Brand.line : Brand.primarySoft,
                      child: Text(
                        '${l.week}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.deep),
                      ),
                    ),
                    title: Text(s.week(l.week), style: const TextStyle(fontSize: 13, color: Brand.muted)),
                    subtitle: Text(
                      l.displayTitle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Brand.ink),
                    ),
                    trailing: !l.published
                        ? Text(s.comingSoon, style: const TextStyle(fontSize: 12, color: Brand.muted))
                        : l.locked
                        ? const ProBadge()
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: l.published ? () => _open(l) : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
