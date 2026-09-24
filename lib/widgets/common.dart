import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme.dart';

S strings(BuildContext context) => context.watch<Session>().s;
S stringsOnce(BuildContext context) => context.read<Session>().s;

/// A user-facing message for any error thrown by the API layer.
String errorMessage(S s, Object error) {
  if (error is ApiException) {
    if (error.isNetwork) return s.network;
    return error.message(s.lang) ?? s.generic;
  }
  return s.generic;
}

/// Signs the user out when their token is no longer valid. Returns true if it did.
bool handleAuthError(BuildContext context, Object error) {
  if (error is ApiException && error.isUnauthorized) {
    context.read<Session>().expired();
    return true;
  }
  return false;
}

String formatMoney(num amount, String currency) {
  final whole = amount == amount.roundToDouble();
  final text = whole ? amount.round().toString() : amount.toStringAsFixed(2);
  final parts = text.split('.');
  final withCommas = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final value = parts.length > 1 ? '$withCommas.${parts[1]}' : withCommas;
  return switch (currency) {
    'TZS' => 'TSh $value',
    'KES' => 'KSh $value',
    'USD' => '\$$value',
    _ => '$currency $value',
  };
}

String formatDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = strings(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: Brand.muted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(s.retry)),
          ],
        ),
      ),
    );
  }
}

class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Brand.primarySoft, borderRadius: BorderRadius.circular(99)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 13, color: Brand.deep),
          SizedBox(width: 3),
          Text(
            'Pro',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.deep),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
  );
}

/// The Masomo wordmark on the brand colour, used on sign-in screens.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      decoration: const BoxDecoration(
        color: Brand.deep,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Image.asset(
          'assets/images/masomo.png',
          height: 44,
          alignment: Alignment.centerLeft,
          semanticLabel: 'Masomo',
        ),
      ),
    );
  }
}
