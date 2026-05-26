import 'package:flutter/material.dart';
import 'panel_header.dart';

class TranscriptPanel extends StatelessWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final bool isRecording;
  final String transcriptText;
  final String? savedStatusText;
  final VoidCallback onStartRecording;

  const TranscriptPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    this.isRecording = false,
    required this.transcriptText,
    this.savedStatusText,
    required this.onStartRecording,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    final hasTranscript = transcriptText.trim().isNotEmpty;

    if (!isRecording && !hasTranscript) {
      content = Center(
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
      content = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isRecording ? Colors.red : const Color(0xFF8E9775),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isRecording
                      ? 'Recording'
                      : (savedStatusText ?? 'Transcript ready'),
                  style: const TextStyle(
                    color: Color(0xFFA8A08E),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEAE7DC)),
          Expanded(
            child: hasTranscript
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        transcriptText,
                        style: const TextStyle(
                          color: Color(0xFF3D3D3D),
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Text(
                      'Listening...',
                      style: TextStyle(
                        color: Color(0xFF3D3D3D),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

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
              title: '即時逐字稿',
              icon: Icons.subtitles,
              onClose: onClose,
              actions: [
                if (!isRecording && hasTranscript)
                  InkWell(
                    onTap: onStartRecording,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.mic,
                        size: 14,
                        color: Color(0xFFA8A08E),
                      ),
                    ),
                  ),
              ],
              index: index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
