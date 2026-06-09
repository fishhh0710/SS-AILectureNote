import 'package:flutter/material.dart';

import 'panel_header.dart';

class TranscriptPanel extends StatefulWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final bool isRecording;
  final String? savedStatusText;
  final VoidCallback onStartRecording;
  final String liveTranscript;
  final bool isDemoMode;
  final ValueChanged<bool>? onDemoModeChanged;

  const TranscriptPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    this.isRecording = false,
    this.savedStatusText,
    required this.onStartRecording,
    this.liveTranscript = '',
    this.isDemoMode = false,
    this.onDemoModeChanged,
  });

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant TranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.liveTranscript != oldWidget.liveTranscript) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayText = widget.liveTranscript.trim();

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
              title: widget.isDemoMode ? '即時逐字稿 (Demo)' : '即時逐字稿',
              icon: Icons.subtitles,
              onClose: widget.onClose,
              index: widget.index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            if (widget.savedStatusText != null)
              _StatusBanner(text: widget.savedStatusText!),
            Expanded(
              child: displayText.isEmpty && !widget.isRecording
                  ? _EmptyTranscript(
                      onStartRecording: widget.onStartRecording,
                      isDemoMode: widget.isDemoMode,
                      onDemoModeChanged: widget.onDemoModeChanged,
                    )
                  : _TranscriptBody(
                      controller: _scrollController,
                      text: displayText,
                      isRecording: widget.isRecording,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String text;

  const _StatusBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F2EA),
        border: Border(bottom: BorderSide(color: Color(0xFFEAE7DC))),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF6F735E),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyTranscript extends StatelessWidget {
  final VoidCallback onStartRecording;
  final bool isDemoMode;
  final ValueChanged<bool>? onDemoModeChanged;

  const _EmptyTranscript({
    required this.onStartRecording,
    required this.isDemoMode,
    this.onDemoModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onStartRecording,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFEAE7DC), width: 2),
              ),
              child: Icon(
                isDemoMode ? Icons.play_arrow : Icons.mic,
                size: 48,
                color: const Color(0xFF8E9775),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isDemoMode ? '開始展示模擬' : '開始錄音吧',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D3D3D),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDemoMode
                ? '點擊上方播放按鈕，模擬即時課程逐字稿。'
                : '點擊上方圖示或右下角按鈕開始紀錄課程',
            style: const TextStyle(fontSize: 12, color: Color(0xFFA8A08E)),
          ),
          const SizedBox(height: 32),
          if (onDemoModeChanged != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '展示模擬模式',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6F735E),
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: isDemoMode,
                  onChanged: onDemoModeChanged,
                  activeColor: const Color(0xFF8E9775),
                  activeTrackColor: const Color(0xFFDCD7C9),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TranscriptBody extends StatelessWidget {
  final ScrollController controller;
  final String text;
  final bool isRecording;

  const _TranscriptBody({
    required this.controller,
    required this.text,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> chunks = text.split('\n\n').where((s) => s.trim().isNotEmpty).toList();

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(20),
      itemCount: chunks.length + (chunks.isEmpty && isRecording ? 1 : 0),
      itemBuilder: (context, index) {
        if (chunks.isEmpty) {
          return const _TranscriptChunkCard(
            text: '',
            isFinished: false,
            index: 0,
          );
        }

        final chunkText = chunks[index];
        final isLast = index == chunks.length - 1;
        final isFinished = !isRecording || !isLast;

        return _TranscriptChunkCard(
          text: chunkText,
          isFinished: isFinished,
          index: index,
        );
      },
    );
  }
}

class _TranscriptChunkCard extends StatelessWidget {
  final String text;
  final bool isFinished;
  final int index;

  const _TranscriptChunkCard({
    required this.text,
    required this.isFinished,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFinished ? const Color(0xFFEAE7DC) : const Color(0xFF8E9775),
          width: isFinished ? 1.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isFinished ? '段落 ${index + 1}' : '即時語音辨識中...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isFinished ? const Color(0xFF8E9775) : const Color(0xFFC88A58),
                ),
              ),
              if (!isFinished)
                const _PulsingDot(),
            ],
          ),
          const SizedBox(height: 10),
          if (text.isEmpty && !isFinished)
            const Text(
              'Listening...',
              style: TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: Color(0xFFA8A08E),
              ),
            )
          else
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Color(0xFF3D3D3D),
                ),
                children: [
                  TextSpan(text: text),
                  if (!isFinished)
                    const WidgetSpan(
                      child: Padding(
                        padding: EdgeInsets.only(left: 2),
                        child: _BlinkingCursorInline(),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFC88A58),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _BlinkingCursorInline extends StatefulWidget {
  const _BlinkingCursorInline();

  @override
  State<_BlinkingCursorInline> createState() => _BlinkingCursorInlineState();
}

class _BlinkingCursorInlineState extends State<_BlinkingCursorInline> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 16,
        color: const Color(0xFF8E9775),
      ),
    );
  }
}
