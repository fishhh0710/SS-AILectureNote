import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../database/models.dart';
import 'panel_header.dart';
import 'slide_page.dart';

class SlidesPanel extends StatefulWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final String fileId;

  const SlidesPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    required this.fileId,
  });

  @override
  State<SlidesPanel> createState() => _SlidesPanelState();
}

class _SlidesPanelState extends State<SlidesPanel> {
  PdfDocument? doc;
  bool _isLoading = false;
  String? _errorMessage;

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
      _loadSavedPdf();
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
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      if (!await File(savedPath).exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Saved PDF not found. Please upload it again.';
          });
        }
        return;
      }

      await _openPdf(savedPath);
    } catch (e) {
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
    pdfrxFlutterInitialize();
    final loaded = await PdfDocument.openFile(filePath);
    final oldDoc = doc;

    if (!mounted) {
      loaded.dispose();
      return;
    }

    setState(() {
      doc = loaded;
      _isLoading = false;
      _errorMessage = null;
    });

    oldDoc?.dispose();
  }

  @override
  void dispose() {
    doc?.dispose();
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
          return SlidePage(
            pageNumber: idx + 1,
            child: PdfPageView(document: doc!, pageNumber: idx + 1),
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
          Expanded(child: content),
        ],
      ),
    );
  }
}
