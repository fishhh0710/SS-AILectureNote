import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/annotation_model.dart';
import '../repositories/file_tree_repository.dart';
import '../services/annotation_manager.dart';
import '../services/bounding_box_service.dart';

class SlidesViewModel extends ChangeNotifier {
  SlidesViewModel({required String fileId, FileTreeRepository? repository})
    : _fileId = fileId,
      _repository = repository ?? FileTreeRepository();

  final String _fileId;
  final FileTreeRepository _repository;
  final BoundingBoxService _bboxService = BoundingBoxService();

  int? get _nodeId => int.tryParse(_fileId);

  Future<String?> loadSavedPdfPath() async {
    final nodeId = _nodeId;
    if (nodeId == null) return null;

    final node = await _repository.getNode(nodeId);
    return node?.filePath;
  }

  Future<void> savePdfPath(String filePath) async {
    final nodeId = _nodeId;
    if (nodeId == null) {
      throw Exception('Cannot save PDF because fileId is invalid.');
    }

    await _repository.updateFilePath(nodeId: nodeId, filePath: filePath);
  }

  /// Processes a single page of the PDF: renders it as an image, converts it
  /// to PNG, sends it to the API, and stores the results as annotations.
  Future<void> processPage({
    required PdfPage page,
    required int pageIndex,
    required PageAnnotationManager annotationManager,
  }) async {
    try {
      // 1. Render the page to a high-resolution raw pixel buffer
      final pdfImage = await page.render(
        width: (page.width * 1.5).toInt(),
        height: (page.height * 1.5).toInt(),
      );
      if (pdfImage == null) return;

      // 2. Decode raw BGRA pixels to a Flutter ui.Image and encode as PNG bytes
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pdfImage.pixels,
        pdfImage.width,
        pdfImage.height,
        ui.PixelFormat.bgra8888,
        (ui.Image img) {
          completer.complete(img);
        },
      );
      final uiImage = await completer.future;
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      final imgWidth = pdfImage.width.toDouble();
      final imgHeight = pdfImage.height.toDouble();
      uiImage.dispose();
      pdfImage.dispose(); // Release native image resources early

      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      // 3. Request bounding boxes from the REST API
      final response = await _bboxService.fetchAnnotatedPipeline(pngBytes);

      // 4. Map the bounding boxes back to relative coordinates and add them
      // Clear any pre-existing annotations for this page before adding fresh ones
      annotationManager.clearPage(pageIndex);

      for (final item in response) {
        final label = item['label'] as String;
        final colorName = item['color'] as String? ?? 'red';
        final coordsList = item['box'] as List<dynamic>?;

        if (coordsList != null && coordsList.length == 4) {
          final double x1 = (coordsList[0] as num).toDouble();
          final double y1 = (coordsList[1] as num).toDouble();
          final double x2 = (coordsList[2] as num).toDouble();
          final double y2 = (coordsList[3] as num).toDouble();

          // Normalize absolute pixel coordinates to relative (0.0 to 1.0)
          final rx = x1 / imgWidth;
          final ry = y1 / imgHeight;
          final rw = (x2 - x1) / imgWidth;
          final rh = (y2 - y1) / imgHeight;

          // Parse color string to ui.Color
          ui.Color colorVal;
          switch (colorName.toLowerCase()) {
            case 'green':
              colorVal = const ui.Color(0xFF00FF00);
              break;
            case 'blue':
              colorVal = const ui.Color(0xFF0000FF);
              break;
            case 'yellow':
              colorVal = const ui.Color(0xFFFFFF00);
              break;
            case 'cyan':
              colorVal = const ui.Color(0xFF00FFFF);
              break;
            case 'magenta':
              colorVal = const ui.Color(0xFFFF00FF);
              break;
            case 'orange':
              colorVal = const ui.Color(0xFFFFA500);
              break;
            case 'purple':
              colorVal = const ui.Color(0xFF800080);
              break;
            case 'white':
              colorVal = const ui.Color(0xFFFFFFFF);
              break;
            case 'black':
              colorVal = const ui.Color(0xFF000000);
              break;
            default:
              colorVal = const ui.Color(0xFFFF0000); // Default to Red
          }

          final annotation = RectAnnotation(
            id: 'rect_${DateTime.now().microsecondsSinceEpoch}',
            pageIndex: pageIndex,
            color: colorVal,
            x: rx,
            y: ry,
            width: rw,
            height: rh,
            label: label,
          );
          annotationManager.addAnnotation(pageIndex, annotation);
        }
      }
    } catch (e) {
      debugPrint('Failed to process page $pageIndex: $e');
      rethrow;
    }
  }

  /// Runs OpenCV contour/morph and matching against agent targets,
  /// adding new bounding box annotations to the page dynamically.
  Future<void> processPageWithTargets({
    required PdfPage page,
    required int pageIndex,
    required List<Map<String, dynamic>> targets,
    required PageAnnotationManager annotationManager,
  }) async {
    try {
      if (targets.isEmpty) return;

      // 1. Render the page to a high-resolution raw pixel buffer
      final pdfImage = await page.render(
        width: (page.width * 1.5).toInt(),
        height: (page.height * 1.5).toInt(),
      );
      if (pdfImage == null) return;

      // 2. Decode raw BGRA pixels to a Flutter ui.Image and encode as PNG bytes
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pdfImage.pixels,
        pdfImage.width,
        pdfImage.height,
        ui.PixelFormat.bgra8888,
        (ui.Image img) {
          completer.complete(img);
        },
      );
      final uiImage = await completer.future;
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      final imgWidth = pdfImage.width.toDouble();
      final imgHeight = pdfImage.height.toDouble();
      uiImage.dispose();
      pdfImage.dispose(); // Release native image resources early

      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      // Convert targets list to JSON string
      final targetsJson = jsonEncode(targets);

      // 3. Request bounding boxes matching the targets from the REST API
      final response = await _bboxService.fetchAgentPipeline(
        pngBytes,
        targetsJson,
      );

      // 4. Map the bounding boxes back to relative coordinates and add them
      for (final item in response) {
        final label = item['label'] as String;
        final colorName = item['color'] as String? ?? 'red';
        final coordsList = item['box'] as List<dynamic>?;

        if (coordsList != null && coordsList.length == 4) {
          final double x1 = (coordsList[0] as num).toDouble();
          final double y1 = (coordsList[1] as num).toDouble();
          final double x2 = (coordsList[2] as num).toDouble();
          final double y2 = (coordsList[3] as num).toDouble();

          // Normalize absolute pixel coordinates to relative (0.0 to 1.0)
          final rx = x1 / imgWidth;
          final ry = y1 / imgHeight;
          final rw = (x2 - x1) / imgWidth;
          final rh = (y2 - y1) / imgHeight;

          // Parse color string to ui.Color
          ui.Color colorVal;
          switch (colorName.toLowerCase()) {
            case 'green':
              colorVal = const ui.Color(0xFF00FF00);
              break;
            case 'blue':
              colorVal = const ui.Color(0xFF0000FF);
              break;
            case 'yellow':
              colorVal = const ui.Color(0xFFFFFF00);
              break;
            case 'cyan':
              colorVal = const ui.Color(0xFF00FFFF);
              break;
            case 'magenta':
              colorVal = const ui.Color(0xFFFF00FF);
              break;
            case 'orange':
              colorVal = const ui.Color(0xFFFFA500);
              break;
            case 'purple':
              colorVal = const ui.Color(0xFF800080);
              break;
            case 'white':
              colorVal = const ui.Color(0xFFFFFFFF);
              break;
            case 'black':
              colorVal = const ui.Color(0xFF000000);
              break;
            default:
              colorVal = const ui.Color(0xFFFF0000); // Default to Red
          }

          // Check if an annotation with the exact same label already exists on this page.
          // If it does, delete it so we can update it dynamically with new coordinates.
          final existingNotifier = annotationManager.getPageNotifier(pageIndex);
          final existingList = List<Annotation>.from(existingNotifier.value);
          for (final ann in existingList) {
            if (ann is RectAnnotation && ann.label == label) {
              annotationManager.deleteAnnotation(pageIndex, ann.id);
            }
          }

          final annotation = RectAnnotation(
            id: 'rect_${DateTime.now().microsecondsSinceEpoch}',
            pageIndex: pageIndex,
            color: colorVal,
            x: rx,
            y: ry,
            width: rw,
            height: rh,
            label: label,
          );
          annotationManager.addAnnotation(pageIndex, annotation);
        }
      }
    } catch (e) {
      debugPrint('Failed to process page with targets $pageIndex: $e');
    }
  }

  /// Processes all pages in the PDF document concurrently using Future.wait
  Future<void> processAllPages({
    required PdfDocument document,
    required PageAnnotationManager annotationManager,
    required Function(int pageNum, bool isDone) onPageProgress,
  }) async {
    final List<Future<void>> tasks = [];

    for (int i = 0; i < document.pages.length; i++) {
      final pageNum = i + 1;
      onPageProgress(
        pageNum,
        false,
      ); // Mark this page index as currently loading

      final task =
          processPage(
                page: document.pages[i],
                pageIndex: pageNum,
                annotationManager: annotationManager,
              )
              .then((_) {
                onPageProgress(pageNum, true); // Loading finished
              })
              .catchError((error) {
                debugPrint('Error while auto-annotating page $pageNum: $error');
                onPageProgress(
                  pageNum,
                  true,
                ); // Turn off spinner even if it failed
              });

      tasks.add(task);
    }

    await Future.wait(tasks);
  }

  @override
  void dispose() {
    _bboxService.dispose();
    super.dispose();
  }
}
