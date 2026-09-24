import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class VideoListScreen extends StatefulWidget {
  const VideoListScreen({super.key, required this.week});
  final int week;

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  late Future<List<Video>> _future = context.read<MasomoApi>().videos(widget.week);

  void _reload() => setState(() {
    _future = context.read<MasomoApi>().videos(widget.week);
  });

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.week(widget.week))),
      body: FutureBuilder<List<Video>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final err = snap.error;
          if (err != null) {
            if (handleAuthError(context, err)) return const SizedBox.shrink();
            final msg = err is ApiException && err.statusCode == 503 ? s.videosUnavailable : errorMessage(s, err);
            return ErrorView(message: msg, onRetry: _reload);
          }
          final videos = snap.data!;
          if (videos.isEmpty) {
            return Center(
              child: Text(s.noVideos, style: const TextStyle(color: Brand.muted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: videos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => Card(
              child: ListTile(
                leading: const Icon(Icons.play_circle_fill_rounded, color: Brand.primary, size: 36),
                title: Text(videos[i].title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: videos[i].size.isEmpty ? null : Text(videos[i].size),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: videos[i]))),
              ),
            ),
          );
        },
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.video});
  final Video video;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller = VideoPlayerController.networkUrl(Uri.parse(widget.video.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
          _controller.play();
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    final ready = _controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.video.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Center(
        child: _failed
            ? Text(s.videosUnavailable, style: const TextStyle(color: Colors.white))
            : !ready
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(playedColor: Brand.gold),
                  ),
                  IconButton(
                    iconSize: 56,
                    color: Colors.white,
                    icon: Icon(_controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    onPressed: () => _controller.value.isPlaying ? _controller.pause() : _controller.play(),
                  ),
                ],
              ),
      ),
    );
  }
}
