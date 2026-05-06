import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CourseDetails extends StatelessWidget {
  final String courseId;

  const CourseDetails({super.key, required this.courseId});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => context.push('/'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 14, color: Color(0xFFA8A08E)),
                    SizedBox(width: 8),
                    Text(
                      '返回所有課程',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA8A08E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                courseId,
                style: const TextStyle(
                  fontSize: 36,
                  fontFamily: 'Serif',
                  color: Color(0xFF3D3D3D),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '課程大綱 • 2023 秋季',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFA8A08E),
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                '課堂教材',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFA8A08E),
                  letterSpacing: 3.0,
                ),
              ),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _buildFileItem(context, '語音紀錄', '資料夾', Icons.folder, isFolder: true),
                  _buildFileItem(context, 'AI 筆記', '資料夾', Icons.folder, isFolder: true),
                  _buildFileItem(context, '第一章_導論.pdf', 'pdf', Icons.picture_as_pdf),
                  _buildFileItem(context, 'Chapter 4.1', 'lecture', Icons.description),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileItem(BuildContext context, String name, String type, IconData icon, {bool isFolder = false}) {
    return InkWell(
      onTap: () {
        if (!isFolder) {
          context.push('/lecture/\$courseId/\$name');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAE7DC)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isFolder ? const Color(0xFFF5F2EA) : const Color(0xFFFAF9F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isFolder ? const Color(0xFF8E9775) : const Color(0xFFA8A08E)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF3D3D3D),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                     type.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFA8A08E),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.more_vert, color: Color(0xFFEAE7DC)),
          ],
        ),
      ),
    );
  }
}
