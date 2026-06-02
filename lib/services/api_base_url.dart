import 'dart:io';

String defaultLocalApiBaseUrl() {
  const configured = String.fromEnvironment('PYTHON_API_BASE_URL');
  if (configured.isNotEmpty) return configured;

  if (Platform.isAndroid) {
    return 'http://10.0.2.2:8000';
  }

  return 'http://127.0.0.1:8000';
}
