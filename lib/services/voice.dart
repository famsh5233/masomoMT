import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceStatus { ready, unavailable, denied }

/// Speech in and out, both on the device. Only text is sent to the server,
/// which keeps each tutor turn cheap and keeps the learner's voice private.
abstract class Voice {
  Future<VoiceStatus> init();
  bool get isListening;

  /// Streams partial text to [onText]; [onDone] gets the final text ('' if nothing was heard).
  Future<void> listen({required void Function(String text) onText, required void Function(String text) onDone});
  Future<void> stopListening();

  /// Stops listening and drops whatever was heard (onDone is not called).
  Future<void> cancelListening();
  Future<void> speak(String text);
  Future<void> stopSpeaking();
}

class DeviceVoice implements Voice {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  VoiceStatus? _status;
  String? _localeId;
  String _last = '';
  void Function(String)? _onDone;
  bool _finished = false;

  // Preferred English recognisers: East African English first, then widely installed ones.
  static const _preferred = ['en_TZ', 'en_KE', 'en_UG', 'en_GB', 'en_US'];

  @override
  bool get isListening => _stt.isListening;

  @override
  Future<VoiceStatus> init() async {
    if (_status != null) return _status!;
    var denied = false;
    bool ok;
    try {
      ok = await _stt.initialize(
        onError: (SpeechRecognitionError e) {
          if (e.errorMsg.contains('permission')) denied = true;
          _finish();
        },
        onStatus: (s) {
          if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) _finish();
        },
      );
    } catch (_) {
      ok = false;
    }
    if (ok) {
      try {
        final locales = await _stt.locales();
        final ids = {for (final l in locales) l.localeId.replaceAll('-', '_'): l.localeId};
        _localeId = _preferred.map((p) => ids[p]).firstWhere((id) => id != null, orElse: () => null);
      } catch (_) {
        _localeId = null; // the recogniser's default language is used
      }
    }
    try {
      await _tts.setLanguage('en-GB');
      await _tts.setSpeechRate(0.45);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // Text-to-speech is optional; the reply is also shown as text.
    }
    return _status = ok ? VoiceStatus.ready : (denied ? VoiceStatus.denied : VoiceStatus.unavailable);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    final cb = _onDone;
    _onDone = null;
    cb?.call(_last.trim());
  }

  @override
  Future<void> listen({required void Function(String text) onText, required void Function(String text) onDone}) async {
    _last = '';
    _finished = false;
    _onDone = onDone;
    await _tts.stop();
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        _last = r.recognizedWords;
        onText(_last);
        if (r.finalResult) _finish();
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> stopListening() async {
    await _stt.stop();
    // Some recognisers never send a final result after a manual stop.
    Timer(const Duration(milliseconds: 800), _finish);
  }

  @override
  Future<void> cancelListening() async {
    _onDone = null;
    _finished = true;
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
