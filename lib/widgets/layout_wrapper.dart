import 'package:flutter/material.dart';

class LayoutWrapper extends StatelessWidget {
  final Widget child;
  final String currentPath;

  const LayoutWrapper({
    super.key,
    required this.child,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context) {
    final bool isLectureView = currentPath.startsWith('/lecture/');

    return Scaffold(
      appBar: isLectureView
          ? null
          : AppBar(
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E9775),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.menu_book, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'AI LECTURE NOTE',
                    style: TextStyle(
                      fontFamily: 'Serif',
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1.0),
                child: Container(color: const Color(0xFFEAE7DC), height: 1.0),
              ),
            ),
      body: child,
      bottomNavigationBar: isLectureView
          ? null
          : Container(
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFFDFCF8),
                border: Border(top: BorderSide(color: Color(0xFFEAE7DC))),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool showVersion = constraints.maxWidth > 550;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(),
                      if (showVersion) ...[
                        const SizedBox(width: 16),
                        const Text(
                          '版本 v1.2.0 • AI Lecture Note 智慧型工作空間',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFA8A08E),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }
}
