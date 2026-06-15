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
                              child: InteractiveAnnotationOverlay(
                                annotations: annotations,
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

class InteractiveAnnotationOverlay extends StatefulWidget {
  final List<Annotation> annotations;

  const InteractiveAnnotationOverlay({super.key, required this.annotations});

  @override
  State<InteractiveAnnotationOverlay> createState() =>
      _InteractiveAnnotationOverlayState();
}

class _InteractiveAnnotationOverlayState
    extends State<InteractiveAnnotationOverlay> {
  final Set<String> _pressedIds = {};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final localPos = details.localPosition;
            String? hitId;

            // Search in reverse draw order so top-most item is checked first
            for (final ann in widget.annotations.reversed) {
              if (ann is RectAnnotation) {
                final rect = Rect.fromLTWH(
                  ann.x * size.width,
                  ann.y * size.height,
                  ann.width * size.width,
                  ann.height * size.height,
                );
                if (rect.contains(localPos)) {
                  hitId = ann.id;
                  break;
                }
              }
            }

            if (hitId != null) {
              setState(() {
                _pressedIds.add(hitId!);
              });
            }
          },
          onTapUp: (details) {
            setState(() {
              _pressedIds.clear();
            });
          },
          onTapCancel: () {
            setState(() {
              _pressedIds.clear();
            });
          },
          child: CustomPaint(
            painter: PageAnnotationPainter(
              annotations: widget.annotations,
              tappedIds: _pressedIds,
            ),
          ),
        );
      },
    );
  }
}

class PageAnnotationPainter extends CustomPainter {
  final List<Annotation> annotations;
  final Set<String> tappedIds;

  PageAnnotationPainter({
    required this.annotations,
    required this.tappedIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      final showLabel = tappedIds.contains(annotation.id);
      annotation.draw(canvas, size, showLabel: showLabel);
    }
  }

  @override
  bool shouldRepaint(covariant PageAnnotationPainter oldDelegate) {
    return oldDelegate.annotations != annotations ||
        oldDelegate.tappedIds != tappedIds;
  }
}
