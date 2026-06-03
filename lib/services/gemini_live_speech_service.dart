import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class TranscriptChunk {
  final DateTime startTime;
  final DateTime endTime;
  final String text;

  TranscriptChunk({
    required this.startTime,
    required this.endTime,
    required this.text,
  });

  factory TranscriptChunk.fromJson(Map<String, dynamic> json) {
    final startTimeRaw = json['startTime'];
    final endTimeRaw = json['endTime'];
    if (startTimeRaw is! String || endTimeRaw is! String) {
      throw const FormatException('Transcript chunk is missing timestamps.');
    }

    return TranscriptChunk(
      startTime: DateTime.parse(startTimeRaw),
      endTime: DateTime.parse(endTimeRaw),
      text: json['text']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'text': text,
  };
}

class GeminiLiveSpeechService {
  final AudioRecorder _record = AudioRecorder();

  LiveSession? _session;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _receiveSubscription;

  bool isListening = false;
  bool _shouldListen = false;
  bool _isAudioStreaming = false; // Tracks if audio recorder is active
  bool _isReconnecting = false; // Prevents reconnect storms

  List<TranscriptChunk> chunks = [];
  DateTime? _currentChunkStartTime;
  String _currentTurnWords = '';
  String? _storageId;
  double confidence = 1.0;
  String currentLocaleId = 'en_US';

  // Callbacks
  final Function(String text, bool isListening) onUpdate;
  final Function(String errorMsg) onError;
  final Function(double level)? onSoundLevelChange;
  final Function(String filePath)? onSaved;

  GeminiLiveSpeechService({
    required this.onUpdate,
    required this.onError,
    this.onSoundLevelChange,
    this.onSaved,
  });

  Future<bool> initialize() async {
    final micStatus = await Permission.microphone.request();
    return micStatus == PermissionStatus.granted;
  }

  void setLocale(String localeId) {
    currentLocaleId = localeId;
    if (isListening) {
      _scheduleReconnect();
    }
  }

  String _getSystemInstruction() {
    final langName = currentLocaleId == 'zh_TW'
        ? 'Traditional Chinese (zh-TW)'
        : 'English (en-US)';
    return 'You are a real-time speech-to-text transcriber for a classroom lecture. '
        'Verbatim output only. Do not reply to the content, do not answer questions, '
        'do not add introductory or explanatory text. Just transcribe what you hear '
        'exactly, word-for-word. Transcribe primarily in $langName, or the language '
        'spoken. Keep punctuation natural and clean.';
  }

  Future<void> _connectSession() async {
    try {
      // Use FirebaseAI.googleAI() — credentials from google-services.json, no API key needed.
      final model = FirebaseAI.googleAI().liveGenerativeModel(
        model: 'gemini-2.5-flash-native-audio-preview-12-2025',
        liveGenerationConfig: LiveGenerationConfig(
          responseModalities: [
            ResponseModalities.audio,
            ResponseModalities.text,
          ],
        ),
        systemInstruction: Content.system(_getSystemInstruction()),
      );

      debugPrint('[GeminiLive] Connecting...');
      _session = await model.connect();
      debugPrint('[GeminiLive] Session connected successfully.');

      // Reset reconnecting flag now that we have a live session
      _isReconnecting = false;

      // Listen to server responses — audio keeps running independently of session reconnects
      _receiveSubscription?.cancel();
      _receiveSubscription = _session!.receive().listen(
        _handleServerResponse,
        onError: (err) {
          debugPrint('[GeminiLive] Receive stream error: $err');
          onError('Live API error: $err');
          _scheduleReconnect();
        },
        onDone: () {
          // Session ended — could be server timeout, model rejection, or graceful close
          final closeCode = _session?.toString() ?? 'unknown';
          debugPrint(
            '[GeminiLive] Receive stream ended (session closed). $closeCode',
          );
          if (_shouldListen) {
            _scheduleReconnect();
          } else {
            isListening = false;
            onSoundLevelChange?.call(0.0);
            onUpdate(_getCombinedText(), isListening);
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[GeminiLive] Session connection failed: $e');
      onError('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _handleServerResponse(LiveServerResponse response) {
    final message = response.message;

    if (message is LiveServerContent) {
      // Extract text from model turn
      final modelTurn = message.modelTurn;
      if (modelTurn != null) {
        for (final part in modelTurn.parts) {
          if (part is TextPart) {
            _currentTurnWords += part.text;
          }
        }
      }

      final turnComplete = message.turnComplete ?? false;
      final interrupted = message.interrupted ?? false;

      if (turnComplete || interrupted) {
        _finalizeActiveChunk();
      }

      onUpdate(_getCombinedText(), isListening);
    } else if (message is LiveServerToolCall) {
      // Ignore function calls for transcription use case
      debugPrint('[GeminiLive] Tool call received (ignored).');
    } else {
      // LiveServerSetupComplete, GoingAwayNotice, SessionResumptionUpdate, etc.
      debugPrint('[GeminiLive] Other message: ${message.runtimeType}');
    }
  }

  void _finalizeActiveChunk() {
    final cleanWords = _currentTurnWords.trim();
    if (cleanWords.isNotEmpty) {
      chunks.add(
        TranscriptChunk(
          startTime: _currentChunkStartTime ?? DateTime.now(),
          endTime: DateTime.now(),
          text: cleanWords,
        ),
      );
      _currentTurnWords = '';
      _currentChunkStartTime = DateTime.now();

      final storageId = _storageId;
      if (storageId != null) {
        saveTranscript(storageId);
      }
    }
  }

  void _calculateSoundLevel(Uint8List data) {
    if (data.isEmpty || onSoundLevelChange == null) return;

    double sum = 0.0;
    final sampleCount = data.length ~/ 2;
    if (sampleCount == 0) return;

    for (int i = 0; i < data.length - 1; i += 2) {
      final low = data[i];
      final high = data[i + 1];
      int sample = (high << 8) | low;
      if (sample >= 32768) sample -= 65536;
      sum += sample.abs();
    }

    final average = sum / sampleCount;
    final level = (average / 32767.0) * 100.0;
    onSoundLevelChange?.call(level);
  }

  /// Schedule a session reconnect without touching the audio stream.
  /// Audio keeps running — only the WebSocket session reconnects.
  void _scheduleReconnect() {
    if (_isReconnecting || !_shouldListen) return;
    _isReconnecting = true;
    debugPrint('[GeminiLive] Scheduling reconnect in 3s...');
    Future.delayed(const Duration(seconds: 3), () async {
      if (!_shouldListen) {
        _isReconnecting = false;
        return;
      }
      await _closeSessionOnly();
      await _connectSession();
      // Audio is already streaming — no need to restart it
    });
  }

  /// Close only the session/WebSocket, NOT the audio recorder.
  Future<void> _closeSessionOnly() async {
    await _receiveSubscription?.cancel();
    _receiveSubscription = null;
    try {
      await _session?.close();
    } catch (_) {}
    _session = null;
  }

  void toggleListening() {
    if (!isListening && !_shouldListen) {
      _shouldListen = true;
      _startListening();
    } else {
      _shouldListen = false;
      isListening = false;
      _isAudioStreaming = false;
      _isReconnecting = false;
      onSoundLevelChange?.call(0.0);
      _audioSubscription?.cancel();
      _audioSubscription = null;
      _record.stop();
      _finalizeActiveChunk();
      _closeSessionOnly();
      onUpdate(_getCombinedText(), isListening);
    }
  }

  Future<void> _startListening() async {
    _currentChunkStartTime = DateTime.now();
    _currentTurnWords = '';
    _isReconnecting = false;

    // Start audio first — it runs independently of the session
    await _startAudioStream();

    // Then connect the session
    await _connectSession();
  }

  Future<void> _startAudioStream() async {
    if (_isAudioStreaming) return; // Already recording, don't double-start
    try {
      if (await _record.hasPermission()) {
        final audioStream = await _record.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        _isAudioStreaming = true;
        isListening = true;
        onUpdate(_getCombinedText(), isListening);
        debugPrint('[GeminiLive] Audio stream started.');

        _audioSubscription = audioStream.listen((data) {
          if (!_shouldListen) return;

          _calculateSoundLevel(data);

          // Only send if session is alive; if not, drop the chunk (session will reconnect)
          final session = _session;
          if (session != null) {
            session
                .sendAudioRealtime(InlineDataPart('audio/pcm;rate=16000', data))
                .catchError((e) {
                  debugPrint(
                    '[GeminiLive] Audio send error (session may be reconnecting): $e',
                  );
                });
          }
        });
      } else {
        onError('Microphone permission denied.');
      }
    } catch (e) {
      _isAudioStreaming = false;
      debugPrint('[GeminiLive] Error starting audio capture: $e');
      onError('Failed to capture audio: $e');
    }
  }

  String _getCombinedText() {
    final finalized = chunks.map((c) => c.text).join('\n\n').trim();
    final active = _currentTurnWords.trim();
    if (finalized.isEmpty) return active;
    if (active.isEmpty) return finalized;
    return '$finalized\n\n$active';
  }

  String getExportJson() {
    final allChunks = List<TranscriptChunk>.from(chunks);
    if (_currentTurnWords.trim().isNotEmpty) {
      allChunks.add(
        TranscriptChunk(
          startTime: _currentChunkStartTime ?? DateTime.now(),
          endTime: DateTime.now(),
          text: _currentTurnWords.trim(),
        ),
      );
    }
    return jsonEncode(allChunks.map((c) => c.toJson()).toList());
  }

  Future<String?> loadSavedTranscript(String storageId) async {
    _storageId = storageId;

    try {
      final file = await _getTranscriptFile(storageId);
      if (!await file.exists()) {
        chunks.clear();
        _currentTurnWords = '';
        onUpdate('', isListening);
        return null;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        throw const FormatException('Saved transcript JSON must be a list.');
      }

      chunks = decoded
          .map(
            (item) => TranscriptChunk.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((chunk) => chunk.text.trim().isNotEmpty)
          .toList();
      _currentTurnWords = '';
      onUpdate(_getCombinedText(), isListening);
      return file.path;
    } catch (e) {
      onError('Failed to load saved transcript: $e');
      return null;
    }
  }

  Future<String?> saveTranscript(String storageId) async {
    _storageId = storageId;

    try {
      final file = await _getTranscriptFile(storageId);
      await file.writeAsString(getExportJson());
      onSaved?.call(file.path);
      return file.path;
    } catch (e) {
      onError('Failed to save transcript: $e');
      return null;
    }
  }

  Future<File> _getTranscriptFile(String storageId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final transcriptsDir = Directory(p.join(appDir.path, 'transcripts'));
    await transcriptsDir.create(recursive: true);

    return File(
      p.join(transcriptsDir.path, '${_safeStorageId(storageId)}.json'),
    );
  }

  String _safeStorageId(String storageId) {
    return storageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  void reset() {
    chunks.clear();
    _currentTurnWords = '';
    onSoundLevelChange?.call(0.0);
    onUpdate('', isListening);
  }

  void dispose() {
    _shouldListen = false;
    isListening = false;
    _isAudioStreaming = false;
    _isReconnecting = false;
    _audioSubscription?.cancel();
    _record.dispose();
    _closeSessionOnly();
  }
}
