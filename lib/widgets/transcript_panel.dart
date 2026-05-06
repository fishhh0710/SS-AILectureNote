import 'package:flutter/material.dart';
import '../data/transcript_data.dart';
import 'panel_header.dart';
import 'transcript_accordion.dart';

class TranscriptPanel extends StatelessWidget {
  final double width;
  final int index;
  final VoidCallback onClose;

  const TranscriptPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
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
              title: 'TRANSCRIPT',
              icon: Icons.subtitles,
              onClose: onClose,
              index: index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(
              child: ListView.builder(
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
                          'Slide \${page.pageNumber}',
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
