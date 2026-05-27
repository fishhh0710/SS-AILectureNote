import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AiPageNote {
  final int pageNumber;
  final String markdown;

  const AiPageNote({required this.pageNumber, required this.markdown});

  factory AiPageNote.fromJson(Map<String, dynamic> json) {
    final pageValue = json['page_number'] ?? json['pageNumber'];
    final pageNumber = pageValue is int
        ? pageValue
        : int.tryParse(pageValue.toString());

    if (pageNumber == null) {
      throw const FormatException('Missing page_number in AI note response.');
    }

    final markdown = json['markdown'];
    if (markdown is! String) {
      throw const FormatException('Missing markdown in AI note response.');
    }

    return AiPageNote(pageNumber: pageNumber, markdown: markdown.trim());
  }

  Map<String, dynamic> toJson() {
    return {'page_number': pageNumber, 'markdown': markdown};
  }
}

class NoteGenerationException implements Exception {
  final String message;

  const NoteGenerationException(this.message);

  @override
  String toString() => message;
}

class NoteGenerationService {
  NoteGenerationService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? _defaultBaseUrl();

  final http.Client _client;
  final String baseUrl;

  static String _defaultBaseUrl() {
    const configured = String.fromEnvironment('PYTHON_API_BASE_URL');
    if (configured.isNotEmpty) return configured;

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }

    return 'http://127.0.0.1:8000';
  }

  Future<List<AiPageNote>> generateNotesFromPdf(String pdfPath) async {
    final file = File(pdfPath);
    if (!await file.exists()) {
      throw NoteGenerationException('PDF not found: $pdfPath');
    }

    final request = http.MultipartRequest('POST', _uri('/notes/from-pdf'))
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          pdfPath,
          filename: p.basename(pdfPath),
        ),
      );

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(minutes: 10));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NoteGenerationException(_extractErrorMessage(response));
    }

    return _parseNotesResponse(response.body);
  }

  Future<List<AiPageNote>> loadSavedNotes(String storageId) async {
    final notesDir = await _getLectureNotesDir(storageId);
    final jsonFile = File(p.join(notesDir.path, 'notes.json'));

    if (await jsonFile.exists()) {
      final contents = await jsonFile.readAsString(encoding: utf8);
      return _parseNotesResponse(contents);
    }

    return _loadMarkdownFiles(notesDir);
  }

  Future<void> saveNotes(String storageId, List<AiPageNote> notes) async {
    final outputDir = await _getLectureNotesDir(storageId);
    await outputDir.create(recursive: true);

    final markdownDir = Directory(p.join(outputDir.path, 'notes'));
    if (await markdownDir.exists()) {
      await markdownDir.delete(recursive: true);
    }
    await markdownDir.create(recursive: true);

    final sortedNotes = [...notes]
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    final jsonFile = File(p.join(outputDir.path, 'notes.json'));
    final jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert({'pages': sortedNotes.map((note) => note.toJson()).toList()});

    await jsonFile.writeAsString(jsonText, encoding: utf8);

    for (final note in sortedNotes) {
      final fileName = 'page_${note.pageNumber.toString().padLeft(3, '0')}.md';
      final markdownFile = File(p.join(markdownDir.path, fileName));
      await markdownFile.writeAsString(
        '${note.markdown.trim()}\n',
        encoding: utf8,
      );
    }
  }

  Future<void> clearSavedNotes(String storageId) async {
    final notesDir = await _getLectureNotesDir(storageId);
    if (await notesDir.exists()) {
      await notesDir.delete(recursive: true);
    }
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

  List<AiPageNote> _parseNotesResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI note response must be a JSON object.');
    }

    final pages = decoded['pages'];
    if (pages is! List) {
      throw const FormatException('AI note response is missing pages.');
    }

    final notes =
        pages
            .map(
              (page) =>
                  AiPageNote.fromJson(Map<String, dynamic>.from(page as Map)),
            )
            .where((note) => note.markdown.isNotEmpty)
            .toList()
          ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    return notes;
  }

  Future<List<AiPageNote>> _loadMarkdownFiles(Directory lectureNotesDir) async {
    final markdownDir = Directory(p.join(lectureNotesDir.path, 'notes'));
    if (!await markdownDir.exists()) return const [];

    final notes = <AiPageNote>[];
    final pageFilePattern = RegExp(r'^page_(\d+)\.md$');

    await for (final entity in markdownDir.list()) {
      if (entity is! File) continue;

      final match = pageFilePattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;

      final pageNumber = int.tryParse(match.group(1)!);
      if (pageNumber == null) continue;

      final markdown = await entity.readAsString(encoding: utf8);
      if (markdown.trim().isEmpty) continue;

      notes.add(AiPageNote(pageNumber: pageNumber, markdown: markdown.trim()));
    }

    notes.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return notes;
  }

  Future<Directory> _getLectureNotesDir(String storageId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(
      p.join(appDir.path, 'ai_notes', _safeStorageId(storageId)),
    );
  }

  String _safeStorageId(String storageId) {
    return storageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          final message = detail['message'];
          if (message is String && message.isNotEmpty) {
            return 'AI note generation failed (${response.statusCode}): $message';
          }
        }
        if (detail is String && detail.isNotEmpty) {
          return 'AI note generation failed (${response.statusCode}): $detail';
        }
      }
    } catch (_) {
      // Fall back to the raw HTTP response below.
    }

    final body = response.body.trim();
    if (body.isNotEmpty) {
      return 'AI note generation failed (${response.statusCode}): $body';
    }

    return 'AI note generation failed (${response.statusCode}).';
  }
}
