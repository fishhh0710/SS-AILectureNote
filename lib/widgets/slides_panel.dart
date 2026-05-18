import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../database/database_helper.dart';
import '../database/models.dart';
import '../services/note_api_service.dart';
import 'panel_header.dart';
import 'slide_page.dart';

class SlidesPanel extends StatefulWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final int? fileId;
  final VoidCallback onNotesGenerationStarted;
  final VoidCallback onNotesGenerationFinished;
  final void Function(String message) onNotesGenerationFailed;

  const SlidesPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    required this.fileId,
    required this.onNotesGenerationStarted,
    required this.onNotesGenerationFinished,
    required this.onNotesGenerationFailed,
  });

  @override
  State<SlidesPanel> createState() => _SlidesPanelState();
}

class _SlidesPanelState extends State<SlidesPanel> {
  PdfDocument? doc;
  bool _isLoading = false;
  String? _loadedPdfPath;
  String? _errorMessage;
  String? _loadingMessage;

  @override
  void initState() {
    super.initState();
    pdfrxFlutterInitialize();
    _loadSavedPdf();
  }

  Future<void> _loadSavedPdf() async {
    final fileId = widget.fileId;
    if (fileId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _loadingMessage = 'Loading PDF...';
    });

    try {
      final node = await DatabaseHelper.instance.getNodeById(fileId);
      final savedPath = node?.filePath;

      if (savedPath == null || savedPath.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadingMessage = null;
          });
        }
        return;
      }

      if (!await File(savedPath).exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Saved PDF file was not found.';
            _loadingMessage = null;
          });
        }
        return;
      }

      await _openPdf(savedPath);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load saved PDF.';
          _loadingMessage = null;
        });
      }
    }
  }

  Future<String> _copyPdfToAppStorage(String sourcePath) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final slidesDir = Directory(p.join(documentsDir.path, 'slides'));

    if (!await slidesDir.exists()) {
      await slidesDir.create(recursive: true);
    }

    final extension = p.extension(sourcePath).toLowerCase();
    final pdfExtension = extension == '.pdf' ? extension : '.pdf';
    final fileName =
        'lecture_${widget.fileId ?? 'unlinked'}_${DateTime.now().millisecondsSinceEpoch}$pdfExtension';
    final targetPath = p.join(slidesDir.path, fileName);

    return (await File(sourcePath).copy(targetPath)).path;
  }

  Future<void> _savePdfPath(String pdfPath) async {
    final fileId = widget.fileId;
    if (fileId == null) {
      throw Exception('Missing lecture file id.');
    }

    final node = await DatabaseHelper.instance.getNodeById(fileId);
    if (node == null) {
      throw Exception('Lecture file not found.');
    }

    final updatedNode = AppNode(
      id: node.id,
      parentId: node.parentId,
      type: node.type,
      name: node.name,
      content: node.content,
      filePath: pdfPath,
      createdAt: node.createdAt,
    );

    await DatabaseHelper.instance.updateItem(updatedNode);
  }

  Future<void> _openPdf(String pdfPath) async {
    final loaded = await PdfDocument.openFile(pdfPath);
    final oldDoc = doc;

    if (!mounted) {
      loaded.dispose();
      return;
    }

    setState(() {
      doc = loaded;
      _loadedPdfPath = pdfPath;
      _isLoading = false;
      _errorMessage = null;
      _loadingMessage = null;
    });

    oldDoc?.dispose();
  }

  Future<AppNode?> _findAiNotesFolder(int fileId) async {
    final fileNode = await DatabaseHelper.instance.getNodeById(fileId);
    int? currentParentId = fileNode?.parentId;

    while (currentParentId != null) {
      final parentNode = await DatabaseHelper.instance.getNodeById(
        currentParentId,
      );

      if (parentNode?.type == 'system_folder' &&
          parentNode?.name == 'AI notes') {
        return parentNode;
      }

      final siblings = await DatabaseHelper.instance.getItemsByParent(
        currentParentId,
      );

      for (final node in siblings) {
        if (node.type == 'system_folder' && node.name == 'AI notes') {
          return node;
        }
      }

      currentParentId = parentNode?.parentId;
    }

    return null;
  }

  String _safeFolderName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'AI Notes' : sanitized;
  }

  Future<void> _saveGeneratedNotesToAiNotes(
    String sourcePdfName,
    List<GeneratedPageNote> pageNotes,
  ) async {
    final fileId = widget.fileId;
    if (fileId == null) {
      throw Exception('Missing lecture file id.');
    }

    final aiNotesFolder = await _findAiNotesFolder(fileId);
    if (aiNotesFolder?.id == null) {
      throw Exception('AI notes folder was not found.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final pdfName = p.basenameWithoutExtension(sourcePdfName);
    final notesFolderName = '${_safeFolderName(pdfName)} notes';
    final documentsDir = await getApplicationDocumentsDirectory();
    final localNotesDir = Directory(
      p.join(documentsDir.path, 'ai_notes', 'lecture_${fileId}_$timestamp'),
    );

    if (!await localNotesDir.exists()) {
      await localNotesDir.create(recursive: true);
    }

    final folderId = await DatabaseHelper.instance.insertItem(
      AppNode(
        parentId: aiNotesFolder!.id,
        type: 'folder',
        name: notesFolderName,
        filePath: localNotesDir.path,
        createdAt: DateTime.now().toIso8601String(),
      ),
    );

    for (final note in pageNotes) {
      final pageLabel = note.pageNumber.toString().padLeft(3, '0');
      final markdown = note.markdown.trim();
      final mdPath = p.join(localNotesDir.path, 'page_$pageLabel.md');

      await File(mdPath).writeAsString(
        '$markdown\n',
        encoding: utf8,
      );

      await DatabaseHelper.instance.insertItem(
        AppNode(
          parentId: folderId,
          type: 'ai_note',
          name: 'Page $pageLabel',
          content: markdown,
          filePath: mdPath,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
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
          _loadingMessage = 'Importing PDF...';
        });

        final savedPath = await _copyPdfToAppStorage(result.files.single.path!);
        await _savePdfPath(savedPath);
        await _openPdf(savedPath);

        _generateNotesInBackground(savedPath, result.files.single.name);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not import PDF.';
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _generateNotesInBackground(
    String savedPdfPath,
    String sourcePdfName,
  ) async {
    widget.onNotesGenerationStarted();
    final noteApiService = NoteApiService();

    try {
      final pageNotes = await noteApiService.generatePageNotesFromPdf(
        savedPdfPath,
      );
      await _saveGeneratedNotesToAiNotes(sourcePdfName, pageNotes);
      widget.onNotesGenerationFinished();
    } catch (_) {
      widget.onNotesGenerationFailed('Could not generate AI notes.');
    } finally {
      noteApiService.close();
    }
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
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF8E9775)),
            if (_loadingMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _loadingMessage!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFA8A08E)),
              ),
            ],
          ],
        ),
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
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
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
            child: PdfPageView(
              key: ValueKey('${_loadedPdfPath}_${idx + 1}'),
              document: doc!,
              pageNumber: idx + 1,
            ),
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
            index: widget.index,
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}
