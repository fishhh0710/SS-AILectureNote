import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
    return TranscriptChunk(
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      text: json['text']?.toString() ?? '',
    );
  }

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
  Future<void>? _stopFuture;
  bool _recorderStarted = false;
  bool _disposed = false;
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
  String currentLocaleId = 'zh-TW';

  // Unique request ID per session (Azure requires this)
  String _requestId = '';
  bool _sentWavHeader = false;

  void setLocale(String localeId) {
    currentLocaleId = localeId == 'zh_TW' ? 'zh-TW' : 'en-US';
  }

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
    if (isListening || _disposed) return;

    debugPrint("[AzureSTT] startListening called");

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint("[AzureSTT] Microphone permission denied");
      return;
    }
    debugPrint("[AzureSTT] Microphone permission granted");

    try {
      _requestId = const Uuid().v4().replaceAll('-', '');
      _sentWavHeader = false;
      debugPrint("[AzureSTT] Request ID: $_requestId");

      // Construct WebSocket URL
      final uri = Uri.parse(
        'wss://$region.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=$currentLocaleId',
      );
      debugPrint("[AzureSTT] Connecting to: $uri");

      // Connect via WebSocket using the temporary token
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'X-ConnectionId': _requestId,
        },
      );

      // Wait for connection to be ready
      try {
        await _channel!.ready;
        debugPrint("[AzureSTT] WebSocket connection ready!");
      } catch (e) {
        debugPrint("[AzureSTT] WebSocket connection FAILED: $e");
        _handleError(e);
        return;
      }

      // Listen to Azure responses
      _channel!.stream.listen(
        (event) {
          debugPrint("[AzureSTT] Received message (${event.runtimeType}): ${event is String ? (event.length > 200 ? '${event.substring(0, 200)}...' : event) : 'binary ${(event as List).length} bytes'}");
          _handleAzureResponse(event);
        },
        onError: (error) {
          debugPrint("[AzureSTT] Stream error: $error");
          _handleError(error);
        },
        onDone: () {
          debugPrint("[AzureSTT] Stream done (closeCode=${_channel?.closeCode}, closeReason=${_channel?.closeReason})");
          _handleReconnect();
        },
      );

      // Send speech.config message
      _sendSpeechConfig();
      debugPrint("[AzureSTT] speech.config sent");

      // Start recording and buffering 16kHz, 16-bit Mono PCM
      if (await _record.hasPermission()) {
        debugPrint("[AzureSTT] Starting audio stream...");
        final audioStream = await _record.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        _recorderStarted = true;
        if (_disposed) {
          await _record.stop();
          _recorderStarted = false;
          return;
        }
        isListening = true;
        _statusController.add(isListening);
        _currentChunkStartTime = DateTime.now();
        debugPrint("[AzureSTT] Audio stream started, isListening=true");

        int audioChunkCount = 0;
        _audioSubscription = audioStream.listen((data) {
          if (_channel != null && isListening) {
            audioChunkCount++;
            // Send audio as binary with proper Azure framing
            _sendAudioChunk(Uint8List.fromList(data));
            if (audioChunkCount <= 3 || audioChunkCount % 50 == 0) {
              debugPrint("[AzureSTT] Sent audio chunk #$audioChunkCount, size=${data.length} bytes");
            }
          }
        });
      } else {
        debugPrint("[AzureSTT] record.hasPermission() returned false");
      }
    } catch (e) {
      debugPrint("[AzureSTT] Error starting Azure STT: $e");
      _handleError(e);
    }
  }

  /// Build and send the RIFF WAV header for the audio stream.
  /// Azure requires audio to start with this header when sending raw PCM.
  Uint8List _buildWavHeader() {
    // For streaming, we use a very large data size placeholder
    const int sampleRate = 16000;
    const int numChannels = 1;
    const int bitsPerSample = 16;
    const int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    const int blockAlign = numChannels * (bitsPerSample ~/ 8);
    // Use 0 for streaming (unknown length)
    const int dataSize = 0;
    const int chunkSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);   // PCM sub-chunk size
    header.setUint16(20, 1, Endian.little);    // PCM format
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    return header.buffer.asUint8List();
  }

  /// Send an audio chunk with the proper Azure binary framing.
  ///
  /// Azure binary message format:
  ///   [2 bytes: header length (big-endian UInt16)]
  ///   [N bytes: text header (ASCII)]
  ///   [remaining bytes: audio payload]
  void _sendAudioChunk(Uint8List pcmData) {
    if (_channel == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    // Build the text header for audio messages
    final textHeader =
        "Path: audio\r\n"
        "X-RequestId: $_requestId\r\n"
        "X-Timestamp: $now\r\n"
        "Content-Type: audio/x-wav\r\n";

    final headerBytes = utf8.encode(textHeader);
    final headerLength = headerBytes.length;

    // For the first chunk, prepend the WAV header to the audio payload
    Uint8List audioPayload;
    if (!_sentWavHeader) {
      _sentWavHeader = true;
      final wavHeader = _buildWavHeader();
      audioPayload = Uint8List(wavHeader.length + pcmData.length);
      audioPayload.setAll(0, wavHeader);
      audioPayload.setAll(wavHeader.length, pcmData);
      debugPrint("[AzureSTT] First audio message: WAV header (${wavHeader.length}B) + PCM (${pcmData.length}B)");
    } else {
      audioPayload = pcmData;
    }

    // Assemble the full binary frame:
    //   2 bytes (header length, big-endian) + header bytes + audio bytes
    final frame = Uint8List(2 + headerLength + audioPayload.length);
    // Write header length as big-endian UInt16
    frame[0] = (headerLength >> 8) & 0xFF;
    frame[1] = headerLength & 0xFF;
    // Write text header
    frame.setRange(2, 2 + headerLength, headerBytes);
    // Write audio payload
    frame.setRange(2 + headerLength, frame.length, audioPayload);

    _channel!.sink.add(frame);
  }


  void _sendSpeechConfig() {
    if (_channel == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    // speech.config message
    final configMessage = {
      "context": {
        "system": {
          "version": "1.0.0",
        },
        "os": {
          "platform": "Android",
          "name": "Android",
          "version": "14",
        },
        "audio": {
          "source": {
            "microphone": {},
          },
        },
        "phraseOutput": {"phrases": phraseList},
        "languageId": {"mode": "Continuous", "languages": targetLanguages},
      },
    };

    final configHeader =
        "Path: speech.config\r\nX-RequestId: $_requestId\r\nX-Timestamp: $now\r\nContent-Type: application/json; charset=utf-8\r\n\r\n";
    final configPayload = '$configHeader${jsonEncode(configMessage)}';

    _channel!.sink.add(configPayload);
  }

  void _handleAzureResponse(dynamic event) {
    if (event is String) {
      try {
        // Responses are typically text messages with headers and a JSON body.
        // We need to parse the JSON part.
        final parts = event.split('\r\n\r\n');
        if (parts.length > 1) {
          final jsonString = parts.sublist(1).join('\r\n\r\n');
          
          // Check if there's actually JSON content
          if (jsonString.trim().isEmpty) {
            debugPrint("[AzureSTT] Received message with empty body, headers: ${parts[0]}");
            return;
          }

          final data = jsonDecode(jsonString);

          if (event.contains("speech.hypothesis")) {
            // Partial recognition
            if (data['Text'] != null) {
              _currentPartial = data['Text'];
              debugPrint("[AzureSTT] Hypothesis: $_currentPartial");
              _emitTranscript();
            }
          } else if (event.contains("speech.phrase")) {
            // Finalized recognition
            if (data['RecognitionStatus'] == 'Success' &&
                data['DisplayText'] != null) {
              final text = data['DisplayText'];
              debugPrint("[AzureSTT] Phrase: $text");
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
              if (_storageId != null) {
                saveTranscript(_storageId!);
              }
            } else {
              debugPrint("[AzureSTT] Phrase with status: ${data['RecognitionStatus']}");
            }
          } else if (event.contains("turn.start")) {
            debugPrint("[AzureSTT] turn.start received - Azure is ready for audio");
          } else if (event.contains("turn.end")) {
            debugPrint("[AzureSTT] turn.end received");
          } else if (event.contains("speech.startDetected")) {
            debugPrint("[AzureSTT] speech.startDetected");
          } else if (event.contains("speech.endDetected")) {
            debugPrint("[AzureSTT] speech.endDetected");
          } else {
            debugPrint("[AzureSTT] Other message path in headers: ${parts[0]}");
          }
        } else {
          debugPrint("[AzureSTT] Received message without header/body split: ${event.length > 200 ? '${event.substring(0, 200)}...' : event}");
        }
      } catch (e) {
        debugPrint("[AzureSTT] Error parsing Azure response: $e");
      }
    } else {
      debugPrint("[AzureSTT] Received binary message: ${(event as List).length} bytes");
    }
  }

  void _emitTranscript() {
    final finalizedText = chunks.map((c) => c.text).join(' ');
    final fullText = '$finalizedText $_currentPartial'.trim();
    _transcriptController.add(fullText);
  }

  void _handleError(Object error) {
    debugPrint("[AzureSTT] Error: $error");
    unawaited(stopListening());
  }

  void _handleReconnect() {
    debugPrint("[AzureSTT] Connection closed.");
    unawaited(stopListening());
  }

  Future<void> stopListening() {
    return _stopFuture ??= _stopListeningInternal().whenComplete(() {
      _stopFuture = null;
    });
  }

  Future<void> _stopListeningInternal() async {
    isListening = false;
    if (!_statusController.isClosed) {
      _statusController.add(isListening);
    }

    final audioSubscription = _audioSubscription;
    _audioSubscription = null;
    await audioSubscription?.cancel();

    if (_recorderStarted) {
      _recorderStarted = false;
      try {
        await _record.stop();
      } catch (error) {
        debugPrint('[AzureSTT] Recorder stop ignored: $error');
      }
    }

    final channel = _channel;
    _channel = null;
    await channel?.sink.close();

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

  String? _storageId;

  String getExportJson() {
    return jsonEncode(chunks.map((c) => c.toJson()).toList());
  }

  void reset() {
    chunks.clear();
    _currentPartial = "";
    _emitTranscript();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_disposeAsync());
  }

  Future<void> _disposeAsync() async {
    await stopListening();
    await _transcriptController.close();
    await _statusController.close();
    await _record.dispose();
  }

  Future<String?> loadSavedTranscript(String storageId) async {
    _storageId = storageId;

    try {
      final file = await _getTranscriptFile(storageId);
      if (!await file.exists()) {
        chunks.clear();
        _currentPartial = '';
        _emitTranscript();
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
      _currentPartial = '';
      _emitTranscript();
      return file.path;
    } catch (e) {
      debugPrint('Failed to load saved transcript: $e');
      return null;
    }
  }

  Future<String?> saveTranscript(String storageId) async {
    _storageId = storageId;

    try {
      final file = await _getTranscriptFile(storageId);
      await file.writeAsString(getExportJson());
      return file.path;
    } catch (e) {
      debugPrint('Failed to save transcript: $e');
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
}
