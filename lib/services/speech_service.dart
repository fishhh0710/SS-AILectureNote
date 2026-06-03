import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool isListening = false;
  bool _shouldListen = false;

  List<TranscriptChunk> chunks = [];
  DateTime? _currentChunkStartTime;
  String? _storageId;
  String currentWords = '';
  double confidence = 1.0;
  String currentLocaleId = 'en_US';

  // Callbacks
  final Function(String text, bool isListening) onUpdate;
  final Function(String errorMsg) onError;
  final Function(double level)? onSoundLevelChange;
  final Function(String filePath)? onSaved;

  SpeechService({
    required this.onUpdate,
    required this.onError,
    this.onSoundLevelChange,
    this.onSaved,
  });

  Future<bool> initialize() async {
    await [Permission.microphone, Permission.speech].request();
    return await _speech.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
    );
  }

  void _handleStatus(String val) {
    if (val == 'done' || val == 'notListening') {
      isListening = false;
      onSoundLevelChange?.call(0.0);
      _currentChunkStartTime = null;
      currentWords = '';
      onUpdate(_getCombinedText(), isListening);
      final storageId = _storageId;
      if (storageId != null) {
        saveTranscript(storageId);
      }

      if (_shouldListen) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_shouldListen) _startListening();
        });
      }
    }
  }

  void _handleError(dynamic val) {
    isListening = false;
    onSoundLevelChange?.call(0.0);

    // In continuous listening mode (e.g. whole class recording),
    // the system might throw timeout errors (sometimes marked as permanent)
    // when there is a long pause in speech. We should ignore them and restart.

    String errorMsg = val.toString();
    if (errorMsg.contains('error_audio_error') ||
        errorMsg.contains('error_permission')) {
      // Only abort on actual hardware or permission errors
      _shouldListen = false;
      onError("Microphone/Permission error. Recording stopped.");
      return;
    }

    // Otherwise, for timeouts or network blips, keep trying to restart!
    if (_shouldListen) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_shouldListen) _startListening();
      });
    }
  }

  void toggleListening() {
    if (!isListening && !_shouldListen) {
      _shouldListen = true;
      _startListening();
    } else {
      _shouldListen = false;
      isListening = false;
      onSoundLevelChange?.call(0.0);
      _speech.stop();
      onUpdate(_getCombinedText(), isListening);
    }
  }

  void setLocale(String localeId) {
    currentLocaleId = localeId;
    if (isListening) {
      toggleListening();
      Future.delayed(const Duration(milliseconds: 300), toggleListening);
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
    );
    if (available && _shouldListen) {
      isListening = true;
      _currentChunkStartTime = DateTime.now();
      currentWords = '';
      onUpdate(_getCombinedText(), isListening);
      _speech.listen(
        onResult: (val) {
          currentWords = val.recognizedWords;
          if (val.hasConfidenceRating && val.confidence > 0) {
            confidence = val.confidence;
          }

          // When the recognizer finalizes a sentence within a session,
          // immediately save it as a chunk so the next partial result
          // appends rather than overwrites it.
          if (val.finalResult && currentWords.trim().isNotEmpty) {
            chunks.add(
              TranscriptChunk(
                startTime: _currentChunkStartTime ?? DateTime.now(),
                endTime: DateTime.now(),
                text: currentWords.trim(),
              ),
            );
            currentWords = '';
            _currentChunkStartTime = DateTime.now();
          }

          onUpdate(_getCombinedText(), isListening);
        },
        onSoundLevelChange: (level) {
          onSoundLevelChange?.call(level);
        },
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          localeId: currentLocaleId,
          listenFor: const Duration(hours: 24),
          pauseFor: const Duration(hours: 24),
        ),
      );
    }
  }

  String _getCombinedText() {
    return chunks.map((c) => c.text).join('\n\n').trim();
  }

  String getExportJson() {
    return jsonEncode(chunks.map((c) => c.toJson()).toList());
  }

  Future<String?> loadSavedTranscript(String storageId) async {
    _storageId = storageId;

    try {
      final file = await _getTranscriptFile(storageId);
      if (!await file.exists()) {
        chunks.clear();
        currentWords = '';
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
      currentWords = '';
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
    currentWords = '';
    onSoundLevelChange?.call(0.0);
    onUpdate('', isListening);
  }
}
