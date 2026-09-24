import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../services/token_store.dart';

enum SessionStatus { loading, signedOut, signedIn }

/// Who is signed in, their profile and Pro status, and the interface language.
class Session extends ChangeNotifier {
  Session({required this.api, required this.tokens});

  final MasomoApi api;
  final TokenStore tokens;

  SessionStatus status = SessionStatus.loading;
  Me? me;
  String _uiLang = 'sw';
  String? notice; // one-off message for the sign-in screen, e.g. "please sign in again"

  String get uiLang => _uiLang;
  S get s => S(_uiLang);

  void setUiLang(String lang) {
    _uiLang = lang == 'sw' ? 'sw' : 'en';
    notifyListeners();
  }

  Future<void> start() async {
    final token = await tokens.read();
    if (token == null) {
      status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }
    api.token = token;
    try {
      await refresh();
      status = SessionStatus.signedIn;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _clear();
      } else {
        // Offline at launch: keep the token and let screens show their own errors.
        status = SessionStatus.signedIn;
      }
    }
    notifyListeners();
  }

  Future<void> signIn(String token) async {
    api.token = token;
    await tokens.write(token);
    await refresh();
    status = SessionStatus.signedIn;
    notice = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    me = await api.me();
    _uiLang = me!.nativeLang == 'sw' ? 'sw' : 'en';
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? nativeLang, String? level}) async {
    me = await api.updateProfile(name: name, nativeLang: nativeLang, level: level);
    _uiLang = me!.nativeLang == 'sw' ? 'sw' : 'en';
    notifyListeners();
  }

  void setTurnsLeft(int turnsLeft) {
    final m = me;
    if (m == null) return;
    me = Me(
      id: m.id,
      name: m.name,
      phone: m.phone,
      level: m.level,
      nativeLang: m.nativeLang,
      country: m.country,
      pro: m.pro,
      proUntil: m.proUntil,
      turnsLeftToday: turnsLeft,
      dailyLimit: m.dailyLimit,
    );
    notifyListeners();
  }

  /// Call when any request returns 401: the token was replaced on another device.
  Future<void> expired() async {
    notice = s.sessionExpired;
    await _clear();
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.logout();
    } on ApiException {
      // Signing out locally is enough if the server can't be reached.
    }
    await _clear();
    notifyListeners();
  }

  Future<void> _clear() async {
    await tokens.clear();
    api.token = null;
    me = null;
    status = SessionStatus.signedOut;
  }
}
