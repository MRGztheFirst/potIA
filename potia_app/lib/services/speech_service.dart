import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

typedef SpeechResultCallback = void Function(String words, bool isFinal);

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  String? _localeId;
  void Function(String status)? _onStatus;
  void Function(String error)? _onError;

  bool get isListening => _speech.isListening;

  Future<bool> start({
    required SpeechResultCallback onResult,
    required void Function(String status) onStatus,
    required void Function(String error) onError,
    void Function(double level)? onLevel,
  }) async {
    _onStatus = onStatus;
    _onError = onError;
    if (!await _ensureReady()) return false;
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords, result.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        autoPunctuation: true,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 60),
      ),
    );
    return true;
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();

  Future<bool> _ensureReady() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        onStatus: (status) => _onStatus?.call(status),
        onError: (SpeechRecognitionError error) => _onError?.call(error.errorMsg),
      );
    } catch (_) {
      _available = false;
    }
    if (_available) _localeId = await _portugueseLocale();
    return _available;
  }

  Future<String?> _portugueseLocale() async {
    final locales = await _speech.locales();
    final ids = {for (final locale in locales) locale.localeId.replaceAll('-', '_').toLowerCase(): locale.localeId};
    return ids['pt_br'] ?? ids.entries.where((e) => e.key.startsWith('pt')).map((e) => e.value).firstOrNull;
  }
}
