import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'otp_screen.dart';

const countries = [('TZ', 'Tanzania (+255)'), ('KE', 'Kenya (+254)'), ('UG', 'Uganda (+256)')];

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phone = TextEditingController();
  String _country = 'TZ';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return; // the keyboard's "done" key and the button can both fire
    final s = stringsOnce(context);
    final raw = _phone.text.trim();
    if (raw.replaceAll(RegExp(r'\D'), '').length < 9) {
      setState(() => _error = s.badPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await context.read<MasomoApi>().startLogin(raw, _country);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(phone: start.phone, country: _country, devCode: start.devCode),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.statusCode == 422 && e.code == null ? s.badPhone : errorMessage(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = session.s;
    return Scaffold(
      backgroundColor: Brand.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const BrandHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => session.setUiLang(s.sw ? 'en' : 'sw'),
                    icon: const Icon(Icons.translate_rounded, size: 18),
                    label: Text(s.switchLanguage),
                  ),
                ),
                Text(s.welcomeTitle, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
                const SizedBox(height: 10),
                Text(s.welcomeBody, style: const TextStyle(fontSize: 16, color: Brand.muted, height: 1.4)),
                if (session.notice != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    session.notice!,
                    style: const TextStyle(color: Brand.deep, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 28),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _country,
                  decoration: InputDecoration(labelText: s.country),
                  items: [for (final (code, label) in countries) DropdownMenuItem(value: code, child: Text(label))],
                  onChanged: (v) => setState(() => _country = v ?? 'TZ'),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('phoneField'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: InputDecoration(labelText: s.phoneLabel, hintText: s.phoneHint, errorText: _error),
                  onSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('sendCode'),
                  onPressed: _busy ? null : _send,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(s.sendCode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
