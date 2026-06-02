import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base_url.dart';

class ChatApiException implements Exception {
  final String message;

  const ChatApiException(this.message);

  @override
  String toString() => message;
}

class ChatApiService {
  ChatApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? defaultLocalApiBaseUrl();

  final http.Client _client;
  final String baseUrl;

  Future<String> ask({
    required String notes,
    required String transcript,
    required String history,
    required String question,
  }) async {
    final response = await _client
        .post(
          _uri('/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'notes': notes,
            'transcript': transcript,
            'history': history,
            'question': question,
          }),
        )
        .timeout(const Duration(minutes: 2));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatApiException(_extractErrorMessage(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ChatApiException('Chat response must be a JSON object.');
    }

    final answer = decoded['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const ChatApiException('Chat response is missing answer.');
    }

    return answer.trim();
  }

  void dispose() {
    _client.close();
  }

  Uri _uri(String path) {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalizedBaseUrl$path');
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return 'Chat request failed (${response.statusCode}): $detail';
        }
      }
    } catch (_) {
      // Fall back to the raw HTTP response below.
    }

    final body = response.body.trim();
    if (body.isNotEmpty) {
      return 'Chat request failed (${response.statusCode}): $body';
    }

    return 'Chat request failed (${response.statusCode}).';
  }
}
