import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ai_page_note.dart';
import '../services/note_generation_manager.dart';

class LectureNotesViewModel extends ChangeNotifier {
  LectureNotesViewModel({NoteGenerationManager? manager})
    : _manager = manager ?? NoteGenerationManager.instance;

  final NoteGenerationManager _manager;
  StreamSubscription<NoteGenerationState>? _subscription;
  String? _storageId;
  bool _disposed = false;

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
    _storageId = storageId;
    await _subscription?.cancel();
    _subscription = _manager.watch(storageId).listen(_applyState);
    await _manager.load(storageId);
    _applyState(_manager.stateFor(storageId));
  }

  Future<void> generateFromPdf({
    required String storageId,
    required String pdfPath,
  }) async {
    _lastPdfPath = pdfPath;
    unawaited(_manager.generate(storageId: storageId, pdfPath: pdfPath));
  }

  Future<void> retry(String storageId) async {
    unawaited(_manager.retry(storageId));
  }

  void _applyState(NoteGenerationState state) {
    if (_disposed || state.storageId != _storageId) return;

    _notes = state.notes;
    _isGenerating = state.isGenerating;
    _errorMessage = state.errorMessage;
    _lastPdfPath = state.lastPdfPath ?? _lastPdfPath;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
