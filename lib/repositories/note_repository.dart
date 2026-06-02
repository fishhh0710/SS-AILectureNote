import '../models/ai_page_note.dart';
import '../services/note_generation_service.dart';

class NoteRepository {
  NoteRepository({NoteGenerationService? service})
    : _service = service ?? NoteGenerationService();

  final NoteGenerationService _service;

  Future<List<AiPageNote>> loadSavedNotes(String storageId) {
    return _service.loadSavedNotes(storageId);
  }

  Future<List<AiPageNote>> generateAndSaveNotes({
    required String storageId,
    required String pdfPath,
  }) async {
    await _service.clearSavedNotes(storageId);
    final notes = await _service.generateNotesFromPdf(pdfPath);
    await _service.saveNotes(storageId, notes);
    return notes;
  }

  void dispose() {
    _service.dispose();
  }
}
