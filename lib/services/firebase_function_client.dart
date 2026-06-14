import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class FirebaseFunctionException implements Exception {
  const FirebaseFunctionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class FirebaseFunctionClient {
  FirebaseFunctionClient({
    http.Client? client,
    String? baseUrl,
    String? projectId,
    String? region,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? _configuredBaseUrl,
       _projectId = projectId ?? _configuredProjectId,
       _region = region ?? _configuredRegion;

  static const _configuredBaseUrl = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_BASE_URL',
  );
  static const _configuredProjectId = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_PROJECT_ID',
  );
  static const _configuredRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );

  final http.Client _client;
  final String _baseUrl;
  final String _projectId;
  final String _region;

  Future<Map<String, dynamic>> postJson({
    required String functionName,
    required Map<String, dynamic> body,
    String overrideUrl = '',
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final uri = resolveUri(
      functionName: functionName,
      overrideUrl: overrideUrl,
    );

    final headers = <String, String>{'Content-Type': 'application/json'};
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final response = await _client
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseFunctionException(
        _extractErrorMessage(response),
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FirebaseFunctionException(
        'Firebase Function response must be a JSON object.',
      );
    }

    return Map<String, dynamic>.from(decoded);
  }

  Uri resolveUri({required String functionName, String overrideUrl = ''}) {
    if (overrideUrl.isNotEmpty) {
      return Uri.parse(overrideUrl);
    }

    if (_baseUrl.isNotEmpty) {
      final normalized = _baseUrl.endsWith('/')
          ? _baseUrl.substring(0, _baseUrl.length - 1)
          : _baseUrl;
      return Uri.parse('$normalized/$functionName');
    }

    final projectId = _projectId.isNotEmpty
        ? _projectId
        : Firebase.app().options.projectId;
    return Uri.https('$_region-$projectId.cloudfunctions.net', functionName);
  }

  static Map<String, dynamic> unwrapPayload(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map) return Map<String, dynamic>.from(data);

    final result = response['result'];
    if (result is Map) return Map<String, dynamic>.from(result);

    return response;
  }

  void dispose() {
    _client.close();
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] ?? decoded['error'];
        if (message is String && message.trim().isNotEmpty) {
          return 'Firebase Function failed (${response.statusCode}): $message';
        }

        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return 'Firebase Function failed (${response.statusCode}): $detail';
        }
      }
    } catch (_) {
      // Fall back to the raw body below.
    }

    final body = response.body.trim();
    if (body.isNotEmpty) {
      return 'Firebase Function failed (${response.statusCode}): $body';
    }

    return 'Firebase Function failed (${response.statusCode}).';
  }
}
