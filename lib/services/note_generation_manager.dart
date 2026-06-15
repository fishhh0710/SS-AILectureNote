import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
    this.totalPages = 0,
    this.completedPages = 0,
    this.totalBatches = 0,
    this.completedBatches = 0,
  });

  final String storageId;
  final NoteGenerationStatus status;
  final List<AiPageNote> notes;
  final String? errorMessage;
  final String? lastPdfPath;
  final int totalPages;
  final int completedPages;
  final int totalBatches;
  final int completedBatches;

  bool get isGenerating => status == NoteGenerationStatus.generating;

  NoteGenerationState copyWith({
    NoteGenerationStatus? status,
    List<AiPageNote>? notes,
    String? errorMessage,
    bool clearError = false,
    String? lastPdfPath,
    int? totalPages,
    int? completedPages,
    int? totalBatches,
    int? completedBatches,
    bool clearProgress = false,
  }) {
    return NoteGenerationState(
      storageId: storageId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastPdfPath: lastPdfPath ?? this.lastPdfPath,
      totalPages: clearProgress ? 0 : totalPages ?? this.totalPages,
      completedPages: clearProgress ? 0 : completedPages ?? this.completedPages,
      totalBatches: clearProgress ? 0 : totalBatches ?? this.totalBatches,
      completedBatches: clearProgress
          ? 0
          : completedBatches ?? this.completedBatches,
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
      _firestore = FirebaseFirestore.instance,
      _auth = FirebaseAuth.instance,
      _functionClient = FirebaseFunctionClient(),
      _loadSavedNotesOverride = null,
      _generateAndSaveNotesOverride = null,
      _saveNotesOverride = null;

  NoteGenerationManager._testing({
    required LoadSavedNotes loadSavedNotes,
    required GenerateAndSaveNotes generateAndSaveNotes,
    SaveNotes? saveNotes,
  }) : _storage = null,
       _firestore = null,
       _auth = null,
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
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final FirebaseFunctionClient? _functionClient;
  final LoadSavedNotes? _loadSavedNotesOverride;
  final GenerateAndSaveNotes? _generateAndSaveNotesOverride;
  final SaveNotes? _saveNotesOverride;
  final Map<String, NoteGenerationState> _states = {};
  final Map<String, Future<void>> _loadOperations = {};
  final Map<String, Future<void>> _generationOperations = {};
  final Map<String, Future<void>> _noteMutationOperations = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _batchSubscriptions = {};
  final Map<String, String> _activeJobIds = {};
  final Map<String, Set<String>> _appliedBatchIds = {};
  final Map<String, String> _courseIds = {};
  final Map<String, String> _lectureIds = {};
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
    String? courseId,
    String? lectureId,
  }) async {
    _courseIds[storageId] = courseId ?? _courseIds[storageId] ?? storageId;
    _lectureIds[storageId] = lectureId ?? _lectureIds[storageId] ?? storageId;
    await load(storageId);

    final existing = _generationOperations[storageId];
    if (existing != null) return existing;

    final current = stateFor(storageId);
    _emit(
      current.copyWith(
        status: NoteGenerationStatus.generating,
        clearError: true,
        clearProgress: true,
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
    await _enqueueNoteMutation(storageId, () async {
      await _saveAndEmitNotes(storageId, notes);
    });
  }

  Future<bool> appendRealtimeUpdate({
    required String storageId,
    required int pageNumber,
    required List<String> newPoints,
    required List<String> questions,
  }) async {
    await load(storageId);
    return _enqueueNoteMutation(storageId, () async {
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
      await _saveAndEmitNotes(storageId, updatedNotes);
      return true;
    });
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
      await _stopBatchListener(storageId);
      await _enqueueNoteMutation(storageId, () async {
        final mergedNotes = _mergeGeneratedPages(
          generatedNotes: notes,
          currentNotes: stateFor(storageId).notes,
        );
        await _saveNotesForStorage(storageId, mergedNotes);
        final current = stateFor(storageId);
        _emit(
          current.copyWith(
            status: NoteGenerationStatus.completed,
            notes: List.unmodifiable(mergedNotes),
            completedPages: current.totalPages > 0
                ? current.totalPages
                : mergedNotes.length,
            completedBatches: current.totalBatches,
            clearError: true,
          ),
        );
      });
    } catch (error) {
      _emit(
        stateFor(storageId).copyWith(
          status: NoteGenerationStatus.failed,
          errorMessage: error.toString(),
        ),
      );
    } finally {
      await _stopBatchListener(storageId);
    }
  }

  List<AiPageNote> _mergeGeneratedPages({
    required List<AiPageNote> generatedNotes,
    required List<AiPageNote> currentNotes,
  }) {
    const headings = [
      '### Live Lecture Updates',
      '### Professor Additions',
      '### Professor Questions',
    ];
    final currentByPage = {
      for (final note in currentNotes) note.pageNumber: note,
    };
    final mergedByPage = {...currentByPage};
    for (final note in currentNotes) {
      final indices = headings
          .map(note.markdown.indexOf)
          .where((index) => index >= 0)
          .toList();
      if (indices.isEmpty) continue;
      indices.sort();
      final liveSection = note.markdown.substring(indices.first);
      final generated = generatedNotes.where(
        (item) => item.pageNumber == note.pageNumber,
      );
      if (generated.isNotEmpty) {
        final replacement = generated.first;
        mergedByPage[note.pageNumber] = AiPageNote(
          pageNumber: note.pageNumber,
          markdown: '${replacement.markdown.trim()}\n\n$liveSection',
        );
      }
    }

    for (final note in generatedNotes) {
      mergedByPage.putIfAbsent(note.pageNumber, () => note);
      if (!currentByPage.containsKey(note.pageNumber) ||
          !headings.any(currentByPage[note.pageNumber]!.markdown.contains)) {
        mergedByPage[note.pageNumber] = note;
      }
    }

    final merged = mergedByPage.values.toList();
    merged.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return merged;
  }

  Future<T> _enqueueNoteMutation<T>(
    String storageId,
    Future<T> Function() action,
  ) {
    final previous = _noteMutationOperations[storageId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> queued;
    queued = () async {
      try {
        await previous;
      } catch (_) {
        // A failed write must not block later note updates.
      }
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    _noteMutationOperations[storageId] = queued;
    unawaited(
      queued.whenComplete(() {
        if (identical(_noteMutationOperations[storageId], queued)) {
          _noteMutationOperations.remove(storageId);
        }
      }),
    );
    return completer.future;
  }

  Future<void> _saveNotesForStorage(
    String storageId,
    List<AiPageNote> notes,
  ) async {
    if (_saveNotesOverride != null) {
      await _saveNotesOverride(storageId, notes);
    } else if (_storage != null) {
      await _saveNotes(storageId, notes);
    }
  }

  Future<void> _saveAndEmitNotes(
    String storageId,
    List<AiPageNote> notes,
  ) async {
    final sortedNotes = [...notes]
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    await _saveNotesForStorage(storageId, sortedNotes);
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

  Future<void> _startBatchListener({
    required String storageId,
    required String uid,
    required String jobId,
  }) async {
    final firestore = _firestore;
    if (firestore == null) return;
    await _stopBatchListener(storageId);
    _activeJobIds[storageId] = jobId;
    _appliedBatchIds[storageId] = <String>{};
    final batches = firestore
        .collection('users')
        .doc(uid)
        .collection('ai_note_jobs')
        .doc(jobId)
        .collection('batches');
    _batchSubscriptions[storageId] = batches.snapshots().listen(
      (snapshot) {
        if (_activeJobIds[storageId] != jobId) return;
        final documents = snapshot.docs;
        final totalPages = documents.fold<int>(0, (maximum, document) {
          final value = document.data()['totalPages'];
          return value is int && value > maximum ? value : maximum;
        });
        final completedDocuments = documents.where(
          (document) => document.data()['status'] == 'completed',
        );
        final completedPages = completedDocuments.fold<int>(0, (
          total,
          document,
        ) {
          final data = document.data();
          final start = data['startPage'];
          final end = data['endPage'];
          return start is int && end is int ? total + end - start + 1 : total;
        });
        final current = stateFor(storageId);
        _emit(
          current.copyWith(
            status: NoteGenerationStatus.generating,
            totalPages: totalPages,
            completedPages: completedPages,
            totalBatches: documents.length,
            completedBatches: completedDocuments.length,
          ),
        );

        final applied = _appliedBatchIds[storageId]!;
        for (final document in completedDocuments) {
          if (!applied.add(document.id)) continue;
          try {
            final rawPages = document.data()['pages'];
            if (rawPages is! List) continue;
            final batchNotes = rawPages
                .whereType<Map>()
                .map(
                  (page) =>
                      AiPageNote.fromJson(Map<String, dynamic>.from(page)),
                )
                .toList();
            unawaited(_applyPartialBatch(storageId, batchNotes));
          } catch (error) {
            _emit(
              stateFor(storageId).copyWith(
                errorMessage: 'Failed to apply generated pages: $error',
              ),
            );
          }
        }
      },
      onError: (Object error) {
        if (_activeJobIds[storageId] != jobId) return;
        _emit(
          stateFor(
            storageId,
          ).copyWith(errorMessage: 'Failed to receive generated pages: $error'),
        );
      },
    );
  }

  Future<void> _applyPartialBatch(
    String storageId,
    List<AiPageNote> batchNotes,
  ) async {
    if (batchNotes.isEmpty) return;
    await _enqueueNoteMutation(storageId, () async {
      final merged = _mergeGeneratedPages(
        generatedNotes: batchNotes,
        currentNotes: stateFor(storageId).notes,
      );
      await _saveAndEmitNotes(storageId, merged);
    });
  }

  @visibleForTesting
  Future<void> applyPartialBatchForTesting(
    String storageId,
    List<AiPageNote> batchNotes,
  ) {
    return _applyPartialBatch(storageId, batchNotes);
  }

  Future<void> _stopBatchListener(String storageId) async {
    _activeJobIds.remove(storageId);
    _appliedBatchIds.remove(storageId);
    await _batchSubscriptions.remove(storageId)?.cancel();
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
    final user = _auth?.currentUser;
    if (user == null) {
      throw StateError('Firebase authentication is required for AI notes.');
    }
    final jobId = const Uuid().v4();

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

    await _startBatchListener(
      storageId: storageId,
      uid: user.uid,
      jobId: jobId,
    );
    final response = await _functionClient!.postJson(
      functionName: _functionName,
      overrideUrl: _functionUrl,
      timeout: const Duration(minutes: 10),
      body: {
        'storageId': storageId,
        'courseId': _courseIds[storageId] ?? storageId,
        'lectureId': _lectureIds[storageId] ?? storageId,
        'storageBucket': _storage.bucket,
        'pdfStoragePath': pdfStoragePath,
        'jobId': jobId,
        'requestedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    return _parseFunctionResponse(response);
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
