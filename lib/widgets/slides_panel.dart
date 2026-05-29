import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../database/models.dart';
import '../services/annotation_manager.dart';

import 'panel_header.dart';
import 'slide_page.dart';
import 'annotation_test_controls.dart';

class SlidesPanel extends StatefulWidget {
  final double width;
  final int index;
  final String fileId;
  final VoidCallback onClose;
  final Future<void> Function(String filePath)? onPdfUploaded;

  const SlidesPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    required this.fileId,
    this.onPdfUploaded,
  });

  @override
  State<SlidesPanel> createState() => _SlidesPanelState();
}

class _SlidesPanelState extends State<SlidesPanel> {
  PdfDocument? doc;
  bool _isLoading = false;
  String? _errorMessage;
  PageAnnotationManager? _annotationManager;

  int? get _nodeId => int.tryParse(widget.fileId);

  @override
  void initState() {
    super.initState();
    _loadSavedPdf();
  }

  @override
  void didUpdateWidget(covariant SlidesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      doc?.dispose();
      doc = null;
      _annotationManager?.dispose();
      _annotationManager = null;
      _loadSavedPdf();
    }
  }

  Future<void> _loadSavedPdf() async {
    final nodeId = _nodeId;
    if (nodeId == null) {
      print('DEBUG: _loadSavedPdf returned early because _nodeId is null');
      return;
    }

    print('DEBUG: _loadSavedPdf started, nodeId: $nodeId');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final node = await DatabaseHelper.instance.getNodeById(nodeId);
      final savedPath = node?.filePath;
      print('DEBUG: Database node fetched, filePath: $savedPath');

      if (savedPath == null || savedPath.isEmpty) {
        print('DEBUG: savedPath is null or empty, setting _isLoading = false');
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final fileExists = await File(savedPath).exists();
      print('DEBUG: file exists: $fileExists');
      if (!fileExists) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Saved PDF not found. Please upload it again.';
          });
        }
        return;
      }

      print('DEBUG: calling _openPdf');
      await _openPdf(savedPath);
      print('DEBUG: _openPdf call finished successfully');
    } catch (e, stack) {
      print('DEBUG: _loadSavedPdf caught error: $e');
      print('DEBUG: StackTrace: $stack');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load saved PDF: $e';
        });
      }
    }
  }

  Future<void> pickAndLoadPdf() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });

        final savedPath = await _copyPdfToAppStorage(result.files.single.path!);
        await _savePdfPath(savedPath);
        await _openPdf(savedPath);
        final onPdfUploaded = widget.onPdfUploaded;
        if (onPdfUploaded != null) {
          unawaited(onPdfUploaded(savedPath));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to upload PDF: $e';
        });
      }
    }
  }

  Future<String> _copyPdfToAppStorage(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final slidesDir = Directory(p.join(appDir.path, 'lecture_slides'));
    await slidesDir.create(recursive: true);

    final destinationPath = p.join(slidesDir.path, '${widget.fileId}.pdf');
    final sourceFile = File(sourcePath);
    final destinationFile = File(destinationPath);

    if (sourceFile.absolute.path != destinationFile.absolute.path) {
      await sourceFile.copy(destinationPath);
    }

    return destinationPath;
  }

  Future<void> _savePdfPath(String filePath) async {
    final nodeId = _nodeId;
    if (nodeId == null) {
      throw Exception('Cannot save PDF because fileId is invalid.');
    }

    final node = await DatabaseHelper.instance.getNodeById(nodeId);
    if (node == null) {
      throw Exception(
        'Cannot save PDF because the lecture item does not exist.',
      );
    }

    await DatabaseHelper.instance.updateItem(
      AppNode(
        id: node.id,
        parentId: node.parentId,
        type: node.type,
        name: node.name,
        content: node.content,
        filePath: filePath,
        createdAt: node.createdAt,
      ),
    );
  }

  Future<void> _openPdf(String filePath) async {
    print('DEBUG: _openPdf started with filePath: $filePath');
    try {
      pdfrxFlutterInitialize();
      print('DEBUG: pdfrxFlutterInitialize completed');
      
      final loaded = await PdfDocument.openFile(filePath);
      print('DEBUG: PdfDocument.openFile completed successfully');
      
      final oldDoc = doc;

      if (!mounted) {
        print('DEBUG: _openPdf returned early because widget is not mounted');
        loaded.dispose();
        return;
      }

      setState(() {
        doc = loaded;
        _isLoading = false;
        _errorMessage = null;
        final nodeId = _nodeId;
        print('DEBUG: _openPdf setState running, nodeId: $nodeId');
        if (nodeId != null) {
          _annotationManager?.dispose();
          _annotationManager = PageAnnotationManager(nodeId);
          print('DEBUG: _annotationManager initialized');
        }
      });

      oldDoc?.dispose();
      print('DEBUG: _openPdf completed successfully');
    } catch (e, stack) {
      print('DEBUG: _openPdf encountered error: $e');
      print('DEBUG: StackTrace: $stack');
      rethrow;
    }
  }

  @override
  void dispose() {
    doc?.dispose();
    _annotationManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_isLoading) {
      content = const Center(
        child: CircularProgressIndicator(color: Color(0xFF8E9775)),
      );
    } else if (doc == null) {
      // Empty state
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: pickAndLoadPdf,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFEAE7DC), width: 2),
                ),
                child: const Icon(
                  Icons.present_to_all,
                  size: 48,
                  color: Color(0xFF8E9775),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '匯入簡報',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3D3D3D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '或是搭配手寫筆與平板進行即時速記',
              style: TextStyle(fontSize: 12, color: Color(0xFFA8A08E)),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.redAccent,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      content = ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        itemCount: doc!.pages.length,
        itemBuilder: (context, idx) {
          final pageNum = idx + 1;
          return SlidePage(
            pageNumber: pageNum,
            annotationListenable: _annotationManager?.getPageNotifier(pageNum),
            child: PdfPageView(document: doc!, pageNumber: pageNum),
          );
        },
      );
    }

    return SizedBox(
      width: widget.width,
      child: Column(
        children: [
          PanelHeader(
            title: '課堂教材', // Changed title based on UI
            icon: Icons.picture_in_picture,
            onClose: widget.onClose,
            actions: [
              InkWell(
                onTap: _isLoading ? null : pickAndLoadPdf,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.upload_file,
                    size: 14,
                    color: Color(0xFFA8A08E),
                  ),
                ),
              ),
            ],
            index: widget.index,
          ),
          Expanded(
            child: Stack(
              children: [
                content,
                if (_annotationManager != null)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: SlideAnnotationTestControls(manager: _annotationManager!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
