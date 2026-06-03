import 'package:flutter/material.dart';

class PanelHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final VoidCallback? onClose;
  final List<Widget>? actions;
  final bool isDraggable;
  final int? index;

  const PanelHeader({
    super.key,
    required this.title,
    this.icon,
    this.onClose,
    this.actions,
    this.isDraggable = true,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 40), // Left spacer
          Expanded(
            child: Center(
              child: MouseRegion(
                cursor: isDraggable
                    ? SystemMouseCursors.grab
                    : SystemMouseCursors.basic,
                child: Builder(
                  builder: (context) {
                    final content = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDraggable)
                          const Icon(
                            Icons.drag_indicator,
                            size: 14,
                            color: Color(0xFFA8A08E),
                          ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(
                                0xFFEAE7DC,
                              ).withValues(alpha: 0.5),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                Icon(
                                  icon,
                                  size: 14,
                                  color: const Color(0xFFA8A08E),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                title.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF8E9775),
                                  letterSpacing: 2.0,
                                ),
                              ),
                              if (actions != null) ...[
                                const SizedBox(width: 8),
                                ...actions!,
                              ],
                              if (onClose != null) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: onClose,
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Color(0xFFA8A08E),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );

                    if (isDraggable && index != null) {
                      return ReorderableDragStartListener(
                        index: index!,
                        child: content,
                      );
                    }
                    return content;
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 40), // Right spacer
        ],
      ),
    );
  }
}
