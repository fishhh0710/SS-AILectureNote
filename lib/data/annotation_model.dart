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

  void draw(
    Canvas canvas,
    Size size, {
    bool showLabel = false,
    bool rectOnly = false,
    bool labelOnly = false,
  });
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
    'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
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
  void draw(
    Canvas canvas,
    Size size, {
    bool showLabel = false,
    bool rectOnly = false,
    bool labelOnly = false,
  }) {
    final double scale = size.width / 850.0;

    if (!labelOnly) {
      final rect = Rect.fromLTWH(
        x * size.width,
        y * size.height,
        width * size.width,
        height * size.height,
      );

      final double radius = 6.0 * scale;
      final double minRadius = 4.0;
      final double finalRadius = radius > minRadius ? radius : minRadius;
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(finalRadius));

      // Draw subtle fill inside bounding box
      final fillPaint = Paint()
        ..color = color.withValues(alpha: showLabel ? 0.12 : 0.04)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, fillPaint);

      // Draw stroke outline
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = showLabel ? (strokeWidth + 1.0) : strokeWidth;
      canvas.drawRRect(rrect, strokePaint);
    }

    if (showLabel && !rectOnly && label != null && label!.isNotEmpty) {
      final double scaledFontSize = 13.0 * scale;
      final double minFontSize = 11.0;
      final double finalFontSize = scaledFontSize > minFontSize ? scaledFontSize : minFontSize;

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: finalFontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      final double horizontalPadding = 8.0 * scale;
      final double minHorizontalPadding = 6.0;
      final double finalHPadding = horizontalPadding > minHorizontalPadding ? horizontalPadding : minHorizontalPadding;

      final double verticalPadding = 4.0 * scale;
      final double minVerticalPadding = 3.0;
      final double finalVPadding = verticalPadding > minVerticalPadding ? verticalPadding : minVerticalPadding;

      final double maxAllowedWidth = (size.width * (1.0 - x)) - (finalHPadding * 2);
      textPainter.layout(
        maxWidth: maxAllowedWidth > 50.0 ? maxAllowedWidth : 50.0,
      );

      final double badgeWidth = textPainter.width + (finalHPadding * 2);
      final double badgeHeight = textPainter.height + (finalVPadding * 2);

      double textY = (y * size.height) - badgeHeight - (4.0 * scale);
      if (textY < 2.0) {
        textY = (y * size.height) + (height * size.height) + (4.0 * scale);
      }

      double textX = x * size.width;
      if (textX + badgeWidth > size.width) {
        textX = size.width - badgeWidth - 4.0;
      }
      if (textX < 4.0) {
        textX = 4.0;
      }

      final bgRect = Rect.fromLTWH(
        textX,
        textY,
        badgeWidth,
        badgeHeight,
      );
      final badgeRRect = RRect.fromRectAndRadius(bgRect, Radius.circular(5.0 * scale));

      // Draw subtle shadow under label badge
      final shadowPath = Path()..addRRect(badgeRRect);
      canvas.drawShadow(shadowPath, const Color(0x66000000), 4.0, true);

      final bgPaint = Paint()..color = color;
      canvas.drawRRect(badgeRRect, bgPaint);

      textPainter.paint(
        canvas,
        Offset(textX + finalHPadding, textY + finalVPadding),
      );
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
    'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
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
  void draw(
    Canvas canvas,
    Size size, {
    bool showLabel = false,
    bool rectOnly = false,
    bool labelOnly = false,
  }) {
    if (rectOnly) return;
    final double scale = size.width / 850.0;
    final double scaledFontSize = fontSize * scale;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: scaledFontSize,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    final double horizontalPadding = 10.0 * scale;
    final double minHorizontalPadding = 8.0;
    final double finalHPadding = horizontalPadding > minHorizontalPadding ? horizontalPadding : minHorizontalPadding;

    final double verticalPadding = 6.0 * scale;
    final double minVerticalPadding = 4.0;
    final double finalVPadding = verticalPadding > minVerticalPadding ? verticalPadding : minVerticalPadding;

    double? constrainedWidth;
    if (autoWrap) {
      final double maxAllowedWidth = (size.width * (1.0 - x)) - (finalHPadding * 2);
      constrainedWidth = maxAllowedWidth > 0 ? maxAllowedWidth : (size.width - (finalHPadding * 2));
    }

    textPainter.layout(maxWidth: constrainedWidth ?? double.infinity);

    final double textX = x * size.width;
    final double textY = y * size.height;

    final cardRect = Rect.fromLTWH(
      textX,
      textY,
      textPainter.width + (finalHPadding * 2),
      textPainter.height + (finalVPadding * 2),
    );

    final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(8.0 * scale));

    // Determine adaptive background card color based on luminance of the text color
    final double luminance = color.computeLuminance();
    final Color cardBgColor;
    if (luminance > 0.5) {
      // Light text color -> Dark background card
      cardBgColor = const Color(0xEE1E1E24);
    } else {
      // Dark text color -> Light background card
      cardBgColor = const Color(0xF4F5F7F9);
    }

    // Draw card drop shadow
    final shadowPath = Path()..addRRect(cardRRect);
    canvas.drawShadow(shadowPath, const Color(0x66000000), 3.0, true);

    // Draw card background
    final bgPaint = Paint()..color = cardBgColor;
    canvas.drawRRect(cardRRect, bgPaint);

    // Draw text inside the card with padding offset
    textPainter.paint(
      canvas,
      Offset(textX + finalHPadding, textY + finalVPadding),
    );
  }
}
