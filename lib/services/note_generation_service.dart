import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/ai_page_note.dart';
import 'firebase_function_client.dart';

class NoteGenerationException implements Exception {
  final String message;

  const NoteGenerationException(this.message);

  @override
  String toString() => message;
}

class NoteGenerationService {
  NoteGenerationService({
    FirebaseStorage? storage,
    FirebaseFunctionClient? functionClient,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _functionClient = functionClient ?? FirebaseFunctionClient();

  static const _functionName = String.fromEnvironment(
    'FIREBASE_NOTES_FUNCTION_NAME',
    defaultValue: 'generateNotesFromPdf',
  );
  static const _functionUrl = String.fromEnvironment(
    'FIREBASE_NOTES_FUNCTION_URL',
  );

  final FirebaseStorage _storage;
  final FirebaseFunctionClient _functionClient;

  Future<List<AiPageNote>> generateNotesFromPdf({
    required String storageId,
    required String pdfPath,
  }) async {
    final file = File(pdfPath);
    if (!await file.exists()) {
      throw NoteGenerationException('PDF not found: $pdfPath');
    }

    final safeStorageId = _safeStorageId(storageId);
    final pdfStoragePath = _buildPdfStoragePath(safeStorageId, pdfPath);
    final jobPath = 'ai_note_jobs/$safeStorageId';

    await _storage
        .ref()
        .child(pdfStoragePath)
        .putFile(
          file,
          SettableMetadata(
            contentType: 'application/pdf',
            customMetadata: {
              'storageId': storageId,
              'sourceFileName': p.basename(pdfPath),
            },
          ),
        );

    final response = await _functionClient.postJson(
      functionName: _functionName,
      overrideUrl: _functionUrl,
      timeout: const Duration(minutes: 10),
      body: {
        'storageId': storageId,
        'pdfStoragePath': pdfStoragePath,
        'jobPath': jobPath,
        'requestedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    return _parseFunctionResponse(response);
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
    _functionClient.dispose();
  }

  Future<List<AiPageNote>> _parseFunctionResponse(
    Map<String, dynamic> response,
  ) async {
    final payload = FirebaseFunctionClient.unwrapPayload(response);

    if (payload['pages'] is List) {
      return _parseNotesMap(payload);
    }

    final notesStoragePath = payload['notesStoragePath'];
    if (notesStoragePath is String && notesStoragePath.isNotEmpty) {
      final bytes = await _storage
          .ref()
          .child(notesStoragePath)
          .getData(50 * 1024 * 1024);
      if (bytes == null) {
        throw NoteGenerationException(
          'Generated notes file is empty: $notesStoragePath',
        );
      }
      return _parseNotesResponse(utf8.decode(bytes));
    }

    final status = payload['status'];
    final jobPath = payload['jobPath'];
    if (status is String && status.isNotEmpty) {
      throw NoteGenerationException(
        'Note generation job is "$status". The Firebase Function must return '
        'pages or notesStoragePath before the app can render notes.'
        '${jobPath is String ? ' Job path: $jobPath.' : ''}',
      );
    }

    throw const NoteGenerationException(
      'Firebase note function response is missing pages.',
    );
  }

  List<AiPageNote> _parseNotesResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI note response must be a JSON object.');
    }

    return _parseNotesMap(decoded);
  }

  List<AiPageNote> _parseNotesMap(Map<String, dynamic> decoded) {
    final pages = decoded['pages'];
    if (pages is! List) {
      throw const FormatException('AI note response is missing pages.');
    }

    final notes =
        pages
            .whereType<Map>()
            .map((page) => AiPageNote.fromJson(Map<String, dynamic>.from(page)))
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

  String _buildPdfStoragePath(String safeStorageId, String pdfPath) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final fileName = _safeFileName(p.basename(pdfPath));
    return 'ai_note_jobs/$safeStorageId/source/${timestamp}_$fileName';
  }

  String _safeStorageId(String storageId) {
    return storageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  String _safeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
