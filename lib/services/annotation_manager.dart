import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../data/annotation_model.dart';

class PageAnnotationManager {
  final int pdfId;
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  // Cache of page-level ValueNotifiers
  final Map<int, ValueNotifier<List<Annotation>>> _pageNotifiers = {};

  // Set of page indexes that have unsaved changes
  final Set<int> _dirtyPages = {};
  Timer? _debounceTimer;
  bool _isDisposed = false;

  PageAnnotationManager(this.pdfId);

  bool get isDisposed => _isDisposed;

  Future<String?> getGenerationStatus() => dbHelper.getAnnotationStatus(pdfId);
  Future<void> setGenerationStatus(String status) =>
      dbHelper.setAnnotationStatus(pdfId, status);
  Future<void> deleteGenerationStatus() =>
      dbHelper.deleteAnnotationStatus(pdfId);

  // Synchronously returns the ValueNotifier for a page, loading it asynchronously if not cached
  ValueNotifier<List<Annotation>> getPageNotifier(int pageIndex) {
    if (_pageNotifiers.containsKey(pageIndex)) {
      return _pageNotifiers[pageIndex]!;
    }

    final notifier = ValueNotifier<List<Annotation>>([]);
    _pageNotifiers[pageIndex] = notifier;

    _loadPageAnnotationsFromDb(pageIndex, notifier);

    return notifier;
  }

  Future<void> _loadPageAnnotationsFromDb(
    int pageIndex,
    ValueNotifier<List<Annotation>> notifier,
  ) async {
    try {
      final list = await dbHelper.getPageAnnotations(pdfId, pageIndex);
      notifier.value = list;
    } catch (e) {
      print('載入頁面 $pageIndex 的標記失敗: $e');
    }
  }

  // Get all currently loaded annotations across all pages (for list visualization in the Dialog)
  List<Annotation> getAllLoadedAnnotations() {
    final List<Annotation> all = [];
    // Sort pages for neat presentation
    final sortedKeys = _pageNotifiers.keys.toList()..sort();
    for (var key in sortedKeys) {
      all.addAll(_pageNotifiers[key]!.value);
    }
    return all;
  }

  // Add an annotation to a specific page
  void addAnnotation(int pageIndex, Annotation ann) {
    if (_isDisposed) return;
    final notifier = getPageNotifier(pageIndex);
    // Update memory cache -> triggers UI repaint instantly
    notifier.value = List.from(notifier.value)..add(ann);
    _markPageAsDirty(pageIndex);
  }

  // Delete a specific annotation from a page by its ID
  void deleteAnnotation(int pageIndex, String annotationId) {
    if (_isDisposed) return;
    final notifier = getPageNotifier(pageIndex);
    // Update memory cache -> triggers UI repaint instantly
    notifier.value = List.from(notifier.value)
      ..removeWhere((e) => e.id == annotationId);
    _markPageAsDirty(pageIndex);
  }

  // Clear all annotations from a specific page
  void clearPage(int pageIndex) {
    if (_isDisposed) return;
    final notifier = getPageNotifier(pageIndex);
    notifier.value = [];
    _markPageAsDirty(pageIndex);
  }

  // Clear all annotations for this PDF across all pages
  Future<void> clearAll() async {
    _debounceTimer?.cancel();
    _dirtyPages.clear();

    // Clear all page ValueNotifiers
    for (var notifier in _pageNotifiers.values) {
      notifier.value = [];
    }

    // Direct deletion in the database
    await dbHelper.clearAllPdfAnnotations(pdfId);
    await dbHelper.deleteAnnotationStatus(pdfId);
  }

  // Mark a page as having pending changes and schedule a debounced DB write
  void _markPageAsDirty(int pageIndex) {
    if (_isDisposed) return;
    _dirtyPages.add(pageIndex);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: 600),
      _saveDirtyPagesToDb,
    );
  }

  // Save all dirty pages to SQLite in one batch in the background
  Future<void> _saveDirtyPagesToDb() async {
    if (_isDisposed) return;
    final pagesToSave = List<int>.from(_dirtyPages);
    _dirtyPages.clear();

    for (final pageIndex in pagesToSave) {
      final annotations = _pageNotifiers[pageIndex]?.value ?? [];
      try {
        if (annotations.isEmpty) {
          await dbHelper.deletePageAnnotationsNode(pdfId, pageIndex);
        } else {
          await dbHelper.savePageAnnotations(pdfId, pageIndex, annotations);
        }
      } catch (e) {
        print('儲存頁面 $pageIndex 的標記失敗: $e');
      }
    }
  }

  // Dispose of the manager, ensuring any remaining changes are flushed to DB
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    // Flush pending writes before setting disposed if we are not interrupted
    _saveDirtyPagesToDb();

    _discardIfInterrupted();

    for (var notifier in _pageNotifiers.values) {
      notifier.dispose();
    }
  }

  Future<void> _discardIfInterrupted() async {
    try {
      final status = await dbHelper.getAnnotationStatus(pdfId);
      if (status == 'generating') {
        // Discard whatever has been generated
        await dbHelper.clearAllPdfAnnotations(pdfId);
        await dbHelper.deleteAnnotationStatus(pdfId);
        // ignore: avoid_print
        print(
          'DEBUG [Agent]: Discarded partial bounding boxes on close for PDF $pdfId',
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to discard partial annotations: $e');
    }
  }
}
