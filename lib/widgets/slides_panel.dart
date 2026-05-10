import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'panel_header.dart';
import 'slide_page.dart';

class SlidesPanel extends StatefulWidget {
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
  State<SlidesPanel> createState() => _SlidesPanelState();
}

class _SlidesPanelState extends State<SlidesPanel> {
  PdfDocument? doc;

  @override
  void initState() {
    super.initState();
    loadPdf();
  }

  Future<void> loadPdf() async {
    pdfrxFlutterInitialize();

    final loaded = await PdfDocument.openAsset(
      'assets/sample_pdf.pdf',
    );

    setState(() {
      doc = loaded;
    });
  }

  @override
  void dispose() {
    doc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (doc == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SizedBox(
      width: widget.width,
      child: Column(
        children: [
          PanelHeader(
            title: 'SLIDES',
            icon: Icons.picture_in_picture,
            onClose: widget.onClose,
            index: widget.index,
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: 48,
                vertical: 24,
              ),

              itemCount: doc!.pages.length,

              itemBuilder: (context, idx) {
                final page = doc!.pages[idx];
                final aspectRatio = page.width / page.height;

                return Center(
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: SlidePage(
                      pageNumber: idx + 1,
                      aspectRatio: aspectRatio,
                      child: PdfPageView(
                        document: doc!,
                        pageNumber: idx + 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}