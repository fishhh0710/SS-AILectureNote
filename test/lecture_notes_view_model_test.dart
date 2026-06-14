import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_note_app/models/ai_page_note.dart';
import 'package:lecture_note_app/services/note_generation_manager.dart';
import 'package:lecture_note_app/viewmodels/lecture_notes_view_model.dart';

void main() {
  const oldNotes = [AiPageNote(pageNumber: 1, markdown: 'Old summary')];
  const newNotes = [AiPageNote(pageNumber: 1, markdown: 'New summary')];

  test('keeps existing notes visible while generation is running', () async {
    final generation = Completer<List<AiPageNote>>();
    final manager = NoteGenerationManager.testing(
      loadSavedNotes: (_) async => oldNotes,
      generateAndSaveNotes: ({required storageId, required pdfPath}) {
        return generation.future;
      },
    );
    final viewModel = LectureNotesViewModel(manager: manager);

    await viewModel.loadSaved('lecture-1');
    await viewModel.generateFromPdf(
      storageId: 'lecture-1',
      pdfPath: 'lecture.pdf',
    );
    await _waitFor(() => viewModel.isGenerating);

    expect(viewModel.notes, oldNotes);

    final completed = manager
        .watch('lecture-1')
        .firstWhere((state) => state.status == NoteGenerationStatus.completed);
    generation.complete(newNotes);
    await completed;

    expect(viewModel.isGenerating, isFalse);
    expect(viewModel.notes, newNotes);
    expect(viewModel.errorMessage, isNull);
    viewModel.dispose();
  });

  test('generation continues after the first view model is disposed', () async {
    final generation = Completer<List<AiPageNote>>();
    final manager = NoteGenerationManager.testing(
      loadSavedNotes: (_) async => const [],
      generateAndSaveNotes: ({required storageId, required pdfPath}) {
        return generation.future;
      },
    );
    final firstViewModel = LectureNotesViewModel(manager: manager);

    await firstViewModel.loadSaved('lecture-1');
    await firstViewModel.generateFromPdf(
      storageId: 'lecture-1',
      pdfPath: 'lecture.pdf',
    );
    await _waitFor(() => firstViewModel.isGenerating);
    firstViewModel.dispose();

    final completed = manager
        .watch('lecture-1')
        .firstWhere((state) => state.status == NoteGenerationStatus.completed);
    generation.complete(newNotes);
    await completed;

    final secondViewModel = LectureNotesViewModel(manager: manager);
    await secondViewModel.loadSaved('lecture-1');

    expect(secondViewModel.isGenerating, isFalse);
    expect(secondViewModel.notes, newNotes);
    secondViewModel.dispose();
  });

  test(
    'deduplicates simultaneous generation requests for one lecture',
    () async {
      final generation = Completer<List<AiPageNote>>();
      var calls = 0;
      final manager = NoteGenerationManager.testing(
        loadSavedNotes: (_) async => const [],
        generateAndSaveNotes: ({required storageId, required pdfPath}) {
          calls++;
          return generation.future;
        },
      );

      final first = manager.generate(
        storageId: 'lecture-1',
        pdfPath: 'lecture.pdf',
      );
      final second = manager.generate(
        storageId: 'lecture-1',
        pdfPath: 'lecture.pdf',
      );
      await _waitFor(() => calls == 1);

      expect(calls, 1);

      generation.complete(newNotes);
      await Future.wait([first, second]);
      expect(manager.stateFor('lecture-1').notes, newNotes);
    },
  );

  test('retains old notes when generation fails', () async {
    final manager = NoteGenerationManager.testing(
      loadSavedNotes: (_) async => oldNotes,
      generateAndSaveNotes: ({required storageId, required pdfPath}) async {
        throw Exception('OpenAI failed');
      },
    );
    final viewModel = LectureNotesViewModel(manager: manager);

    await viewModel.loadSaved('lecture-1');
    await viewModel.generateFromPdf(
      storageId: 'lecture-1',
      pdfPath: 'lecture.pdf',
    );
    await _waitFor(() => viewModel.errorMessage != null);

    expect(viewModel.notes, oldNotes);
    expect(viewModel.isGenerating, isFalse);
    expect(viewModel.errorMessage, contains('OpenAI failed'));
    expect(viewModel.canRetry, isTrue);
    viewModel.dispose();
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not reached in time.');
}
