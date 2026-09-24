import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/voice.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../pay/paywall_screen.dart';

const scenarios = ['free_talk', 'job_interview', 'customer_service', 'tourism', 'phone_call', 'small_business'];

class _Entry {
  _Entry.learner(this.text) : fromTutor = false;
  _Entry.tutor(this.text) : fromTutor = true;

  final String text;
  final bool fromTutor;
  TutorTurn? feedback;
  bool failed = false;
}

class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key, this.initialScenario = 'free_talk', this.standalone = false});

  final String initialScenario;
  final bool standalone; // opened from a lesson, with its own back button

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  late String _scenario = scenarios.contains(widget.initialScenario) ? widget.initialScenario : 'free_talk';
  final _entries = <_Entry>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _listening = false;
  String _partial = '';
  bool _limitReached = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _sending) return;
    final api = context.read<MasomoApi>();
    final session = context.read<Session>();
    final voice = context.read<Voice>();
    final entry = _Entry.learner(text);
    setState(() {
      _entries.add(entry);
      _sending = true;
      _input.clear();
    });
    _scrollToEnd();
    try {
      final turn = await api.tutorChat(text, _scenario);
      if (!mounted) return;
      setState(() {
        entry.feedback = turn;
        _entries.add(_Entry.tutor(turn.reply));
      });
      session.setTurnsLeft(turn.turnsLeft);
      _scrollToEnd();
      voice.speak(turn.reply);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (handleAuthError(context, e)) return;
      setState(() {
        if (e.isDailyLimit) {
          _entries.remove(entry);
          _input.text = text;
          _limitReached = true;
          session.setTurnsLeft(0);
        } else {
          entry.failed = true;
        }
      });
      if (!e.isDailyLimit) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(session.s, e))));
      }
      _scrollToEnd();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleMic() async {
    final voice = context.read<Voice>();
    final s = context.read<Session>().s;
    if (_listening) {
      await voice.stopListening();
      return;
    }
    final status = await voice.init();
    if (!mounted) return;
    if (status != VoiceStatus.ready) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(status == VoiceStatus.denied ? s.micDenied : s.speechUnavailable)));
      return;
    }
    setState(() {
      _listening = true;
      _partial = '';
    });
    await voice.listen(
      onText: (t) {
        if (mounted) setState(() => _partial = t);
      },
      onDone: (t) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _partial = '';
        });
        if (t.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.didNotHear)));
        } else {
          _send(t);
        }
      },
    );
  }

  void _changeScenario(String code) {
    if (code == _scenario) return;
    setState(() {
      _scenario = code;
      _entries.clear();
    });
  }

  Future<void> _openPaywall() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
    if (!mounted) return;
    final me = context.read<Session>().me;
    if (me != null && me.turnsLeftToday > 0) setState(() => _limitReached = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = session.s;
    final me = session.me;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: const Text('Mwalimu'),
        actions: [
          if (me != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Tooltip(
                  message: s.turnsLeft(me.turnsLeftToday),
                  child: Semantics(
                    label: s.turnsLeft(me.turnsLeftToday),
                    excludeSemantics: true,
                    child: Container(
                      key: const Key('turnsLeft'),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Brand.primarySoft, borderRadius: BorderRadius.circular(99)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.forum_rounded, size: 15, color: Brand.deep),
                          const SizedBox(width: 5),
                          Text(
                            '${me.turnsLeftToday}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.deep),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final code in scenarios)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.scenario(code)),
                      selected: code == _scenario,
                      onSelected: (_) => _changeScenario(code),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _TutorBubble(text: s.tutorIntro, speakable: false),
                for (final e in _entries)
                  e.fromTutor
                      ? _TutorBubble(text: e.text)
                      : _LearnerTurn(
                          entry: e,
                          onRetry: e.failed
                              ? () {
                                  setState(() => _entries.remove(e));
                                  _send(e.text);
                                }
                              : null,
                        ),
                if (_sending) const _Typing(),
                if (_limitReached) _LimitCard(pro: me?.pro ?? false, onUpgrade: _openPaywall),
              ],
            ),
          ),
          _Composer(
            controller: _input,
            listening: _listening,
            partial: _partial,
            enabled: !_sending && !_limitReached,
            onSend: () => _send(_input.text),
            onMic: _toggleMic,
          ),
        ],
      ),
    );
  }
}

class _TutorBubble extends StatelessWidget {
  const _TutorBubble({required this.text, this.speakable = true});
  final String text;
  final bool speakable;

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Brand.deep,
            child: Text(
              'M',
              style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: const BoxDecoration(
                color: Brand.surface,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(text, style: const TextStyle(fontSize: 16, height: 1.35)),
                    ),
                  ),
                  if (speakable)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: s.listen,
                      icon: const Icon(Icons.volume_up_rounded, color: Brand.primary),
                      onPressed: () => context.read<Voice>().speak(text),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LearnerTurn extends StatelessWidget {
  const _LearnerTurn({required this.entry, this.onRetry});
  final _Entry entry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    final f = entry.feedback;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: entry.failed ? Brand.badSoft : Brand.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      entry.text,
                      style: TextStyle(fontSize: 16, height: 1.35, color: entry.failed ? Brand.bad : Colors.white),
                    ),
                  ),
                  if (entry.failed) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.refresh_rounded, size: 18, color: Brand.bad),
                  ],
                ],
              ),
            ),
          ),
          if (f != null && (f.corrected.isNotEmpty || f.mistakes.isNotEmpty || f.tip.isNotEmpty))
            Container(
              key: const Key('feedback'),
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Brand.surface,
                border: Border.all(color: Brand.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (f.corrected.isNotEmpty) ...[
                    Text(
                      s.betterWay,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.good),
                    ),
                    const SizedBox(height: 2),
                    Text(f.corrected, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                  ],
                  for (final m in f.mistakes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: m.wrong,
                                  style: const TextStyle(color: Brand.bad, decoration: TextDecoration.lineThrough),
                                ),
                                const WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6),
                                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: Brand.muted),
                                  ),
                                ),
                                TextSpan(
                                  text: m.right,
                                  style: const TextStyle(color: Brand.good, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          Text(m.why, style: const TextStyle(fontSize: 13.5, color: Brand.muted)),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(f.tip, style: const TextStyle(fontSize: 13.5, color: Brand.muted)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: f.score >= 80 ? Brand.goodSoft : Brand.primarySoft,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${s.score} ${f.score}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: f.score >= 80 ? Brand.good : Brand.deep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 40, bottom: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
    ),
  );
}

class _LimitCard extends StatelessWidget {
  const _LimitCard({required this.pro, required this.onUpgrade});
  final bool pro;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Card(
      key: const Key('limitCard'),
      color: Brand.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.limitTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(pro ? s.limitBodyPro : s.limitBody),
            if (!pro) ...[
              const SizedBox(height: 12),
              FilledButton(key: const Key('limitGoPro'), onPressed: onUpgrade, child: Text(s.goPro)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.listening,
    required this.partial,
    required this.enabled,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final bool listening;
  final String partial;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Container(
      decoration: const BoxDecoration(
        color: Brand.surface,
        border: Border(top: BorderSide(color: Brand.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (listening)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  partial.isEmpty ? s.listening : partial,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Brand.muted),
                ),
              ),
            Row(
              children: [
                Semantics(
                  button: true,
                  label: listening ? s.listening : s.tapToSpeak,
                  child: Material(
                    color: listening ? Brand.deep : Brand.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      key: const Key('micButton'),
                      customBorder: const CircleBorder(),
                      onTap: enabled || listening ? onMic : null,
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('tutorInput'),
                    controller: controller,
                    enabled: enabled && !listening,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 600,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(hintText: s.typeHint, counterText: '', isDense: true),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                IconButton(
                  key: const Key('sendButton'),
                  tooltip: s.send,
                  onPressed: enabled && !listening ? onSend : null,
                  icon: const Icon(Icons.send_rounded, color: Brand.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
