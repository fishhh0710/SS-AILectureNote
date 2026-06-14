import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/ai_page_note.dart';
import 'firebase_function_client.dart';

enum NoteGenerationStatus { idle, generating, completed, failed }

@immutable
class NoteGenerationState {
  const NoteGenerationState({
    required this.storageId,
    this.status = NoteGenerationStatus.idle,
    this.notes = const [],
    this.errorMessage,
    this.lastPdfPath,
  });

  final String storageId;
  final NoteGenerationStatus status;
  final List<AiPageNote> notes;
  final String? errorMessage;
  final String? lastPdfPath;

  bool get isGenerating => status == NoteGenerationStatus.generating;

  NoteGenerationState copyWith({
    NoteGenerationStatus? status,
    List<AiPageNote>? notes,
    String? errorMessage,
    bool clearError = false,
    String? lastPdfPath,
  }) {
    return NoteGenerationState(
      storageId: storageId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastPdfPath: lastPdfPath ?? this.lastPdfPath,
    );
  }
}

typedef LoadSavedNotes = Future<List<AiPageNote>> Function(String storageId);
typedef GenerateAndSaveNotes =
    Future<List<AiPageNote>> Function({
      required String storageId,
      required String pdfPath,
    });
typedef SaveNotes =
    Future<void> Function(String storageId, List<AiPageNote> notes);

class NoteGenerationManager {
  NoteGenerationManager._production()
    : _storage = FirebaseStorage.instance,
      _functionClient = FirebaseFunctionClient(),
      _loadSavedNotesOverride = null,
      _generateAndSaveNotesOverride = null,
      _saveNotesOverride = null;

  NoteGenerationManager._testing({
    required LoadSavedNotes loadSavedNotes,
    required GenerateAndSaveNotes generateAndSaveNotes,
    SaveNotes? saveNotes,
  }) : _storage = null,
       _functionClient = null,
       _loadSavedNotesOverride = loadSavedNotes,
       _generateAndSaveNotesOverride = generateAndSaveNotes,
       _saveNotesOverride = saveNotes;

  static final NoteGenerationManager instance =
      NoteGenerationManager._production();

  @visibleForTesting
  factory NoteGenerationManager.testing({
    required LoadSavedNotes loadSavedNotes,
    required GenerateAndSaveNotes generateAndSaveNotes,
    SaveNotes? saveNotes,
  }) {
    return NoteGenerationManager._testing(
      loadSavedNotes: loadSavedNotes,
      generateAndSaveNotes: generateAndSaveNotes,
      saveNotes: saveNotes,
    );
  }

  static const _functionName = String.fromEnvironment(
    'FIREBASE_NOTES_FUNCTION_NAME',
    defaultValue: 'generateNotesFromPdf',
  );
  static const _functionUrl = String.fromEnvironment(
    'FIREBASE_NOTES_FUNCTION_URL',
  );

  final FirebaseStorage? _storage;
  final FirebaseFunctionClient? _functionClient;
  final LoadSavedNotes? _loadSavedNotesOverride;
  final GenerateAndSaveNotes? _generateAndSaveNotesOverride;
  final SaveNotes? _saveNotesOverride;
  final Map<String, NoteGenerationState> _states = {};
  final Map<String, Future<void>> _loadOperations = {};
  final Map<String, Future<void>> _generationOperations = {};
  final Set<String> _loadedStorageIds = {};
  final StreamController<NoteGenerationState> _stateController =
      StreamController<NoteGenerationState>.broadcast();

  NoteGenerationState stateFor(String storageId) {
    return _states[storageId] ?? NoteGenerationState(storageId: storageId);
  }

  Stream<NoteGenerationState> watch(String storageId) {
    return _stateController.stream.where(
      (state) => state.storageId == storageId,
    );
  }

  Future<void> load(String storageId) {
    if (_loadedStorageIds.contains(storageId)) return Future.value();

    final existing = _loadOperations[storageId];
    if (existing != null) return existing;

    final operation = _load(storageId);
    _loadOperations[storageId] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_loadOperations[storageId], operation)) {
          _loadOperations.remove(storageId);
        }
      }),
    );
    return operation;
  }

  Future<void> generate({
    required String storageId,
    required String pdfPath,
  }) async {
    await load(storageId);

    final existing = _generationOperations[storageId];
    if (existing != null) return existing;

    final current = stateFor(storageId);
    _emit(
      current.copyWith(
        status: NoteGenerationStatus.generating,
        clearError: true,
        lastPdfPath: pdfPath,
      ),
    );

    final operation = _generate(storageId: storageId, pdfPath: pdfPath);
    _generationOperations[storageId] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_generationOperations[storageId], operation)) {
          _generationOperations.remove(storageId);
        }
      }),
    );
    return operation;
  }

  Future<void> retry(String storageId) async {
    final pdfPath = stateFor(storageId).lastPdfPath;
    if (pdfPath == null || pdfPath.isEmpty) return;
    await generate(storageId: storageId, pdfPath: pdfPath);
  }

  Future<void> updateNotes({
    required String storageId,
    required List<AiPageNote> notes,
  }) async {
    await load(storageId);

    final sortedNotes = [...notes]
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    if (_saveNotesOverride != null) {
      await _saveNotesOverride(storageId, sortedNotes);
    } else {
      await _saveNotes(storageId, sortedNotes);
    }

    final current = stateFor(storageId);
    _emit(
      current.copyWith(
        status: current.isGenerating
            ? NoteGenerationStatus.generating
            : NoteGenerationStatus.completed,
        notes: List.unmodifiable(sortedNotes),
        clearError: true,
      ),
    );
  }

  Future<bool> appendRealtimeUpdate({
    required String storageId,
    required int pageNumber,
    required List<String> newPoints,
    required List<String> questions,
  }) async {
    await load(storageId);

    final current = stateFor(storageId);
    final noteIndex = current.notes.indexWhere(
      (note) => note.pageNumber == pageNumber,
    );
    if (noteIndex < 0) return false;

    final note = current.notes[noteIndex];
    var markdown = note.markdown.trim();
    final additions = _newMarkdownItems(markdown, newPoints);
    markdown = _appendSection(
      markdown,
      heading: '### Professor Additions',
      items: additions,
    );
    final newQuestions = _newMarkdownItems(markdown, questions);
    markdown = _appendSection(
      markdown,
      heading: '### Professor Questions',
      items: newQuestions,
    );
    if (additions.isEmpty && newQuestions.isEmpty) return false;

    final updatedNotes = [...current.notes];
    updatedNotes[noteIndex] = AiPageNote(
      pageNumber: pageNumber,
      markdown: markdown,
    );
    await updateNotes(storageId: storageId, notes: updatedNotes);
    return true;
  }

  Future<void> _load(String storageId) async {
    try {
      final notes =
          await (_loadSavedNotesOverride?.call(storageId) ??
              _loadSavedNotes(storageId));
      _loadedStorageIds.add(storageId);

      final current = stateFor(storageId);
      if (current.isGenerating) return;

      _emit(
        current.copyWith(
          status: notes.isEmpty
              ? NoteGenerationStatus.idle
              : NoteGenerationStatus.completed,
          notes: notes,
          clearError: true,
        ),
      );
    } catch (error) {
      _loadedStorageIds.add(storageId);
      final current = stateFor(storageId);
      _emit(
        current.copyWith(
          status: NoteGenerationStatus.failed,
          errorMessage: 'Failed to load saved AI notes: $error',
        ),
      );
    }
  }

  Future<void> _generate({
    required String storageId,
    required String pdfPath,
  }) async {
    try {
      final notes =
          await (_generateAndSaveNotesOverride?.call(
                storageId: storageId,
                pdfPath: pdfPath,
              ) ??
              _generateAndSaveNotes(storageId: storageId, pdfPath: pdfPath));
      final mergedNotes = _mergeRealtimeUpdates(
        generatedNotes: notes,
        currentNotes: stateFor(storageId).notes,
      );
      if (!_sameNotes(notes, mergedNotes)) {
        if (_saveNotesOverride != null) {
          await _saveNotesOverride(storageId, mergedNotes);
        } else {
          await _saveNotes(storageId, mergedNotes);
        }
      }
      _emit(
        stateFor(storageId).copyWith(
          status: NoteGenerationStatus.completed,
          notes: List.unmodifiable(mergedNotes),
          clearError: true,
        ),
      );
    } catch (error) {
      _emit(
        stateFor(storageId).copyWith(
          status: NoteGenerationStatus.failed,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  List<AiPageNote> _mergeRealtimeUpdates({
    required List<AiPageNote> generatedNotes,
    required List<AiPageNote> currentNotes,
  }) {
    const headings = [
      '### Live Lecture Updates',
      '### Professor Additions',
      '### Professor Questions',
    ];
    final liveByPage = <int, String>{};
    for (final note in currentNotes) {
      final indices = headings
          .map(note.markdown.indexOf)
          .where((index) => index >= 0)
          .toList();
      if (indices.isNotEmpty) {
        indices.sort();
        liveByPage[note.pageNumber] = note.markdown.substring(indices.first);
      }
    }

    final merged = generatedNotes.map((note) {
      final liveSection = liveByPage.remove(note.pageNumber);
      if (liveSection == null) return note;
      return AiPageNote(
        pageNumber: note.pageNumber,
        markdown: '${note.markdown.trim()}\n\n$liveSection',
      );
    }).toList();

    for (final entry in liveByPage.entries) {
      merged.add(AiPageNote(pageNumber: entry.key, markdown: entry.value));
    }
    merged.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return merged;
  }

  List<String> _newMarkdownItems(String markdown, List<String> items) {
    final existing = markdown
        .split('\n')
        .map((line) => line.trim().toLowerCase())
        .toSet();
    final result = <String>[];
    for (final item in items) {
      var text = item.trim();
      if (text.isEmpty ||
          const {'null', 'none', 'n/a'}.contains(text.toLowerCase())) {
        continue;
      }
      text = text.replaceFirst(RegExp(r'^[-*]\s*'), '').trim();
      if (text.isEmpty) continue;
      final line = '- $text';
      if (existing.add(line.toLowerCase())) result.add(line);
    }
    return result;
  }

  String _appendSection(
    String markdown, {
    required String heading,
    required List<String> items,
  }) {
    if (items.isEmpty) return markdown;
    final headingIndex = markdown.indexOf(heading);
    if (headingIndex < 0) {
      return '${markdown.trim()}\n\n$heading\n${items.join('\n')}';
    }

    final sectionStart = headingIndex + heading.length;
    final nextHeading = RegExp(
      r'^###\s+',
      multiLine: true,
    ).firstMatch(markdown.substring(sectionStart));
    final insertAt = nextHeading == null
        ? markdown.length
        : sectionStart + nextHeading.start;
    final before = markdown.substring(0, insertAt).trimRight();
    final after = markdown.substring(insertAt).trimLeft();
    return after.isEmpty
        ? '$before\n${items.join('\n')}'
        : '$before\n${items.join('\n')}\n\n$after';
  }

  bool _sameNotes(List<AiPageNote> first, List<AiPageNote> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].pageNumber != second[index].pageNumber ||
          first[index].markdown != second[index].markdown) {
        return false;
      }
    }
    return true;
  }

  Future<List<AiPageNote>> _generateAndSaveNotes({
    required String storageId,
    required String pdfPath,
  }) async {
    final file = File(pdfPath);
    if (!await file.exists()) {
      throw Exception('PDF not found: $pdfPath');
    }

    final safeStorageId = _safeStorageId(storageId);
    final pdfStoragePath = _buildPdfStoragePath(safeStorageId, pdfPath);
    final jobPath = 'ai_note_jobs/$safeStorageId';

    await _storage!
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

    final response = await _functionClient!.postJson(
      functionName: _functionName,
      overrideUrl: _functionUrl,
      timeout: const Duration(minutes: 10),
      body: {
        'storageId': storageId,
        'storageBucket': _storage.bucket,
        'pdfStoragePath': pdfStoragePath,
        'jobPath': jobPath,
        'requestedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    final notes = await _parseFunctionResponse(response);
    await _saveNotes(storageId, notes);
    return notes;
  }

  Future<List<AiPageNote>> _parseFunctionResponse(
    Map<String, dynamic> response,
  ) async {
    final payload = FirebaseFunctionClient.unwrapPayload(response);
    if (payload['pages'] is List) return _parseNotesMap(payload);

    final notesStoragePath = payload['notesStoragePath'];
    if (notesStoragePath is String && notesStoragePath.isNotEmpty) {
      Uint8List? bytes;
      try {
        bytes = await _storage!
            .ref()
            .child(notesStoragePath)
            .getData(50 * 1024 * 1024);
      } on FirebaseException catch (error) {
        if (error.code == 'object-not-found') {
          throw Exception(
            'The deployed generateNotesFromPdf Function returned an output '
            'path before the notes file existed. Redeploy the current '
            'generateNotesFromPdf Function and try again.',
          );
        }
        rethrow;
      }
      if (bytes == null) {
        throw Exception('Generated notes file is empty: $notesStoragePath');
      }
      return _parseNotesResponse(utf8.decode(bytes));
    }

    throw const FormatException(
      'Firebase note function response is missing pages.',
    );
  }

  Future<List<AiPageNote>> _loadSavedNotes(String storageId) async {
    final notesDir = await _getLectureNotesDir(storageId);
    final jsonFile = File(p.join(notesDir.path, 'notes.json'));
    if (await jsonFile.exists()) {
      return _parseNotesResponse(await jsonFile.readAsString(encoding: utf8));
    }
    return _loadMarkdownFiles(notesDir);
  }

  Future<void> _saveNotes(String storageId, List<AiPageNote> notes) async {
    final outputDir = await _getLectureNotesDir(storageId);
    await outputDir.create(recursive: true);

    final sortedNotes = [...notes]
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    final nextMarkdownDir = Directory(p.join(outputDir.path, 'notes_next'));
    if (await nextMarkdownDir.exists()) {
      await nextMarkdownDir.delete(recursive: true);
    }
    await nextMarkdownDir.create(recursive: true);

    for (final note in sortedNotes) {
      final fileName = 'page_${note.pageNumber.toString().padLeft(3, '0')}.md';
      await File(
        p.join(nextMarkdownDir.path, fileName),
      ).writeAsString('${note.markdown.trim()}\n', encoding: utf8);
    }

    final jsonFile = File(p.join(outputDir.path, 'notes.json'));
    final nextJsonFile = File('${jsonFile.path}.next');
    final jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert({'pages': sortedNotes.map((note) => note.toJson()).toList()});
    await nextJsonFile.writeAsString(jsonText, encoding: utf8, flush: true);

    final markdownDir = Directory(p.join(outputDir.path, 'notes'));
    if (await markdownDir.exists()) {
      await markdownDir.delete(recursive: true);
    }
    await nextMarkdownDir.rename(markdownDir.path);
    if (await jsonFile.exists()) await jsonFile.delete();
    await nextJsonFile.rename(jsonFile.path);
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

    return pages
        .whereType<Map>()
        .map((page) => AiPageNote.fromJson(Map<String, dynamic>.from(page)))
        .where((note) => note.markdown.isNotEmpty)
        .toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
  }

  Future<List<AiPageNote>> _loadMarkdownFiles(Directory notesDir) async {
    final markdownDir = Directory(p.join(notesDir.path, 'notes'));
    if (!await markdownDir.exists()) return const [];

    final notes = <AiPageNote>[];
    final pattern = RegExp(r'^page_(\d+)\.md$');
    await for (final entity in markdownDir.list()) {
      if (entity is! File) continue;
      final match = pattern.firstMatch(p.basename(entity.path));
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

  String _safeStorageId(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  void _emit(NoteGenerationState state) {
    _states[state.storageId] = state;
    _stateController.add(state);
  }
}
