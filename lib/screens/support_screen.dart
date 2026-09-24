import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _input = TextEditingController();
  final _messages = <(bool fromUser, String text)>[];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    final s = context.read<Session>().s;
    setState(() {
      _messages.add((true, text));
      _input.clear();
      _busy = true;
    });
    try {
      final r = await context.read<MasomoApi>().support(text);
      if (!mounted) return;
      setState(() {
        _messages.add((false, r.reply));
        if (r.escalated) _messages.add((false, s.escalated));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!handleAuthError(context, e)) setState(() => _messages.add((false, errorMessage(s, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.help)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final (fromUser, text) in [(false, s.supportIntro), ..._messages])
                  Align(
                    alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: EdgeInsets.only(bottom: 10, left: fromUser ? 48 : 0, right: fromUser ? 0 : 48),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: fromUser ? Brand.primary : Brand.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(text, style: TextStyle(color: fromUser ? Colors.white : Brand.ink, fontSize: 15.5)),
                    ),
                  ),
                if (_busy) const Align(alignment: Alignment.centerLeft, child: CircularProgressIndicator()),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('supportInput'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: s.supportHint, isDense: true),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.send_rounded, color: Brand.primary),
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
