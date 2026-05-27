import 'package:flutter/material.dart';
import 'panel_header.dart';

class TranscriptPanel extends StatefulWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final bool isRecording;
  final VoidCallback onStartRecording;
  final String liveTranscript;

  const TranscriptPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    this.isRecording = false,
    required this.onStartRecording,
    this.liveTranscript = '',
  });

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  /// Permanently stores all text that has already been finalized.
  /// This only ever grows — never cleared during a session.
  String _fullTranscript = '';

  /// The last known value of liveTranscript, used to detect when a new
  /// chunk has started (i.e., when liveTranscript becomes shorter).
  String _lastLive = '';

  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(TranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newLive = widget.liveTranscript;
    final oldLive = oldWidget.liveTranscript;

    // Detect a chunk boundary: if the incoming text is shorter than what
    // was previously shown, it means the speech service started a fresh
    // partial for a new sentence. Preserve the previous full text first.
    if (oldLive.isNotEmpty && newLive.length < oldLive.length) {
      _fullTranscript = _fullTranscript.isEmpty
          ? oldLive.trimRight()
          : '${_fullTranscript.trimRight()} ${oldLive.trimRight()}';
    }

    // If the user explicitly resets (liveTranscript goes to '' while not
    // recording), also clear our buffer so the panel returns to idle state.
    if (newLive.isEmpty && !widget.isRecording) {
      _fullTranscript = '';
    }

    _lastLive = newLive;

    // Auto-scroll to bottom when text changes
    if (newLive != oldLive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
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
    // Combine permanently saved text with the current live partial.
    // _fullTranscript only grows; liveTranscript is the latest rolling partial.
    final String displayText = _fullTranscript.isEmpty
        ? widget.liveTranscript
        : widget.liveTranscript.isEmpty
            ? _fullTranscript
            : '${_fullTranscript.trimRight()} ${widget.liveTranscript.trimLeft()}';

    Widget content;

    if (!widget.isRecording && displayText.isEmpty) {
      // No recording, no history — show the "start recording" prompt
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: widget.onStartRecording,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFEAE7DC), width: 2),
                ),
                child: const Icon(
                  Icons.mic,
                  size: 48,
                  color: Color(0xFF8E9775),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '開始錄音吧',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3D3D3D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '點擊上方圖示或右下角按鈕開始紀錄課程',
              style: TextStyle(fontSize: 12, color: Color(0xFFA8A08E)),
            ),
          ],
        ),
      );
    } else {
      content = SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // Show "Listening..." only if we have absolutely no text yet
              displayText.isEmpty && widget.isRecording
                  ? 'Listening...'
                  : displayText,
              style: const TextStyle(
                fontSize: 16,
                height: 1.7,
                color: Color(0xFF3D3D3D),
              ),
            ),
            // Blinking cursor while recording
            if (widget.isRecording)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: _BlinkingCursor(),
              ),
          ],
        ),
      );
    }

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
              title: '即時逐字稿',
              icon: Icons.subtitles,
              onClose: widget.onClose,
              index: widget.index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

// Simple blinking cursor shown while actively recording
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
      child: Container(
        width: 2,
        height: 18,
        color: const Color(0xFF8E9775),
      ),
    );
  }
}
