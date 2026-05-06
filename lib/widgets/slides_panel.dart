import 'package:flutter/material.dart';
import 'panel_header.dart';
import 'slide_page.dart';

class SlidesPanel extends StatelessWidget {
  final double width;
  final int index;
  final VoidCallback onClose;

  const SlidesPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          PanelHeader(
            title: 'SLIDES',
            icon: Icons.picture_in_picture,
            onClose: onClose,
            index: index,
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              itemCount: 3, // Mocking some slides
              itemBuilder: (context, idx) {
                return SlidePage(
                  pageNumber: idx + 1,
                  child: const Text('Slide Content Mock', style: TextStyle(color: Color(0xFFA8A08E))),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
