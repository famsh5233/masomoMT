import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Languages Mwalimu can explain in (must match jarvis/jarvis/agents/__init__.py).
const nativeLanguages = {
  'sw': 'Kiswahili',
  'ha': 'Hausa',
  'yo': 'Yorùbá',
  'am': 'አማርኛ (Amharic)',
  'so': 'Soomaali',
  'fr': 'Français',
  'pt': 'Português',
  'ar': 'العربية (Arabic)',
  'hi': 'हिन्दी (Hindi)',
  'bn': 'বাংলা (Bengali)',
  'ur': 'اردو (Urdu)',
  'id': 'Bahasa Indonesia',
  'vi': 'Tiếng Việt',
  'tr': 'Türkçe',
  'es': 'Español',
};

const levels = ['A1', 'A2', 'B1', 'B2', 'C1'];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.firstRun = false});
  final bool firstRun;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  late String _lang;
  late String _level;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = context.read<Session>().me;
    _name = TextEditingController(text: me?.name ?? '');
    _lang = nativeLanguages.containsKey(me?.nativeLang) ? me!.nativeLang : 'sw';
    _level = levels.contains(me?.level) ? me!.level : 'A2';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = context.read<Session>();
    final s = session.s;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = s.nameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.updateProfile(name: _name.text.trim(), nativeLang: _lang, level: _level);
      if (mounted && !widget.firstRun) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!handleAuthError(context, e)) setState(() => _error = errorMessage(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? s.setupTitle : s.editProfile)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            key: const Key('nameField'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: s.yourName, errorText: _error),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _lang,
            decoration: InputDecoration(labelText: s.nativeLanguage),
            items: [for (final e in nativeLanguages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _lang = v ?? 'sw'),
          ),
          SectionTitle(s.yourLevel),
          RadioGroup<String>(
            groupValue: _level,
            onChanged: (v) => setState(() => _level = v ?? _level),
            child: Column(
              children: [
                for (final l in levels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: RadioListTile<String>(
                        value: l,
                        title: Text(s.levelLabel(l)),
                        secondary: Text(
                          l,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.muted),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('saveProfile'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(widget.firstRun ? s.continueLabel : s.save),
          ),
        ],
      ),
    );
  }
}
