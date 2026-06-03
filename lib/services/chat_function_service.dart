import 'firebase_function_client.dart';

class ChatFunctionException implements Exception {
  const ChatFunctionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatFunctionService {
  ChatFunctionService({FirebaseFunctionClient? functionClient})
    : _functionClient = functionClient ?? FirebaseFunctionClient();

  static const _functionName = String.fromEnvironment(
    'FIREBASE_CHAT_FUNCTION_NAME',
    defaultValue: 'chat',
  );
  static const _functionUrl = String.fromEnvironment(
    'FIREBASE_CHAT_FUNCTION_URL',
  );

  final FirebaseFunctionClient _functionClient;

  Future<String> ask({
    required String notes,
    required String transcript,
    required String history,
    required String question,
  }) async {
    final response = await _functionClient.postJson(
      functionName: _functionName,
      overrideUrl: _functionUrl,
      body: {
        'notes': notes,
        'transcript': transcript,
        'history': history,
        'question': question,
      },
    );

    final payload = FirebaseFunctionClient.unwrapPayload(response);
    final answer = payload['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const ChatFunctionException(
        'Firebase chat function response is missing answer.',
      );
    }

    return answer.trim();
  }

  void dispose() {
    _functionClient.dispose();
  }
}
