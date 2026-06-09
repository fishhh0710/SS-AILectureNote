import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../data/annotation_model.dart';

class SlidePage extends StatelessWidget {
  final int pageNumber;
  final Widget child;
  final ValueListenable<List<Annotation>>? annotationListenable;

  const SlidePage({
    super.key,
    required this.pageNumber,
    required this.child,
    this.annotationListenable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 48),

      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main Slide Container
          Container(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  ClipRect(child: child),
                  // Drawing Overlay Layer
                  if (annotationListenable != null)
                    Positioned.fill(
                      child: ValueListenableBuilder<List<Annotation>>(
                        valueListenable: annotationListenable!,
                        builder: (context, annotations, _) {
                          if (annotations.isEmpty)
                            return const SizedBox.shrink();
                          return ClipRect(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: PageAnnotationPainter(
                                  annotations: annotations,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  // Top decoration
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF8E9775).withValues(alpha: 0.2),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(22),
                          topRight: Radius.circular(22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // left label
          Positioned(
            left: -60,
            top: 40,
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                "SLIDE ${pageNumber.toString().padLeft(2, '0')}",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8E9775).withValues(alpha: 0.3),
                  letterSpacing: 4.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PageAnnotationPainter extends CustomPainter {
  final List<Annotation> annotations;

  PageAnnotationPainter({required this.annotations});

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      annotation.draw(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant PageAnnotationPainter oldDelegate) {
    return oldDelegate.annotations != annotations;
  }
}
