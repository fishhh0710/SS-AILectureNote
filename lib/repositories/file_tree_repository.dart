import '../database/database_helper.dart';
import '../database/models.dart';
import '../services/firebase_upload_service.dart';

typedef BackupProgressCallback = void Function(String status, double progress);

class FileTreeSnapshot {
  const FileTreeSnapshot({required this.parent, required this.children});

  final AppNode parent;
  final List<AppNode> children;
}

class FileTreeRepository {
  FileTreeRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<FileTreeSnapshot?> loadDatabaseRoot() async {
    final root = await _dbHelper.getDatabaseRootFolder();
    if (root == null) return null;

    final children = await _dbHelper.getItemsByParent(root.id);
    return FileTreeSnapshot(parent: root, children: children);
  }

  Future<FileTreeSnapshot?> loadNode(int nodeId) async {
    final node = await _dbHelper.getNodeById(nodeId);
    if (node == null) return null;

    final children = await _dbHelper.getItemsByParent(node.id);
    return FileTreeSnapshot(parent: node, children: children);
  }

  Future<AppNode?> getNode(int nodeId) {
    return _dbHelper.getNodeById(nodeId);
  }

  Future<void> createChild({
    required int parentId,
    required String type,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Item name cannot be empty.');
    }

    final node = AppNode(
      parentId: parentId,
      type: type,
      name: trimmedName,
      createdAt: DateTime.now().toIso8601String(),
    );

    if (type == 'course') {
      await _dbHelper.insertCourse(node);
    } else {
      await _dbHelper.insertItem(node);
    }
  }

  Future<void> renameNode(AppNode node, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Item name cannot be empty.');
    }

    await _dbHelper.updateItem(node.copyWith(name: trimmedName));
  }

  Future<void> updateFilePath({
    required int nodeId,
    required String filePath,
  }) async {
    final node = await _dbHelper.getNodeById(nodeId);
    if (node == null) {
      throw Exception(
        'Cannot update file path because item $nodeId not found.',
      );
    }

    await _dbHelper.updateItem(node.copyWith(filePath: filePath));
  }

  Future<void> deleteNode(AppNode node) async {
    final id = node.id;
    if (id == null) {
      throw Exception('Cannot delete an item without an id.');
    }

    await _dbHelper.deleteItem(id);
  }

  Future<void> backupToFirebase({
    required String userId,
    required BackupProgressCallback onProgress,
  }) {
    return FirebaseUploadService.uploadAllFiles(
      userId: userId,
      onProgress: onProgress,
    );
  }
}
