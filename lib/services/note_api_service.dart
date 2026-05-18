import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class GeneratedPageNote {
  final int pageNumber;
  final String markdown;

  const GeneratedPageNote({
    required this.pageNumber,
    required this.markdown,
  });

  factory GeneratedPageNote.fromJson(Map<String, dynamic> json) {
    return GeneratedPageNote(
      pageNumber: json['page_number'] as int,
      markdown: json['markdown'] as String,
    );
  }
}

class NoteApiService {
  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('PYTHON_API_BASE_URL');
    if (configured.isNotEmpty) return configured;

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }

    return 'http://127.0.0.1:8000';
  }

  final String baseUrl;
  final HttpClient _client;

  NoteApiService({
    String? baseUrl,
    HttpClient? client,
  })  : baseUrl = baseUrl ?? defaultBaseUrl,
        _client = client ?? HttpClient();

  Future<List<GeneratedPageNote>> generatePageNotesFromPdf(
    String pdfPath,
  ) async {
    final responseJson = await _uploadPdf(pdfPath);
    final pages = responseJson['pages'];

    if (pages is! List) {
      throw const FormatException('API response does not contain pages.');
    }

    return pages
        .map((page) => GeneratedPageNote.fromJson(page as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> _uploadPdf(String pdfPath) async {
    final pdfFile = File(pdfPath);

    if (!await pdfFile.exists()) {
      throw FileSystemException('PDF file does not exist.', pdfPath);
    }

    final uri = Uri.parse('$baseUrl/notes/from-pdf');
    final request = await _client.postUrl(uri);
    final boundary = 'ss-ai-lecture-note-${DateTime.now().microsecondsSinceEpoch}';
    final filename = p.basename(pdfPath).replaceAll('"', '');

    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    request.write('--$boundary\r\n');
    request.write(
      'Content-Disposition: form-data; name="file"; filename="$filename"\r\n',
    );
    request.write('Content-Type: application/pdf\r\n\r\n');
    await request.addStream(pdfFile.openRead());
    request.write('\r\n--$boundary--\r\n');

    final response = await request.close().timeout(
          const Duration(minutes: 5),
        );
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'PDF notes API failed with status ${response.statusCode}: $body',
        uri: uri,
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('API response is not a JSON object.');
    }

    return decoded;
  }

  void close() {
    _client.close(force: true);
  }
}
