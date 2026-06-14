import 'dart:convert';
import 'package:http/http.dart' as http;

class BoundingBoxService {
  BoundingBoxService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _defaultUrl =
      'https://pdf-bbox-api-176828697643.us-central1.run.app';

  /// Sends the image bytes of a slide to the unified pipeline API and returns
  /// a list of annotations, each containing a description label, color, and bounding box coordinates.
  Future<List<Map<String, dynamic>>> fetchAnnotatedPipeline(
    List<int> imageBytes, {
    String? overrideUrl,
  }) async {
    final baseUrl = overrideUrl ?? _defaultUrl;
    final url = Uri.parse('$baseUrl/detect/pipeline');

    try {
      final request = http.MultipartRequest('POST', url);
      request.files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: 'slide.jpg'),
      );

      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to process slide pipeline (status code: ${response.statusCode})',
        );
      }

      final responseString = await response.stream.bytesToString();
      final List<dynamic> decoded = jsonDecode(responseString);

      return decoded.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      throw Exception('BoundingBoxService pipeline error: $e');
    }
  }

  /// Sends the image bytes of a slide along with agent-defined targets JSON to the
  /// agent-pipeline API and returns matched bounding box coordinates.
  Future<List<Map<String, dynamic>>> fetchAgentPipeline(
    List<int> imageBytes,
    String targetsJson, {
    String? overrideUrl,
  }) async {
    final baseUrl = overrideUrl ?? _defaultUrl;
    final url = Uri.parse('$baseUrl/detect/agent-pipeline');

    try {
      final request = http.MultipartRequest('POST', url);
      request.files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: 'slide.jpg'),
      );
      request.fields['targets'] = targetsJson;

      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to process slide agent-pipeline (status code: ${response.statusCode})',
        );
      }

      final responseString = await response.stream.bytesToString();
      final List<dynamic> decoded = jsonDecode(responseString);

      return decoded.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      throw Exception('BoundingBoxService agent-pipeline error: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
