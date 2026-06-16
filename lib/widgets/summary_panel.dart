import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/ai_page_note.dart';
import 'panel_header.dart';

class SummaryPanel extends StatelessWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final List<AiPageNote> notes;
  final bool isGenerating;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Stream<Map<String, dynamic>>? segmentStream;
  final int totalPages;
  final int completedPages;
  final int totalBatches;
  final int completedBatches;

  const SummaryPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    this.notes = const [],
    this.isGenerating = false,
    this.errorMessage,
    this.onRetry,
    this.segmentStream,
    this.totalPages = 0,
    this.completedPages = 0,
    this.totalBatches = 0,
    this.completedBatches = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
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
              title: 'AI 筆記',
              icon: Icons.auto_awesome,
              onClose: onClose,
              index: index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final progressText = totalPages > 0
        ? '已完成 $completedPages / $totalPages 頁'
        : '正在驗證登入並上傳 PDF，完成後會顯示逐頁進度';
    if (isGenerating && notes.isEmpty) {
      return _CenteredMessage(
        icon: Icons.auto_awesome,
        title: '正在生成 AI 筆記',
        subtitle: progressText,
        showProgress: true,
      );
    }

    if (notes.isEmpty && errorMessage != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        title: 'AI 筆記生成失敗',
        subtitle: errorMessage!,
        actionLabel: onRetry == null ? null : '重試',
        onAction: onRetry,
      );
    }

    if (notes.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.description_outlined,
        title: '還沒有 AI 筆記',
        subtitle: '上傳簡報後會自動產生逐頁筆記',
      );
    }

    return Column(
      children: [
        if (isGenerating)
          _StatusBanner(
            text: totalBatches > 0
                ? '正在更新 AI 筆記：$completedPages / $totalPages 頁，'
                      '$completedBatches / $totalBatches 批'
                : '正在更新 AI 筆記...',
            showProgress: true,
          ),
        if (!isGenerating && errorMessage != null)
          _StatusBanner(text: errorMessage!, isError: true),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, idx) {
              return _PageNoteCard(note: notes[idx]);
            },
          ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF8E9775),
                ),
              )
            else
              Icon(icon, size: 42, color: const Color(0xFF8E9775)),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3D3D3D),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.grey.shade600,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String text;
  final bool showProgress;
  final bool isError;

  const _StatusBanner({
    required this.text,
    this.showProgress = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : const Color(0xFFF5F2EA),
        border: const Border(bottom: BorderSide(color: Color(0xFFEAE7DC))),
      ),
      child: Row(
        children: [
          if (showProgress)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF8E9775),
              ),
            )
          else
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color: isError ? Colors.redAccent : const Color(0xFF8E9775),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isError ? Colors.redAccent : const Color(0xFF6F735E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageNoteCard extends StatelessWidget {
  final AiPageNote note;

  const _PageNoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAE7DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Page ${note.pageNumber}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8E9775),
            ),
          ),
          MarkdownBody(
            data: note.markdown,
            selectable: true,
            softLineBreak: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.55,
                  ),
                  h1: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D3D3D),
                    height: 1.3,
                  ),
                  h2: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D3D3D),
                    height: 1.3,
                  ),
                  h3: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D3D3D),
                    height: 1.3,
                  ),
                  strong: const TextStyle(fontWeight: FontWeight.w700),
                  listBullet: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.55,
                  ),
                  blockSpacing: 8,
                ),
          ),
        ],
      ),
    );
  }
}
