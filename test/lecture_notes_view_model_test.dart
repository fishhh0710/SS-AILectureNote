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
      expect(manager.stateFor('lecture-1').errorMessage, isNull);
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

  test('persists structured realtime summary additions', () async {
    List<AiPageNote>? savedNotes;
    final manager = NoteGenerationManager.testing(
      loadSavedNotes: (_) async => oldNotes,
      generateAndSaveNotes: ({required storageId, required pdfPath}) async {
        return newNotes;
      },
      saveNotes: (storageId, notes) async {
        savedNotes = notes;
      },
    );
    final viewModel = LectureNotesViewModel(manager: manager);

    await viewModel.loadSaved('lecture-1');
    final updated = await viewModel.appendRealtimeUpdate(
      storageId: 'lecture-1',
      pageNumber: 1,
      newPoints: const ['- Teacher explanation'],
      questions: const ['Why does this work?'],
    );

    expect(updated, isTrue);
    expect(savedNotes, isNotNull);
    expect(savedNotes!.single.markdown, contains('### Professor Additions'));
    expect(savedNotes!.single.markdown, contains('- Teacher explanation'));
    expect(savedNotes!.single.markdown, contains('### Professor Questions'));
    expect(savedNotes!.single.markdown, contains('- Why does this work?'));
    await _waitFor(
      () => viewModel.notes.single.markdown == savedNotes!.single.markdown,
    );
    expect(viewModel.notes, hasLength(1));
    expect(viewModel.notes.single.pageNumber, savedNotes!.single.pageNumber);
    expect(viewModel.notes.single.markdown, savedNotes!.single.markdown);
    viewModel.dispose();
  });

  test('discards realtime updates when the page has no summary', () async {
    List<AiPageNote>? savedNotes;
    final manager = NoteGenerationManager.testing(
      loadSavedNotes: (_) async => const [],
      generateAndSaveNotes: ({required storageId, required pdfPath}) async {
        return newNotes;
      },
      saveNotes: (storageId, notes) async {
        savedNotes = notes;
      },
    );
    final viewModel = LectureNotesViewModel(manager: manager);

    await viewModel.loadSaved('lecture-1');
    final updated = await viewModel.appendRealtimeUpdate(
      storageId: 'lecture-1',
      pageNumber: 2,
      newPoints: const ['- New explanation'],
      questions: const [],
    );

    expect(updated, isFalse);
    expect(savedNotes, isNull);
    expect(viewModel.notes, isEmpty);
    viewModel.dispose();
  });

  test('deduplicates repeated realtime additions', () async {
    List<AiPageNote>? savedNotes;
    final manager = NoteGenerationManager.testing(
      loadSavedNotes: (_) async => oldNotes,
      generateAndSaveNotes: ({required storageId, required pdfPath}) async {
        return newNotes;
      },
      saveNotes: (storageId, notes) async {
        savedNotes = notes;
      },
    );

    await manager.appendRealtimeUpdate(
      storageId: 'lecture-1',
      pageNumber: 1,
      newPoints: const ['- Teacher explanation', '- Teacher explanation'],
      questions: const [],
    );
    await manager.appendRealtimeUpdate(
      storageId: 'lecture-1',
      pageNumber: 1,
      newPoints: const ['Teacher explanation'],
      questions: const [],
    );

    expect(
      RegExp('Teacher explanation').allMatches(savedNotes!.single.markdown),
      hasLength(1),
    );
  });

  test('preserves live updates when PDF generation finishes later', () async {
    final generation = Completer<List<AiPageNote>>();
    final manager = NoteGenerationManager.testing(
      loadSavedNotes: (_) async => oldNotes,
      generateAndSaveNotes: ({required storageId, required pdfPath}) {
        return generation.future;
      },
      saveNotes: (storageId, notes) async {},
    );

    final operation = manager.generate(
      storageId: 'lecture-1',
      pdfPath: 'lecture.pdf',
    );
    await _waitFor(() => manager.stateFor('lecture-1').isGenerating);
    await manager.updateNotes(
      storageId: 'lecture-1',
      notes: const [
        AiPageNote(
          pageNumber: 1,
          markdown:
              'Old summary\n\n### Professor Additions\n- Teacher explanation',
        ),
      ],
    );

    generation.complete(newNotes);
    await operation;

    final note = manager.stateFor('lecture-1').notes.single;
    expect(note.markdown, startsWith('New summary'));
    expect(note.markdown, contains('### Professor Additions'));
    expect(note.markdown, contains('- Teacher explanation'));
  });

  test(
    'partial PDF batch replaces only completed pages and keeps live updates',
    () async {
      List<AiPageNote>? savedNotes;
      final manager = NoteGenerationManager.testing(
        loadSavedNotes: (_) async => const [
          AiPageNote(
            pageNumber: 1,
            markdown: 'Old page 1\n\n### Professor Additions\n- Live detail',
          ),
          AiPageNote(pageNumber: 2, markdown: 'Old page 2'),
          AiPageNote(pageNumber: 3, markdown: 'Old page 3'),
        ],
        generateAndSaveNotes: ({required storageId, required pdfPath}) async =>
            const [],
        saveNotes: (storageId, notes) async {
          savedNotes = notes;
        },
      );

      await manager.load('lecture-1');
      await manager.applyPartialBatchForTesting('lecture-1', const [
        AiPageNote(pageNumber: 1, markdown: 'New page 1'),
        AiPageNote(pageNumber: 2, markdown: 'New page 2'),
      ]);

      expect(savedNotes, hasLength(3));
      expect(savedNotes![0].markdown, startsWith('New page 1'));
      expect(savedNotes![0].markdown, contains('- Live detail'));
      expect(savedNotes![1].markdown, 'New page 2');
      expect(savedNotes![2].markdown, 'Old page 3');
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not reached in time.');
}
