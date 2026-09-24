import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../services/billing.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Mobile-money networks AzamPay can charge (keys match the server).
const networks = [
  ('mpesa', 'M-Pesa'),
  ('mixx', 'Mixx by Yas'),
  ('airtel', 'Airtel Money'),
  ('halopesa', 'HaloPesa'),
  ('azampesa', 'AzamPesa'),
];

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    this.pollInterval = const Duration(seconds: 3),
    this.pollTimeout = const Duration(minutes: 2),
  });

  final Duration pollInterval;
  final Duration pollTimeout;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late Future<_Offer> _future = _load();
  String? _plan;
  String _network = 'mpesa';
  late final _phone = TextEditingController(text: _localPhone(context.read<Session>().me?.phone));
  bool _busy = false;
  String? _error;

  static String _localPhone(String? intl) =>
      intl != null && intl.startsWith('255') && intl.length == 12 ? '0${intl.substring(3)}' : '';

  Future<_Offer> _load() async {
    final billing = context.read<StoreBilling>();
    final plans = await context.read<MasomoApi>().plans();
    var store = <StoreProduct>[];
    try {
      if (await billing.available()) store = await billing.products();
    } catch (_) {
      store = [];
    }
    final mm = plans.where((p) => p.isMobileMoney).toList();
    _plan ??= mm.any((p) => p.code == 'tz_month') ? 'tz_month' : (mm.isEmpty ? null : mm.first.code);
    return _Offer(mm, store);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _payMobile(Plan plan) async {
    final session = context.read<Session>();
    final s = session.s;
    final api = context.read<MasomoApi>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await api.payMobile(plan.code, _network, _phone.text.trim());
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WaitDialog(
          externalId: start.externalId,
          api: api,
          s: s,
          interval: widget.pollInterval,
          timeout: widget.pollTimeout,
        ),
      );
      if (ok == true) {
        await session.refresh();
        if (mounted) Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!handleAuthError(context, e)) setState(() => _error = e.detail ?? errorMessage(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payStore(StoreProduct p) async {
    final session = context.read<Session>();
    final s = session.s;
    setState(() => _busy = true);
    try {
      final outcome = await context.read<StoreBilling>().buy(p);
      if (!mounted) return;
      if (outcome == PurchaseOutcome.success) {
        await session.refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.paySuccess)));
        Navigator.of(context).pop(true);
      } else if (outcome == PurchaseOutcome.failed) {
        setState(() => _error = s.payFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = session.s;
    final inTz = (session.me?.country ?? 'TZ') == 'TZ';
    return Scaffold(
      appBar: AppBar(title: Text(s.proTitle)),
      body: FutureBuilder<_Offer>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            if (handleAuthError(context, snap.error!)) return const SizedBox.shrink();
            return ErrorView(
              message: errorMessage(s, snap.error!),
              onRetry: () => setState(() {
                _future = _load();
              }),
            );
          }
          final offer = snap.data!;
          final selected = offer.mobile.where((p) => p.code == _plan).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Brand.deep, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final b in [s.proBenefit1, s.proBenefit2, s.proBenefit3])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Brand.gold, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(b, style: const TextStyle(color: Colors.white, fontSize: 15.5)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (inTz && offer.mobile.isNotEmpty) ...[
                SectionTitle(s.choosePlan),
                RadioGroup<String>(
                  groupValue: _plan,
                  onChanged: (v) => setState(() => _plan = v),
                  child: Column(
                    children: [
                      for (final p in offer.mobile)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: RadioListTile<String>(
                              key: Key('plan-${p.code}'),
                              value: p.code,
                              title: Text(s.planLabel(p.days), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: p.days >= 90
                                  ? Text(s.bestValue, style: const TextStyle(color: Brand.good))
                                  : null,
                              secondary: Text(
                                formatMoney(p.amount, p.currency),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SectionTitle(s.chooseNetwork),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (code, label) in networks)
                      ChoiceChip(
                        key: Key('net-$code'),
                        label: Text(label),
                        selected: _network == code,
                        onSelected: (_) => setState(() => _network = code),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('payPhone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: s.payingNumber, hintText: s.phoneHint, errorText: _error),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('payButton'),
                  onPressed: _busy || selected == null ? null : () => _payMobile(selected),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(s.pay(selected == null ? '' : formatMoney(selected.amount, selected.currency))),
                ),
              ] else if (offer.store.isEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  s.mobileMoneyOnlyTz,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.muted),
                ),
              ],
              if (offer.store.isNotEmpty) ...[
                SectionTitle(s.payWithPlay),
                for (final p in offer.store)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _payStore(p),
                      child: Text('${p.id == 'pro_yearly' ? s.planLabel(365) : s.planLabel(30)} · ${p.price}'),
                    ),
                  ),
                if (!inTz && _error != null) Text(_error!, style: const TextStyle(color: Brand.bad)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Offer {
  _Offer(this.mobile, this.store);
  final List<Plan> mobile;
  final List<StoreProduct> store;
}

/// Polls the payment until the customer confirms with their PIN, it fails, or we give up.
class _WaitDialog extends StatefulWidget {
  const _WaitDialog({
    required this.externalId,
    required this.api,
    required this.s,
    required this.interval,
    required this.timeout,
  });

  final String externalId;
  final MasomoApi api;
  final S s;
  final Duration interval;
  final Duration timeout;

  @override
  State<_WaitDialog> createState() => _WaitDialogState();
}

class _WaitDialogState extends State<_WaitDialog> {
  Timer? _timer;
  late final DateTime _deadline = DateTime.now().add(widget.timeout);
  String _state = 'pending'; // pending | success | failed | timeout

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (_state != 'pending') return;
    try {
      final status = await widget.api.paymentStatus(widget.externalId);
      if (!mounted) return;
      if (status == 'success') {
        setState(() => _state = 'success');
      } else if (status == 'failed') {
        setState(() => _state = 'failed');
      }
    } on ApiException {
      // Keep polling through brief network drops.
    }
    if (mounted && _state == 'pending' && DateTime.now().isAfter(_deadline)) {
      setState(() => _state = 'timeout');
    }
    if (_state != 'pending') _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final (icon, color, text) = switch (_state) {
      'success' => (Icons.check_circle_rounded, Brand.good, s.paySuccess),
      'failed' => (Icons.error_rounded, Brand.bad, s.payFailed),
      'timeout' => (Icons.schedule_rounded, Brand.deep, s.payTimeout),
      _ => (Icons.phone_android_rounded, Brand.primary, s.checkPhone),
    };
    return AlertDialog(
      key: const Key('payDialog'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(text, key: Key('payState-$_state'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          if (_state == 'pending') ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(s.waiting, style: const TextStyle(color: Brand.muted, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        // Closing while pending is allowed: Pro still turns on if the customer confirms later.
        TextButton(
          key: const Key('payDone'),
          onPressed: () => Navigator.of(context).pop(_state == 'success'),
          child: Text(_state == 'pending' ? s.close : s.done),
        ),
      ],
    );
  }
}
