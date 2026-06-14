import 'dart:async';
import 'dart:convert';
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

  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _isProcessing = false;

  RealtimeAgentCoordinator({
    required this.storageId,
    required this.slidesViewModel,
    required this.notesViewModel,
    required this.currentPageNotifier,
    required this.segmentStream,
    required this.getAnnotationManager,
    required this.getPdfDocument,
  }) {
    _subscribe();
  }

  void _subscribe() {
    _subscription = segmentStream.listen((event) {
      final text = event['text'] as String? ?? '';
      final isEmpty = event['is_empty'] as bool? ?? true;
      if (!isEmpty && text.trim().isNotEmpty) {
        unawaited(_processTranscriptChunk(text.trim()));
      }
    });
  }

  Future<void> _processTranscriptChunk(String chunk) async {
    if (_isProcessing) return;
    _isProcessing = true;

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

      final client = FirebaseFunctionClient();
      final decoded = await client.postJson(
        functionName: 'realtimeAgent',
        body: {
          'currentSummary': currentSummary,
          'chunk': chunk,
        },
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
    } finally {
      _isProcessing = false;
    }
  }

  String _cleanJson(String text) {
    text = text.trim();
    if (text.startsWith('```')) {
      final lines = text.split('\n');
      if (lines.first.startsWith('```')) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty && lines.last.startsWith('```')) {
        lines.removeLast();
      }
      text = lines.join('\n').trim();
    }
    return text;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
