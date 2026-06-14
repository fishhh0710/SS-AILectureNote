import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/annotation_manager.dart';
import '../services/firebase_function_client.dart';
import '../viewmodels/slides_view_model.dart';
import '../viewmodels/lecture_notes_view_model.dart';

class RealtimeAgentCoordinator {
  final String storageId;
  final SlidesViewModel slidesViewModel;
  final LectureNotesViewModel notesViewModel;
  final ValueNotifier<int> currentPageNotifier;
  final Stream<Map<String, dynamic>> segmentStream;
  final PageAnnotationManager? Function() getAnnotationManager;
  final PdfDocument? Function() getPdfDocument;
  final FirebaseFunctionClient _functionClient;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<String> _pendingChunks = [];
  bool _isProcessing = false;
  bool _isDisposed = false;

  RealtimeAgentCoordinator({
    required this.storageId,
    required this.slidesViewModel,
    required this.notesViewModel,
    required this.currentPageNotifier,
    required this.segmentStream,
    required this.getAnnotationManager,
    required this.getPdfDocument,
    FirebaseFunctionClient? functionClient,
  }) : _functionClient = functionClient ?? FirebaseFunctionClient() {
    _subscribe();
  }

  void _subscribe() {
    _subscription = segmentStream.listen((event) {
      final text = event['text'] as String? ?? '';
      final isEmpty = event['is_empty'] as bool? ?? true;
      if (!isEmpty && text.trim().isNotEmpty) {
        _pendingChunks.add(text.trim());
        unawaited(_drainQueue());
      }
    });
  }

  Future<void> _drainQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (!_isDisposed && _pendingChunks.isNotEmpty) {
        final chunk = _pendingChunks.removeAt(0);
        await _processTranscriptChunk(chunk);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processTranscriptChunk(String chunk) async {
    try {
      final pageIndex = currentPageNotifier.value;
      final doc = getPdfDocument();
      final annotationManager = getAnnotationManager();

      if (doc == null || annotationManager == null) {
        // ignore: avoid_print
        print(
          'DEBUG [Agent]: PDF Document or Annotation Manager is not ready.',
        );
        return;
      }

      if (pageIndex < 1 || pageIndex > doc.pages.length) {
        // ignore: avoid_print
        print('DEBUG [Agent]: Current page index $pageIndex is out of bounds.');
        return;
      }

      // Find current summary for this page
      final noteIndex = notesViewModel.notes.indexWhere(
        (note) => note.pageNumber == pageIndex,
      );
      final currentSummary = noteIndex != -1
          ? notesViewModel.notes[noteIndex].markdown
          : '';

      final decoded = await _functionClient.postJson(
        functionName: 'realtimeAgent',
        body: {'currentSummary': currentSummary, 'chunk': chunk},
      );

      // Handle summary additions
      final additionalSummary = decoded['additional_summary'] as String?;
      if (additionalSummary != null && additionalSummary.trim().isNotEmpty) {
        // ignore: avoid_print
        print('DEBUG [Agent]: Appending live note update to page $pageIndex');
        await notesViewModel.appendNoteToPage(
          storageId: storageId,
          pageNumber: pageIndex,
          additionalMarkdown: additionalSummary.trim(),
        );
      }

      // Handle bounding box updates
      final targets = decoded['targets'] as List<dynamic>?;
      if (targets != null && targets.isNotEmpty) {
        // ignore: avoid_print
        print(
          'DEBUG [Agent]: Resolving dynamic bounding boxes for targets: $targets',
        );
        final targetsList = targets
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList();
        final page = doc.pages[pageIndex - 1];

        await slidesViewModel.processPageWithTargets(
          page: page,
          pageIndex: pageIndex,
          targets: targetsList,
          annotationManager: annotationManager,
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG [Agent] Error in real-time agent processing: $e');
    }
  }

  void dispose() {
    _isDisposed = true;
    _pendingChunks.clear();
    unawaited(_subscription?.cancel());
    _functionClient.dispose();
  }
}
