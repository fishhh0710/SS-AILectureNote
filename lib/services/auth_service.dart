import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class AzureAuthService {
  // Use 10.0.2.2 for Android emulator to access localhost, or your computer's IP for physical devices.
  // For now, assuming you are testing locally. Adjust this URL when you move to Firebase.
  final String backendUrl = 'http://10.0.2.2:5000/api/azure-token';

  Future<String> getTemporaryToken() async {
    try {
      final response = await http.get(Uri.parse(backendUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['token'] != null) {
          return data['token'];
        } else {
          throw Exception(
            'Backend did not return a token. Response: ${response.body}',
          );
        }
      } else {
        throw Exception(
          'Failed to fetch Azure token. Status Code: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching Azure token: $e');
      rethrow;
    }
  }
}
