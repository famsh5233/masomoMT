import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/billing.dart';
import '../state/session.dart';

import '../widgets/common.dart';
import 'account_screen.dart';
import 'lessons/lessons_screen.dart';
import 'tutor/tutor_screen.dart';
import 'videos/video_weeks_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Finish any store purchase whose check with our server failed earlier (e.g. offline).
    final billing = context.read<StoreBilling>();
    final session = context.read<Session>();
    billing.onVerified = () => session.refresh().catchError((_) {});
    billing.restore().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          TutorScreen(active: _tab == 0),
          const LessonsScreen(),
          const VideoWeeksScreen(),
          const AccountScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.mic_none_rounded),
            selectedIcon: const Icon(Icons.mic_rounded),
            label: s.tabSpeak,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book_rounded),
            label: s.tabLessons,
          ),
          NavigationDestination(
            icon: const Icon(Icons.play_circle_outline_rounded),
            selectedIcon: const Icon(Icons.play_circle_rounded),
            label: s.tabVideos,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: s.tabAccount,
          ),
        ],
      ),
    );
  }
}
