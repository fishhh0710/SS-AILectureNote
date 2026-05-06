import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '目前課程',
                style: TextStyle(
                  fontSize: 24,
                  fontFamily: 'Serif',
                  color: Color(0xFF3D3D3D),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  _buildCourseCard(
                    context,
                    'Computer Architecture',
                    '12 個檔案 • 4 個 AI 總結',
                  ),
                  _buildNewFileCard(context),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseCard(BuildContext context, String title, String subtitle) {
    return InkWell(
      onTap: () {
        context.push('/course/\$title');
      },
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEAE7DC), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF9F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.menu_book,
                color: Color(0xFF8E9775),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF3D3D3D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Color(0xFFA8A08E),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Syllabus 已匯入',
                style: TextStyle(
                  color: Colors.blue.shade500,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewFileCard(BuildContext context) {
    return InkWell(
      onTap: () {
        // Show new item dialog or navigate
      },
      child: Container(
        width: 320,
        height: 200,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFEAE7DC),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEAE7DC)),
              ),
              child: const Icon(Icons.add, color: Color(0xFFA8A08E), size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              '新增',
              style: TextStyle(
                fontSize: 12,
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
