import 'package:flutter/material.dart';

abstract class Annotation {
  final String id; // Unique ID (Format: type_timestamp_random)
  final int pageIndex; // 1-indexed
  final String type; // "rect" | "text" ...
  final Color color;

  Annotation({
    required this.id,
    required this.pageIndex,
    required this.type,
    required this.color,
  });

  Map<String, dynamic> toJson();

  factory Annotation.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'rect':
        return RectAnnotation.fromJson(json);
      case 'text':
        return TextAnnotation.fromJson(json);
      default:
        throw UnimplementedError('Unsupported annotation type: $type');
    }
  }

  void draw(Canvas canvas, Size size, {bool showLabel = false});
}

// 1. Rectangle Annotation (using relative coordinates 0.0 ~ 1.0)
class RectAnnotation extends Annotation {
  final double x;
  final double y;
  final double width;
  final double height;
  final double strokeWidth;
  final String? label;

  RectAnnotation({
    required super.id,
    required super.pageIndex,
    required super.color,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.strokeWidth = 2.0,
    this.label,
  }) : super(type: 'rect');

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'pageIndex': pageIndex,
    'type': type,
    'color': '#${color.value.toRadixString(16).padLeft(8, '0')}',
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'strokeWidth': strokeWidth,
    'label': label,
  };

  factory RectAnnotation.fromJson(Map<String, dynamic> json) {
    return RectAnnotation(
      id: json['id'] as String,
      pageIndex: json['pageIndex'] as int,
      color: Color(int.parse(json['color'].replaceAll('#', ''), radix: 16)),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      label: json['label'] as String?,
    );
  }

  @override
  void draw(Canvas canvas, Size size, {bool showLabel = false}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rect = Rect.fromLTWH(
      x * size.width,
      y * size.height,
      width * size.width,
      height * size.height,
    );
    canvas.drawRect(rect, paint);

    if (showLabel && label != null && label!.isNotEmpty) {
      final double scaledFontSize = 10.0 * (size.width / 850.0);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: scaledFontSize > 8.0 ? scaledFontSize : 8.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      final bgPaint = Paint()..color = color;
      final double maxAllowedWidth = size.width * (1.0 - x);
      textPainter.layout(
        maxWidth: maxAllowedWidth > 50.0 ? maxAllowedWidth : 50.0,
      );

      double textY = (y * size.height) - textPainter.height - 4;
      if (textY < 2) {
        textY = (y * size.height) + 4;
      }

      final textOffset = Offset(x * size.width, textY);
      final bgRect = Rect.fromLTWH(
        textOffset.dx,
        textOffset.dy,
        textPainter.width + 4,
        textPainter.height + 2,
      );

      canvas.drawRect(bgRect, bgPaint);
      textPainter.paint(canvas, textOffset.translate(2, 1));
    }
  }
}

// 2. Text Annotation (includes font family and wrap options)
class TextAnnotation extends Annotation {
  final double x;
  final double y;
  final String text;
  final double fontSize;
  final String? fontFamily;
  final bool autoWrap;

  TextAnnotation({
    required super.id,
    required super.pageIndex,
    required super.color,
    required this.x,
    required this.y,
    required this.text,
    this.fontSize = 14.0,
    this.fontFamily,
    this.autoWrap = true,
  }) : super(type: 'text');

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'pageIndex': pageIndex,
    'type': type,
    'color': '#${color.value.toRadixString(16).padLeft(8, '0')}',
    'x': x,
    'y': y,
    'text': text,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'autoWrap': autoWrap,
  };

  factory TextAnnotation.fromJson(Map<String, dynamic> json) {
    return TextAnnotation(
      id: json['id'] as String,
      pageIndex: json['pageIndex'] as int,
      color: Color(int.parse(json['color'].replaceAll('#', ''), radix: 16)),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      text: json['text'] as String,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      fontFamily: json['fontFamily'] as String?,
      autoWrap: json['autoWrap'] as bool? ?? true,
    );
  }

  @override
  void draw(Canvas canvas, Size size, {bool showLabel = false}) {
    // 💡 根據投影片當前寬度與基準寬度 (850.0) 進行比例縮放，避免縮放時文字尺寸錯位
    final double scaledFontSize = fontSize * (size.width / 850.0);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: scaledFontSize,
          fontFamily: fontFamily,
          backgroundColor: const Color(
            0xAAFFFFFF,
          ), // semi-transparent background to prevent overlaps
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    double? constrainedWidth;
    if (autoWrap) {
      final double maxAllowedWidth = size.width * (1.0 - x);
      constrainedWidth = maxAllowedWidth > 0 ? maxAllowedWidth : size.width;
    }

    textPainter.layout(maxWidth: constrainedWidth ?? double.infinity);
    textPainter.paint(canvas, Offset(x * size.width, y * size.height));
  }
}
