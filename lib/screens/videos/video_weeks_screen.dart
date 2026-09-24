import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../pay/paywall_screen.dart';
import 'video_list_screen.dart';

class VideoWeeksScreen extends StatefulWidget {
  const VideoWeeksScreen({super.key});

  @override
  State<VideoWeeksScreen> createState() => _VideoWeeksScreenState();
}

class _VideoWeeksScreenState extends State<VideoWeeksScreen> {
  late Future<List<VideoWeek>> _future = _load();
  bool? _proWhenLoaded;

  Future<List<VideoWeek>> _load() {
    _proWhenLoaded = context.read<Session>().me?.pro;
    return context.read<MasomoApi>().videoWeeks();
  }

  void _reload() => setState(() {
    _future = _load();
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = session.s;
    if (_proWhenLoaded != null && session.me?.pro != _proWhenLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
      _proWhenLoaded = session.me?.pro;
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.tabVideos)),
      body: FutureBuilder<List<VideoWeek>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            if (handleAuthError(context, snap.error!)) return const SizedBox.shrink();
            return ErrorView(message: errorMessage(s, snap.error!), onRetry: _reload);
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            // Tile height grows with the phone's text size so the label never gets cut off.
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 80 + MediaQuery.textScalerOf(context).scale(40),
            ),
            itemCount: snap.data!.length,
            itemBuilder: (_, i) {
              final w = snap.data![i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key('videoWeek-${w.week}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => w.locked ? const PaywallScreen() : VideoListScreen(week: w.week)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.play_circle_fill_rounded,
                              color: w.locked ? Brand.muted : Brand.primary,
                              size: 30,
                            ),
                            const Spacer(),
                            if (w.locked) const ProBadge(),
                          ],
                        ),
                        const Spacer(),
                        Text(s.week(w.week), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
