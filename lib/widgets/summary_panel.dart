import 'package:flutter/material.dart';
import 'panel_header.dart';

class SummaryPanel extends StatelessWidget {
  final double width;
  final int index;
  final VoidCallback onClose;

  const SummaryPanel({
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
              title: 'SUMMARY',
              icon: Icons.auto_awesome,
              onClose: onClose,
              index: index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'The Processor: Datapath and Control',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3D3D3D),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This is a generated AI summary for the lecture.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
