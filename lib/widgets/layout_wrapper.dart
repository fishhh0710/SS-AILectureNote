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
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8E9775),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'AI 教學助手：Jenny 的個人資料已啟用',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFA8A08E),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    '版本 v1.2.0 • AI Lecture Note 智慧型工作空間',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFA8A08E),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
