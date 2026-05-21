import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class TranscriptChunk {
  final DateTime startTime;
  final DateTime endTime;
  final String text;

  TranscriptChunk({required this.startTime, required this.endTime, required this.text});

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
  String currentWords = '';    
  double confidence = 1.0;
  String currentLocaleId = 'en_US';
  
  // Callbacks
  final Function(String text, bool isListening) onUpdate;
  final Function(String errorMsg) onError;
  final Function(double level)? onSoundLevelChange;

  SpeechService({
    required this.onUpdate,
    required this.onError,
    this.onSoundLevelChange,
  });

  Future<bool> initialize() async {
    await [Permission.microphone, Permission.speech].request();
    return await _speech.initialize(onStatus: _handleStatus, onError: _handleError);
  }

  void _handleStatus(String val) {
    if (val == 'done' || val == 'notListening') {
      isListening = false;
      onSoundLevelChange?.call(0.0);
      if (currentWords.isNotEmpty && _currentChunkStartTime != null) {
        chunks.add(TranscriptChunk(
          startTime: _currentChunkStartTime!,
          endTime: DateTime.now(),
          text: currentWords.trim(),
        ));
        currentWords = '';
      }
      onUpdate(_getCombinedText(), isListening);
      
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
    if (errorMsg.contains('error_audio_error') || errorMsg.contains('error_permission')) {
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
    bool available = await _speech.initialize(onStatus: _handleStatus, onError: _handleError);
    if (available && _shouldListen) {
      isListening = true;
      _currentChunkStartTime = DateTime.now();
      _speech.listen(
        onResult: (val) {
          currentWords = val.recognizedWords;
          if (val.hasConfidenceRating && val.confidence > 0) confidence = val.confidence;
          onUpdate(_getCombinedText(), isListening);
        },
        onSoundLevelChange: (level) {
          onSoundLevelChange?.call(level);
        },
        localeId: currentLocaleId,
        listenFor: const Duration(hours: 24),
        pauseFor: const Duration(hours: 24),
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    }
  }

  String _getCombinedText() {
    return (chunks.map((c) => c.text).join(' ') + ' ' + currentWords).trim();
  }

  String getExportJson() {
    return jsonEncode(chunks.map((c) => c.toJson()).toList());
  }

  void reset() {
    chunks.clear();
    currentWords = '';
    onSoundLevelChange?.call(0.0);
    onUpdate('', isListening);
  }
}
