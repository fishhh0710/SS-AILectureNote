import 'package:flutter/material.dart';
import '../data/transcript_data.dart';
import 'panel_header.dart';
import 'transcript_accordion.dart';

class TranscriptPanel extends StatelessWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final bool isRecording;
  final VoidCallback onStartRecording;

  const TranscriptPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    this.isRecording = false,
    required this.onStartRecording,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (!isRecording) {
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
      content = ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: chapter4_1TranscriptData.length,
        itemBuilder: (context, idx) {
          final page = chapter4_1TranscriptData[idx];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Slide ${page.pageNumber}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFA8A08E),
                  ),
                ),
              ),
              ...page.sections.map(
                (section) => TranscriptAccordion(
                  title: section.title,
                  content: section.content,
                  defaultOpen: idx == 0,
                ),
              ),
            ],
          );
        },
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
