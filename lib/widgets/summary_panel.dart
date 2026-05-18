import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../database/database_helper.dart';
import '../database/models.dart';
import 'panel_header.dart';

class SummaryPanel extends StatefulWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final int? fileId;
  final bool isLoadingNotes;
  final String? errorMessage;
  final int reloadToken;

  const SummaryPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    required this.fileId,
    required this.isLoadingNotes,
    required this.errorMessage,
    required this.reloadToken,
  });

  @override
  State<SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<SummaryPanel> {
  late Future<List<String>> _markdownFuture;

  @override
  void initState() {
    super.initState();
    _markdownFuture = _loadMarkdownNotes();
  }

  @override
  void didUpdateWidget(covariant SummaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.fileId != widget.fileId ||
        oldWidget.reloadToken != widget.reloadToken) {
      _markdownFuture = _loadMarkdownNotes();
    }
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

  Future<List<String>> _loadMarkdownNotes() async {
    final fileId = widget.fileId;
    if (fileId == null) return [];

    final aiNotesFolder = await _findAiNotesFolder(fileId);
    if (aiNotesFolder?.id == null) return [];

    final noteFolders = await DatabaseHelper.instance.getItemsByParent(
      aiNotesFolder!.id,
    );
    final folders = noteFolders.where((node) => node.type == 'folder').toList();
    final latestNoteFolder = folders.isEmpty ? null : folders.first;

    if (latestNoteFolder?.id == null) return [];

    final noteNodes = await DatabaseHelper.instance.getItemsByParent(
      latestNoteFolder!.id,
    );
    noteNodes.sort((a, b) => a.name.compareTo(b.name));

    final markdowns = <String>[];

    for (final node in noteNodes) {
      if (node.type != 'ai_note') continue;

      final filePath = node.filePath;
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          markdowns.add(await file.readAsString());
          continue;
        }
      }

      if (node.content != null && node.content!.isNotEmpty) {
        markdowns.add(node.content!);
      }
    }

    return markdowns;
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No AI notes yet.',
        style: TextStyle(fontSize: 14, color: Color(0xFFA8A08E)),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF8E9775)),
          SizedBox(height: 16),
          Text(
            'Generating AI notes...',
            style: TextStyle(fontSize: 12, color: Color(0xFFA8A08E)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(fontSize: 14, color: Colors.redAccent),
      ),
    );
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
              title: 'SUMMARY',
              icon: Icons.auto_awesome,
              onClose: widget.onClose,
              index: widget.index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(
              child: widget.isLoadingNotes
                  ? _buildLoadingState()
                  : widget.errorMessage != null
                      ? _buildErrorState(widget.errorMessage!)
                      : FutureBuilder<List<String>>(
                future: _markdownFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF8E9775),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Could not load AI notes.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.redAccent,
                        ),
                      ),
                    );
                  }

                  final markdowns = snapshot.data ?? [];
                  if (markdowns.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      for (final markdown in markdowns) ...[
                        MarkdownBody(data: markdown),
                        const SizedBox(height: 32),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
