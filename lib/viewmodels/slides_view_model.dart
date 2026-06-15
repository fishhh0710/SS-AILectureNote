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
        fullWidth: page.width * 1.5,
        fullHeight: page.height * 1.5,
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

      final List<Map<String, dynamic>> candidates = [];
      for (final item in response) {
        final label = item['label'] as String;
        final colorName = item['color'] as String? ?? 'red';
        final coordsList = item['box'] as List<dynamic>?;

        if (coordsList != null && coordsList.length == 4) {
          final double x1 = (coordsList[0] as num).toDouble();
          final double y1 = (coordsList[1] as num).toDouble();
          final double x2 = (coordsList[2] as num).toDouble();
          final double y2 = (coordsList[3] as num).toDouble();

          candidates.add({
            'label': label,
            'colorName': colorName,
            'box': [x1, y1, x2, y2],
            'area': (x2 - x1) * (y2 - y1),
          });
        }
      }

      // Sort candidates by area ascending
      candidates.sort(
        (a, b) => (a['area'] as double).compareTo(b['area'] as double),
      );

      final Set<int> removedIndices = {};
      for (int i = 0; i < candidates.length; i++) {
        if (removedIndices.contains(i)) continue;
        for (int j = i + 1; j < candidates.length; j++) {
          if (removedIndices.contains(j)) continue;

          final overlaps = _calculateOverlapFraction(
            candidates[i]['box'] as List<double>,
            candidates[j]['box'] as List<double>,
          );
          if (overlaps[0] > 0.30 && overlaps[1] > 0.30) {
            // j is the larger/equal box (since candidates is sorted ascending by area). Remove it.
            removedIndices.add(j);
            debugPrint(
              "Overlap filter: Removing larger box '${candidates[j]['label']}' because it overlaps >30% mutually with '${candidates[i]['label']}'.",
            );
          }
        }
      }

      for (int k = candidates.length - 1; k >= 0; k--) {
        if (removedIndices.contains(k)) continue;

        final candidate = candidates[k];
        final label = candidate['label'] as String;
        final colorName = candidate['colorName'] as String;
        final box = candidate['box'] as List<double>;

        final x1 = box[0];
        final y1 = box[1];
        final x2 = box[2];
        final y2 = box[3];

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
          id: 'rect_${DateTime.now().microsecondsSinceEpoch}_$k',
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
        fullWidth: page.width * 1.5,
        fullHeight: page.height * 1.5,
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
      final List<Map<String, dynamic>> candidates = [];
      for (final item in response) {
        final label = item['label'] as String;
        final colorName = item['color'] as String? ?? 'red';
        final coordsList = item['box'] as List<dynamic>?;

        if (coordsList != null && coordsList.length == 4) {
          final double x1 = (coordsList[0] as num).toDouble();
          final double y1 = (coordsList[1] as num).toDouble();
          final double x2 = (coordsList[2] as num).toDouble();
          final double y2 = (coordsList[3] as num).toDouble();

          candidates.add({
            'label': label,
            'colorName': colorName,
            'box': [x1, y1, x2, y2],
            'area': (x2 - x1) * (y2 - y1),
          });
        }
      }

      // Sort candidates by area ascending
      candidates.sort(
        (a, b) => (a['area'] as double).compareTo(b['area'] as double),
      );

      final Set<int> removedIndices = {};
      for (int i = 0; i < candidates.length; i++) {
        if (removedIndices.contains(i)) continue;
        for (int j = i + 1; j < candidates.length; j++) {
          if (removedIndices.contains(j)) continue;

          final overlaps = _calculateOverlapFraction(
            candidates[i]['box'] as List<double>,
            candidates[j]['box'] as List<double>,
          );
          if (overlaps[0] > 0.30 && overlaps[1] > 0.30) {
            // j is the larger/equal box. Remove it.
            removedIndices.add(j);
            debugPrint(
              "Overlap filter: Removing larger box '${candidates[j]['label']}' because it overlaps >30% mutually with '${candidates[i]['label']}'.",
            );
          }
        }
      }

      for (int k = candidates.length - 1; k >= 0; k--) {
        if (removedIndices.contains(k)) continue;

        final candidate = candidates[k];
        final label = candidate['label'] as String;
        final colorName = candidate['colorName'] as String;
        final box = candidate['box'] as List<double>;

        final x1 = box[0];
        final y1 = box[1];
        final x2 = box[2];
        final y2 = box[3];

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
          id: 'rect_${DateTime.now().microsecondsSinceEpoch}_$k',
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
    } catch (e) {
      debugPrint('Failed to process page with targets $pageIndex: $e');
    }
  }

  /// Processes all pages in the PDF document concurrently with a sliding window/pipeline of max 10 requests
  Future<void> processAllPages({
    required PdfDocument document,
    required PageAnnotationManager annotationManager,
    required Function(int pageNum, bool isDone) onPageProgress,
  }) async {
    const int maxConcurrency = 8;
    int nextPageIndex = 0;

    // Worker function: continuously grabs the next slide in queue and processes it
    Future<void> runWorker() async {
      while (true) {
        final int currentIdx = nextPageIndex;
        nextPageIndex++;

        if (currentIdx >= document.pages.length) {
          break; // No more pages to process
        }

        final pageNum = currentIdx + 1;
        onPageProgress(
          pageNum,
          false,
        ); // Mark this page index as currently loading

        try {
          await processPage(
            page: document.pages[currentIdx],
            pageIndex: pageNum,
            annotationManager: annotationManager,
          );
        } catch (error) {
          debugPrint('Error while auto-annotating page $pageNum: $error');
        } finally {
          onPageProgress(pageNum, true); // Turn off spinner even if it failed
        }
      }
    }

    // Launch up to 10 workers in parallel
    final List<Future<void>> workers = [];
    final int workerCount = document.pages.length < maxConcurrency
        ? document.pages.length
        : maxConcurrency;

    for (int w = 0; w < workerCount; w++) {
      workers.add(runWorker());
    }

    // Wait for all workers to finish
    await Future.wait(workers);
  }

  List<double> _calculateOverlapFraction(List<double> boxA, List<double> boxB) {
    // box format: [x1, y1, x2, y2]
    final x1A = boxA[0];
    final y1A = boxA[1];
    final x2A = boxA[2];
    final y2A = boxA[3];

    final x1B = boxB[0];
    final y1B = boxB[1];
    final x2B = boxB[2];
    final y2B = boxB[3];

    final areaA = (x2A - x1A) * (y2A - y1A);
    final areaB = (x2B - x1B) * (y2B - y1B);

    if (areaA <= 0 || areaB <= 0) {
      return [0.0, 0.0];
    }

    // Calculate intersection coordinates
    final x1I = x1A > x1B ? x1A : x1B;
    final y1I = y1A > y1B ? y1A : y1B;
    final x2I = x2A < x2B ? x2A : x2B;
    final y2I = y2A < y2B ? y2A : y2B;

    double areaI = 0.0;
    if (x2I > x1I && y2I > y1I) {
      areaI = (x2I - x1I) * (y2I - y1I);
    }

    final overlapA = areaI / areaA;
    final overlapB = areaI / areaB;

    return [overlapA, overlapB];
  }

  @override
  void dispose() {
    _bboxService.dispose();
    super.dispose();
  }
}
