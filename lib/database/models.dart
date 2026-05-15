// models.dart
class AppNode {
  final int? id;
  final int? parentId; // null indicates it's at the absolute root (e.g. Database, Temp)
  final String type;   // 'system_folder', 'folder', 'course', 'notebook', 'recording', 'ai_note'
  final String name;
  final String? content;  // Transcript for recordings, text for AI notes/notebooks
  final String? filePath; // Physical path for recordings/PDFs
  final String createdAt;

  AppNode({
    this.id,
    this.parentId,
    required this.type,
    required this.name,
    this.content,
    this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'parentId': parentId,
    'type': type,
    'name': name,
    'content': content,
    'filePath': filePath,
    'createdAt': createdAt,
  };

  factory AppNode.fromMap(Map<String, dynamic> map) => AppNode(
    id: map['id'],
    parentId: map['parentId'],
    type: map['type'],
    name: map['name'],
    content: map['content'],
    filePath: map['filePath'],
    createdAt: map['createdAt'],
  );
}