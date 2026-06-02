import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../database/database_helper.dart';
import '../database/models.dart';
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
  bool _isLoading = false;
  String? _errorMessage;

  int? get _nodeId => int.tryParse(widget.fileId);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedPdf());
  }

  @override
  void didUpdateWidget(covariant SlidesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      final oldDocument = _document;
      _document = null;
      if (oldDocument != null) {
        unawaited(oldDocument.dispose());
      }
      unawaited(_loadSavedPdf());
    }
  }

  Future<void> _loadSavedPdf() async {
    final nodeId = _nodeId;
    if (nodeId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final node = await DatabaseHelper.instance.getNodeById(nodeId);
      final savedPath = node?.filePath;

      if (savedPath == null || savedPath.isEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
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
        cloudPath: node.cloudPath,
        createdAt: node.createdAt,
      ),
    );
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
    });

    if (oldDocument != null) {
      unawaited(oldDocument.dispose());
    }
  }

  @override
  void dispose() {
    final document = _document;
    if (document != null) {
      unawaited(document.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Column(
        children: [
          PanelHeader(
            title: 'Slides',
            icon: Icons.picture_in_picture,
            onClose: widget.onClose,
            actions: [
              InkWell(
                onTap: _isLoading ? null : _pickAndLoadPdf,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(4),
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
          Expanded(child: _buildContent()),
        ],
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
                'Upload PDF slides',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3D3D3D),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a PDF to preview slides and generate AI notes.',
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
      itemBuilder: (context, index) {
        return SlidePage(
          pageNumber: index + 1,
          child: PdfPageView(document: document, pageNumber: index + 1),
        );
      },
    );
  }
}
