import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/annotation_manager.dart';
import '../viewmodels/slides_view_model.dart';
import 'annotation_test_controls.dart';
import 'panel_header.dart';
import 'slide_page.dart';

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
  PdfDocument? _document;
  late SlidesViewModel _viewModel;
  bool _isLoading = false;
  String? _errorMessage;
  PageAnnotationManager? _annotationManager;

  int? get _nodeId => int.tryParse(widget.fileId);

  @override
  void initState() {
    super.initState();
    _viewModel = SlidesViewModel(fileId: widget.fileId);
    unawaited(_loadSavedPdf());
  }

  @override
  void didUpdateWidget(covariant SlidesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _viewModel.dispose();
      _viewModel = SlidesViewModel(fileId: widget.fileId);

      final oldDocument = _document;
      _document = null;
      if (oldDocument != null) {
        unawaited(oldDocument.dispose());
      }
      _annotationManager?.dispose();
      _annotationManager = null;
      unawaited(_loadSavedPdf());
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
      final savedPath = await _viewModel.loadSavedPdfPath();

      if (savedPath == null || savedPath.isEmpty) {
        print('DEBUG: savedPath is null or empty, setting _isLoading = false');
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      if (!await File(savedPath).exists()) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Saved PDF not found. Please upload it again.';
        });
        return;
      }

      print('DEBUG: calling _openPdf');
      await _openPdf(savedPath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load saved PDF: $e';
      });
    }
  }

  Future<void> _pickAndLoadPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      final sourcePath = result?.files.single.path;
      if (sourcePath == null) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final savedPath = await _copyPdfToAppStorage(sourcePath);
      await _savePdfPath(savedPath);
      await _openPdf(savedPath);

      final onPdfUploaded = widget.onPdfUploaded;
      if (onPdfUploaded != null) {
        unawaited(onPdfUploaded(savedPath));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to upload PDF: $e';
      });
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
    await _viewModel.savePdfPath(filePath);
  }

  Future<void> _openPdf(String filePath) async {
    await pdfrxFlutterInitialize();
    final loaded = await PdfDocument.openFile(filePath);
    final oldDocument = _document;

    if (!mounted) {
      await loaded.dispose();
      return;
    }

    setState(() {
      _document = loaded;
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

    if (oldDocument != null) {
      unawaited(oldDocument.dispose());
    }
  }

  @override
  void dispose() {
    _annotationManager?.dispose();
    final document = _document;
    if (document != null) {
      unawaited(document.dispose());
    }
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Container(
        margin: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEAE7DC)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            PanelHeader(
              title: '課堂教材',
              icon: Icons.picture_in_picture,
              onClose: widget.onClose,
              actions: [
                InkWell(
                  onTap: _isLoading ? null : _pickAndLoadPdf,
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
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(
              child: Stack(
                children: [
                  _buildContent(),
                  if (_annotationManager != null)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: SlideAnnotationTestControls(
                        manager: _annotationManager!,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final document = _document;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8E9775)),
      );
    }

    if (document == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _pickAndLoadPdf,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFEAE7DC),
                      width: 2,
                    ),
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
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFFA8A08E)),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.redAccent,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      itemCount: document.pages.length,
      itemBuilder: (context, idx) {
        final pageNum = idx + 1;
        return SlidePage(
          pageNumber: pageNum,
          annotationListenable: _annotationManager?.getPageNotifier(pageNum),
          child: PdfPageView(document: document, pageNumber: pageNum),
        );
      },
    );
  }
}
