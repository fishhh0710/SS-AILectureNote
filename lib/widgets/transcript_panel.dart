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

  const TranscriptPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    this.isRecording = false,
    this.savedStatusText,
    required this.onStartRecording,
    this.liveTranscript = '',
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
              title: 'Transcript',
              icon: Icons.subtitles,
              onClose: widget.onClose,
              index: widget.index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            if (widget.savedStatusText != null)
              _StatusBanner(text: widget.savedStatusText!),
            Expanded(
              child: displayText.isEmpty && !widget.isRecording
                  ? _EmptyTranscript(onStartRecording: widget.onStartRecording)
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

  const _EmptyTranscript({required this.onStartRecording});

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
              child: const Icon(Icons.mic, size: 48, color: Color(0xFF8E9775)),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Start recording',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D3D3D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap the microphone to start live transcription.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFFA8A08E)),
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
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.isEmpty && isRecording ? 'Listening...' : text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.7,
              color: Color(0xFF3D3D3D),
            ),
          ),
          if (isRecording)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _BlinkingCursor(),
            ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
      child: Container(width: 2, height: 18, color: const Color(0xFF8E9775)),
    );
  }
}
