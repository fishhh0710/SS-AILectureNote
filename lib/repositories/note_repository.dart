import '../models/ai_page_note.dart';
import '../services/note_generation_service.dart';

class NoteRepository {
  NoteRepository({NoteGenerationService? service})
    : _service = service ?? NoteGenerationService();

  final NoteGenerationService _service;

  Future<List<AiPageNote>> loadSavedNotes(String storageId) {
    return _service.loadSavedNotes(storageId);
  }

  Future<void> clearSavedNotes(String storageId) {
    return _service.clearSavedNotes(storageId);
  }

  Future<List<AiPageNote>> generateNotes({
    required String storageId,
    required String pdfPath,
  }) {
    return _service.generateNotesFromPdf(
      storageId: storageId,
      pdfPath: pdfPath,
    );
  }

  Future<void> saveNotes(String storageId, List<AiPageNote> notes) {
    return _service.saveNotes(storageId, notes);
  }

  void dispose() {
    _service.dispose();
  }
}
