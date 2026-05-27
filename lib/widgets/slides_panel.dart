import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';

import '../database/database_helper.dart';
import '../database/models.dart';

import 'panel_header.dart';
import 'slide_page.dart';

class SlidesPanel extends StatefulWidget {
  final double width;
  final int index;
  final String fileId;
  final VoidCallback onClose;

  const SlidesPanel({
    super.key,
    required this.width,
    required this.index,
    required this.fileId,
    required this.onClose,
  });

  @override
  State<SlidesPanel> createState() => _SlidesPanelState();
}

class _SlidesPanelState extends State<SlidesPanel> {
  PdfDocument? doc;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingPdf();
  }

  Future<void> _loadExistingPdf() async {
    final nodeId = int.tryParse(widget.fileId);
    if (nodeId == null) return;
    
    final node = await DatabaseHelper.instance.getNodeById(nodeId);
    if (node != null && node.filePath != null) {
      final file = File(node.filePath!);
      if (await file.exists()) {
        setState(() {
          _isLoading = true;
        });

        pdfrxFlutterInitialize();

        try {
          final loaded = await PdfDocument.openFile(node.filePath!);
          if (mounted) {
            setState(() {
              doc = loaded;
              _isLoading = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
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
        });

        // Copy file to application documents directory
        final dir = await getApplicationDocumentsDirectory();
        final originalFile = File(result.files.single.path!);
        final fileName = basename(originalFile.path);
        final newPath = '${dir.path}/${widget.fileId}_$fileName';
        await originalFile.copy(newPath);

        // Update database
        final nodeId = int.tryParse(widget.fileId);
        if (nodeId != null) {
          final node = await DatabaseHelper.instance.getNodeById(nodeId);
          if (node != null) {
            final updatedNode = AppNode(
              id: node.id,
              parentId: node.parentId,
              type: node.type,
              name: node.name,
              content: node.content,
              filePath: newPath,
              cloudPath: node.cloudPath,
              createdAt: node.createdAt,
            );
            await DatabaseHelper.instance.updateItem(updatedNode);
          }
        }

        pdfrxFlutterInitialize();

        final loaded = await PdfDocument.openFile(newPath);

        if (mounted) {
          setState(() {
            doc = loaded;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
            index: widget.index,
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}
