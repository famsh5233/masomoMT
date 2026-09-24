import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone, required this.country, this.devCode});

  final String phone; // international digits, e.g. 255754123456
  final String country;
  final String? devCode; // only returned by a development server

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late final _code = TextEditingController(text: widget.devCode ?? '');
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final s = stringsOnce(context);
    final code = _code.text.trim();
    if (code.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<MasomoApi>();
      final session = context.read<Session>();
      final res = await api.verifyLogin(widget.phone, widget.country, code);
      await session.signIn(res.token);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorMessage(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final s = stringsOnce(context);
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final res = await context.read<MasomoApi>().startLogin(widget.phone, widget.country);
      if (!mounted) return;
      setState(() {
        _info = s.codeSentTo(res.phone);
        if (res.devCode != null) _code.text = res.devCode!;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorMessage(s, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Text(s.codeSentTo(widget.phone), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          TextField(
            key: const Key('codeField'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            decoration: InputDecoration(labelText: s.codeLabel, errorText: _error, counterText: ''),
            onChanged: (v) {
              if (v.length == 6) _verify();
            },
          ),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_info!, style: const TextStyle(color: Brand.good)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('verifyCode'),
            onPressed: _busy ? null : _verify,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(s.verify),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.changeNumber)),
              TextButton(onPressed: _resend, child: Text(s.resend)),
            ],
          ),
        ],
      ),
    );
  }
}
