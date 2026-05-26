import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'speech_service.dart' show TranscriptChunk;

class GeminiSpeechService {
  WebSocketChannel? _channel;
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _audioStreamSubscription;

  bool isListening = false;
  List<TranscriptChunk> chunks = [];
  DateTime? _currentChunkStartTime;
  String currentWords = '';

  final Function(String text, bool isListening) onUpdate;
  final Function(String errorMsg) onError;
  final Function(double level)? onSoundLevelChange;
  final Function(List<TranscriptChunk> chunks)? onChunkSaved;

  // Track if we are currently handling a turn from the model
  bool _handlingTurn = false;

  GeminiSpeechService({
    required this.onUpdate,
    required this.onError,
    this.onSoundLevelChange,
    this.onChunkSaved,
  });

  Future<bool> initialize() async {
    final status = await [Permission.microphone].request();
    return status[Permission.microphone] == PermissionStatus.granted;
  }

  Future<String> _getGeminiKey() async {
    final possibleIps = [
      '10.0.2.2',         // Android Emulator
      '172.21.182.159',   // Physical Device on Wi-Fi (Host IP)
      '127.0.0.1',        // Windows/Mac Desktop App
      'localhost',        // iOS Simulator
    ];

    for (String ip in possibleIps) {
      try {
        final response = await http.get(Uri.parse('http://$ip:5001/api/gemini-token'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['key'];
        }
      } catch (_) {
        // Ignore and try the next IP
      }
    }
    throw Exception('Failed to load Gemini key from any local IP. Make sure gemini_app.py is running.');
  }

  Future<void> toggleListening() async {
    if (isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (isListening) return;

    try {
      final apiKey = await _getGeminiKey();
      final wsUrl = Uri.parse('wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$apiKey');
      
      _channel = WebSocketChannel.connect(wsUrl);
      
      // Send Setup Message
      _channel!.sink.add(jsonEncode({
        "setup": {
          "model": "models/gemini-2.0-flash-exp",
          "generationConfig": {
            "responseModalities": ["TEXT"]
          },
          "systemInstruction": {
            "parts": [
              {
                "text": "You are a highly accurate, real-time speech-to-text transcriber. The user will speak in English, Traditional Chinese, or a mix of both. Your ONLY job is to output the exact words the user says. Do not converse. Do not add filler words. Do not translate unless instructed. Just transcribe."
              }
            ]
          }
        }
      }));

      // Listen to WebSocket
      _channel!.stream.listen(
        (message) {
          if (message is String) {
            _handleWebSocketMessage(message);
          }
        },
        onError: (error) {
          _stopListening();
          onError('WebSocket Error: $error');
        },
        onDone: () {
          _stopListening();
        },
      );

      // Start Audio Recording (16kHz PCM 16-bit Mono)
      if (await _audioRecorder.hasPermission()) {
        final audioStream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );
        
        isListening = true;
        _currentChunkStartTime = DateTime.now();
        onUpdate(_getCombinedText(), isListening);

        _audioStreamSubscription = audioStream.listen((data) {
          // Send audio chunks to Gemini
          if (_channel != null) {
            _channel!.sink.add(jsonEncode({
              "realtimeInput": {
                "mediaChunks": [
                  {
                    "mimeType": "audio/pcm;rate=16000",
                    "data": base64Encode(data)
                  }
                ]
              }
            }));
            
            // Very simple sound level calculation for the UI
            if (onSoundLevelChange != null && data.isNotEmpty) {
              double level = 0.0;
              for (int i = 0; i < data.length; i += 2) {
                // Approximate RMS or peak
                level += data[i].abs();
              }
              level = level / data.length;
              onSoundLevelChange!(level.clamp(0.0, 50.0));
            }
          }
        });
      }
    } catch (e) {
      onError('Failed to start Gemini Live: $e');
    }
  }

  void _handleWebSocketMessage(String messageStr) {
    try {
      final data = jsonDecode(messageStr);
      
      if (data.containsKey('serverContent')) {
        final serverContent = data['serverContent'];
        
        if (serverContent.containsKey('modelTurn')) {
          final parts = serverContent['modelTurn']['parts'] as List;
          for (var part in parts) {
            if (part.containsKey('text')) {
              if (!_handlingTurn) {
                _handlingTurn = true;
                if (currentWords.isNotEmpty && _currentChunkStartTime != null) {
                  _flushChunk();
                }
                _currentChunkStartTime = DateTime.now();
              }
              currentWords += part['text'];
              onUpdate(_getCombinedText(), isListening);
            }
          }
        }
        
        if (serverContent['turnComplete'] == true) {
          _handlingTurn = false;
          _flushChunk();
        }
      }
    } catch (e) {
      print('Error parsing WebSocket message: $e');
    }
  }

  void _flushChunk() {
    if (currentWords.isNotEmpty && _currentChunkStartTime != null) {
      chunks.add(TranscriptChunk(
        startTime: _currentChunkStartTime!,
        endTime: DateTime.now(),
        text: currentWords.trim(),
      ));
      currentWords = '';
      onChunkSaved?.call(chunks);
    }
    _currentChunkStartTime = DateTime.now();
    onUpdate(_getCombinedText(), isListening);
  }

  Future<void> _stopListening() async {
    isListening = false;
    _handlingTurn = false;
    
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    
    await _audioRecorder.stop();
    
    _channel?.sink.close();
    _channel = null;

    _flushChunk();
    onSoundLevelChange?.call(0.0);
  }

  String _getCombinedText() {
    final chunksText = chunks.map((c) => c.text).join(' ');
    if (chunksText.isEmpty) return currentWords.trim();
    if (currentWords.isEmpty) return chunksText.trim();
    return '${chunksText.trim()} ${currentWords.trim()}'.trim();
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

  void setLocale(String localeId) {
    // Gemini automatically detects the language (English/Chinese mix),
    // so we don't strictly need to do anything here, but we implement
    // the method to maintain compatibility with the UI.
  }
}
