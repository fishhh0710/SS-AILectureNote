import 'package:flutter/foundation.dart';

import '../models/ai_page_note.dart';
import '../repositories/note_repository.dart';

class LectureNotesViewModel extends ChangeNotifier {
  LectureNotesViewModel({NoteRepository? repository})
    : _repository = repository ?? NoteRepository();

  final NoteRepository _repository;
  int _requestId = 0;

  List<AiPageNote> _notes = const [];
  bool _isGenerating = false;
  String? _errorMessage;
  String? _lastPdfPath;

  List<AiPageNote> get notes => _notes;
  bool get isGenerating => _isGenerating;
  String? get errorMessage => _errorMessage;
  String? get lastPdfPath => _lastPdfPath;
  bool get canRetry => _lastPdfPath != null && !_isGenerating;

  Future<void> loadSaved(String storageId) async {
    final requestId = ++_requestId;

    try {
      final notes = await _repository.loadSavedNotes(storageId);
      if (requestId != _requestId) return;

      _notes = notes;
      notifyListeners();
    } catch (e) {
      if (requestId != _requestId) return;

      _errorMessage = 'Failed to load saved AI notes: $e';
      notifyListeners();
    }
  }

  Future<void> generateFromPdf({
    required String storageId,
    required String pdfPath,
  }) async {
    final requestId = ++_requestId;

    _lastPdfPath = pdfPath;
    _notes = const [];
    _isGenerating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.clearSavedNotes(storageId);
      final notes = await _repository.generateNotes(
        storageId: storageId,
        pdfPath: pdfPath,
      );
      if (requestId != _requestId) return;

      await _repository.saveNotes(storageId, notes);

      _notes = notes;
      _isGenerating = false;
      notifyListeners();
    } catch (e) {
      if (requestId != _requestId) return;

      _isGenerating = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> retry(String storageId) async {
    final pdfPath = _lastPdfPath;
    if (pdfPath == null || _isGenerating) return;

    await generateFromPdf(storageId: storageId, pdfPath: pdfPath);
  }

  void cancelPending() {
    _requestId++;
  }

  Future<void> appendNoteToPage({
    required String storageId,
    required int pageNumber,
    required String additionalMarkdown,
  }) async {
    final updatedNotes = _notes.map((note) {
      if (note.pageNumber == pageNumber) {
        final currentText = note.markdown;
        String newMarkdown;
        if (currentText.contains('### Live Lecture Updates')) {
          newMarkdown = "$currentText\n$additionalMarkdown";
        } else {
          newMarkdown = "$currentText\n\n### Live Lecture Updates\n$additionalMarkdown";
        }
        return AiPageNote(
          pageNumber: note.pageNumber,
          markdown: newMarkdown,
        );
      }
      return note;
    }).toList();

    _notes = updatedNotes;
    notifyListeners();

    try {
      await _repository.saveNotes(storageId, _notes);
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save notes after live update: $e');
    }
  }

  @override
  void dispose() {
    cancelPending();
    _repository.dispose();
    super.dispose();
  }
}
