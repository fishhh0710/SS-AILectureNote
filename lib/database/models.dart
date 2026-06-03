// models.dart
class AppNode {
  final int? id;
  final int?
  parentId; // null indicates it's at the absolute root (e.g. Database, Temp)
  final String
  type; // 'system_folder', 'folder', 'course', 'notebook', 'recording', 'ai_note'
  final String name;
  final String?
  content; // Transcript for recordings, text for AI notes/notebooks
  final String? filePath; // Physical path for recordings/PDFs
  final String? cloudPath; // Path in Firebase Storage
  final String createdAt;

  AppNode({
    this.id,
    this.parentId,
    required this.type,
    required this.name,
    this.content,
    this.filePath,
    this.cloudPath,
    required this.createdAt,
  });

  AppNode copyWith({
    int? id,
    int? parentId,
    String? type,
    String? name,
    String? content,
    String? filePath,
    String? cloudPath,
    String? createdAt,
  }) {
    return AppNode(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      type: type ?? this.type,
      name: name ?? this.name,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      cloudPath: cloudPath ?? this.cloudPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'parentId': parentId,
    'type': type,
    'name': name,
    'content': content,
    'filePath': filePath,
    'cloudPath': cloudPath,
    'createdAt': createdAt,
  };

  factory AppNode.fromMap(Map<String, dynamic> map) => AppNode(
    id: map['id'],
    parentId: map['parentId'],
    type: map['type'],
    name: map['name'],
    content: map['content'],
    filePath: map['filePath'],
    cloudPath: map['cloudPath'],
    createdAt: map['createdAt'],
  );
}

// AI chatbot
class ChatMessage {
  final int? id;
  final int conversationId;
  final String role;
  final String content;
  final int sequenceNumber;
  final String createdAt;

  ChatMessage({
    this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.sequenceNumber,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'role': role,
      'content': content,
      'sequenceNumber': sequenceNumber,
      'createdAt': createdAt,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      conversationId: map['conversationId'],
      role: map['role'],
      content: map['content'],
      sequenceNumber: map['sequenceNumber'],
      createdAt: map['createdAt'],
    );
  }
}
