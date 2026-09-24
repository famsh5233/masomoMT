import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/voice.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../pay/paywall_screen.dart';
import '../tutor/tutor_screen.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.week});
  final int week;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late Future<Lesson> _future = context.read<MasomoApi>().lesson(widget.week);

  void _reload() => setState(() {
    _future = context.read<MasomoApi>().lesson(widget.week);
  });

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.week(widget.week))),
      body: FutureBuilder<Lesson>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final err = snap.error;
          if (err != null) {
            if (handleAuthError(context, err)) return const SizedBox.shrink();
            if (err is ApiException && err.isProRequired) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PaywallScreen())),
                    child: Text(s.goPro),
                  ),
                ),
              );
            }
            return ErrorView(message: errorMessage(s, err), onRetry: _reload);
          }
          return _LessonBody(lesson: snap.data!);
        },
      ),
    );
  }
}

class _LessonBody extends StatelessWidget {
  const _LessonBody({required this.lesson});
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    final voice = context.read<Voice>();
    Widget speakButton(String text) => IconButton(
      tooltip: s.listen,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.volume_up_rounded, color: Brand.primary),
      onPressed: () async {
        await voice.init();
        await voice.speak(text);
      },
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      children: [
        Text(lesson.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 4),
        Text(lesson.theme, style: const TextStyle(color: Brand.muted)),
        SectionTitle(s.objectives),
        for (final o in lesson.objectives)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.check_circle_rounded, size: 18, color: Brand.good),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(o)),
              ],
            ),
          ),
        SectionTitle(s.vocabulary),
        Card(
          child: Column(
            children: [
              for (final (i, v) in lesson.vocabulary.indexed) ...[
                if (i > 0) const Divider(height: 1, color: Brand.line),
                ListTile(
                  title: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: v.word,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: '  ·  ${v.meaning}',
                          style: const TextStyle(color: Brand.muted),
                        ),
                      ],
                    ),
                  ),
                  subtitle: Text(v.example, style: const TextStyle(fontStyle: FontStyle.italic)),
                  trailing: speakButton('${v.word}. ${v.example}'),
                ),
              ],
            ],
          ),
        ),
        SectionTitle(s.phrases),
        Card(
          child: Column(
            children: [
              for (final (i, p) in lesson.phrases.indexed) ...[
                if (i > 0) const Divider(height: 1, color: Brand.line),
                ListTile(
                  title: Text(p.english, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(p.meaning),
                  trailing: speakButton(p.english),
                ),
              ],
            ],
          ),
        ),
        SectionTitle(s.dialogue),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              children: [
                for (final d in lesson.dialogue)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            d.speaker,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.deep),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(padding: const EdgeInsets.only(top: 12), child: Text(d.line)),
                      ),
                      speakButton(d.line),
                    ],
                  ),
              ],
            ),
          ),
        ),
        SectionTitle('${s.grammar}: ${lesson.grammarPoint}'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.grammarExplanation, style: const TextStyle(height: 1.45)),
                const SizedBox(height: 10),
                for (final e in lesson.grammarExamples)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('•  $e', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
        SectionTitle(s.speakingTasks),
        for (final (i, t) in lesson.speakingTasks.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${i + 1}. $t', style: const TextStyle(height: 1.4)),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('practiseButton'),
          icon: const Icon(Icons.mic_rounded),
          label: Text(s.practiseWithMwalimu),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => TutorScreen(initialScenario: lesson.scenario, standalone: true))),
        ),
        SectionTitle(s.quiz),
        QuizView(questions: lesson.quiz),
      ],
    );
  }
}

class QuizView extends StatefulWidget {
  const QuizView({super.key, required this.questions});
  final List<QuizQuestion> questions;

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> {
  late List<int?> _answers = List.filled(widget.questions.length, null);
  bool _checked = false;

  int get _score => [
    for (final (i, q) in widget.questions.indexed)
      if (_answers[i] == q.answerIndex) 1,
  ].length;

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, q) in widget.questions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ${q.question}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (j, o) in q.options.indexed)
                          ChoiceChip(
                            key: Key('quiz-$i-$j'),
                            label: Text(o),
                            selected: _answers[i] == j,
                            selectedColor: !_checked
                                ? Brand.primarySoft
                                : (j == q.answerIndex ? Brand.goodSoft : Brand.badSoft),
                            side: _checked && j == q.answerIndex
                                ? const BorderSide(color: Brand.good, width: 1.5)
                                : null,
                            onSelected: _checked ? null : (_) => setState(() => _answers[i] = j),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_checked)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              s.quizScore(_score, widget.questions.length),
              key: const Key('quizScore'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        _checked
            ? OutlinedButton(
                onPressed: () => setState(() {
                  _answers = List.filled(widget.questions.length, null);
                  _checked = false;
                }),
                child: Text(s.retry),
              )
            : FilledButton(
                key: const Key('checkAnswers'),
                onPressed: () {
                  if (_answers.contains(null)) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.answerAll)));
                    return;
                  }
                  setState(() => _checked = true);
                },
                child: Text(s.checkAnswers),
              ),
      ],
    );
  }
}
