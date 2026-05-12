// models.dart
class Course {
  final int? id;
  final String title;      // 課程名稱
  final String subtitle;   // 副標題 (如: 12 個檔案 • 4 個 AI 總結)
  final String date;

  Course({this.id, required this.title, required this.subtitle, required this.date});

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'date': date,
  };

  factory Course.fromMap(Map<String, dynamic> map) => Course(
    id: map['id'],
    title: map['title'],
    subtitle: map['subtitle'],
    date: map['date'],
  );
}

class CourseItem {
  final int? id;
  final int courseId;      // 屬於哪個課程
  final int? parentId;     // 【關鍵】屬於哪個資料夾？若為 null 代表在課程的最外層
  final String type;       // 類型：'folder', 'voice', 'pdf'
  final String name;       // 檔案或資料夾名稱
  final String? filePath;  // 實體檔案路徑 (資料夾則為 null)
  final String? transcript;// 逐字稿 (僅 voice 有)

  CourseItem({
    this.id,
    required this.courseId,
    this.parentId,
    required this.type,
    required this.name,
    this.filePath,
    this.transcript,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'courseId': courseId,
    'parentId': parentId,
    'type': type,
    'name': name,
    'filePath': filePath,
    'transcript': transcript,
  };

  factory CourseItem.fromMap(Map<String, dynamic> map) => CourseItem(
    id: map['id'],
    courseId: map['courseId'],
    parentId: map['parentId'],
    type: map['type'],
    name: map['name'],
    filePath: map['filePath'],
    transcript: map['transcript'],
  );
}