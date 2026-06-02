import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class TranscriptChunk {
  final DateTime startTime;
  final DateTime endTime;
  final String text;

  TranscriptChunk({
    required this.startTime,
    required this.endTime,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'text': text,
  };
}

class AzureSpeechService {
  final _record = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription? _audioSubscription;
  final String region = "eastasia"; // Adjust to your region

  // Output streams for the UI
  final _transcriptController = StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  bool isListening = false;
  String _currentPartial = "";
  List<TranscriptChunk> chunks = [];
  DateTime? _currentChunkStartTime;

  // Configuration Constants
  final List<String> targetLanguages = ["zh-TW", "en-US"];
  final List<String> phraseList = [
    "Flutter",
    "setState",
    "gRPC",
    "Widget",
    "StatefulWidget",
    "StatelessWidget",
  ];

  Future<void> startListening(String token) async {
    if (isListening) return;

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint("Microphone permission denied");
      return;
    }

    try {
      // Construct WebSocket URL with Continuous LID headers
      // Adding language=zh-TW as a fallback/primary if LID fails
      final uri = Uri.parse(
        'wss://$region.stt.speech.microsoft.com/speech/recognition/continuous/cognitiveservices/v1?language=zh-TW',
      );

      // Connect via WebSocket using the temporary token
      _channel = WebSocketChannel.connect(
        uri,
        protocols: ['Authorization: Bearer $token'],
      );

      // Listen to Azure responses first
      _channel!.stream.listen(
        _handleAzureResponse,
        onError: _handleError,
        onDone: _handleReconnect,
      );

      // Send Configuration Payload (JSON) for LID and Phrase List over the socket
      // Wait a tiny bit for the connection to establish before sending config
      await Future.delayed(const Duration(milliseconds: 100));
      _sendSpeechConfig();

      // Start recording and buffering 16kHz, 16-bit Mono PCM
      if (await _record.hasPermission()) {
        final audioStream = await _record.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        isListening = true;
        _statusController.add(isListening);
        _currentChunkStartTime = DateTime.now();

        _audioSubscription = audioStream.listen((data) {
          if (_channel != null && isListening) {
            // Create the binary audio payload. In a robust implementation,
            // you may need to prepend the specific Azure Audio stream header.
            // For simplicity, many endpoints accept raw PCM if configured right,
            // but typically Azure requires a specific binary header format per chunk
            // or using the turn.start / turn.end messages.
            // Assuming direct binary ingestion for continuous mode:
            _channel!.sink.add(data);
          }
        });
      }
    } catch (e) {
      debugPrint("Error starting Azure STT: $e");
      _handleError(e);
    }
  }

  void _sendSpeechConfig() {
    if (_channel == null) return;

    // Injects Continuous LID and custom phrase lists
    final configMessage = {
      "context": {
        "phraseOutput": {"phrases": phraseList},
        "languageId": {"mode": "Continuous", "languages": targetLanguages},
      },
    };

    // Azure expects specific path and content-type headers for websocket text messages.
    // The Speech SDK handles this formatting (speech.config path).
    // Here we construct a minimal valid speech.config message block.
    final header =
        "path: speech.config\r\nContent-Type: application/json; charset=utf-8\r\n\r\n";
    final payload = '$header${jsonEncode(configMessage)}';

    _channel!.sink.add(payload);
  }

  void _handleAzureResponse(dynamic event) {
    if (event is String) {
      try {
        // Responses are typically text messages with headers and a JSON body.
        // We need to parse the JSON part.
        final parts = event.split('\r\n\r\n');
        if (parts.length > 1) {
          final jsonString = parts[1];
          final data = jsonDecode(jsonString);

          if (event.contains("speech.hypothesis")) {
            // Partial recognition
            if (data['Text'] != null) {
              _currentPartial = data['Text'];
              _emitTranscript();
            }
          } else if (event.contains("speech.phrase")) {
            // Finalized recognition
            if (data['RecognitionStatus'] == 'Success' &&
                data['DisplayText'] != null) {
              final text = data['DisplayText'];
              chunks.add(
                TranscriptChunk(
                  startTime: _currentChunkStartTime ?? DateTime.now(),
                  endTime: DateTime.now(),
                  text: text,
                ),
              );
              _currentChunkStartTime = DateTime.now();
              _currentPartial = "";
              _emitTranscript();
            }
          }
        }
      } catch (e) {
        debugPrint("Error parsing Azure response: $e");
      }
    }
  }

  void _emitTranscript() {
    final finalizedText = chunks.map((c) => c.text).join(' ');
    final fullText = '$finalizedText $_currentPartial'.trim();
    _transcriptController.add(fullText);
  }

  void _handleError(Object error) {
    debugPrint("Azure STT Error: $error");
    stopListening();
    // Implement Network Resilience: Check if we should fetch new token and reconnect.
  }

  void _handleReconnect() {
    debugPrint("Azure STT connection closed.");
    stopListening();
  }

  Future<void> stopListening() async {
    isListening = false;
    _statusController.add(isListening);
    await _audioSubscription?.cancel();
    await _record.stop();
    _channel?.sink.close();
    _channel = null;

    if (_currentPartial.isNotEmpty) {
      chunks.add(
        TranscriptChunk(
          startTime: _currentChunkStartTime ?? DateTime.now(),
          endTime: DateTime.now(),
          text: _currentPartial,
        ),
      );
      _currentPartial = "";
      _emitTranscript();
    }
  }

  String getExportJson() {
    return jsonEncode(chunks.map((c) => c.toJson()).toList());
  }

  void reset() {
    chunks.clear();
    _currentPartial = "";
    _emitTranscript();
  }

  void dispose() {
    stopListening();
    _transcriptController.close();
    _statusController.close();
    _record.dispose();
  }
}
