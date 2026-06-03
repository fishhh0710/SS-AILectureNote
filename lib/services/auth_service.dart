import 'package:flutter/foundation.dart';

import 'firebase_function_client.dart';

class AzureAuthService {
  AzureAuthService({FirebaseFunctionClient? functionClient})
    : _functionClient = functionClient ?? FirebaseFunctionClient();

  static const _functionName = String.fromEnvironment(
    'FIREBASE_AZURE_TOKEN_FUNCTION_NAME',
    defaultValue: 'azureSpeechToken',
  );
  static const _functionUrl = String.fromEnvironment(
    'FIREBASE_AZURE_TOKEN_FUNCTION_URL',
  );

  final FirebaseFunctionClient _functionClient;

  Future<String> getTemporaryToken() async {
    try {
      final response = await _functionClient.postJson(
        functionName: _functionName,
        overrideUrl: _functionUrl,
        body: const {},
      );
      final payload = FirebaseFunctionClient.unwrapPayload(response);
      final token = payload['token'];
      if (token is String && token.isNotEmpty) {
        return token;
      }

      throw const FirebaseFunctionException(
        'Azure token Firebase Function response is missing token.',
      );
    } catch (e) {
      debugPrint('Error fetching Azure token: $e');
      rethrow;
    }
  }

  void dispose() {
    _functionClient.dispose();
  }
}
