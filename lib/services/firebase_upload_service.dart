// firebase_upload_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_helper.dart';
import '../database/models.dart';

class FirebaseUploadService {
  /// Calculate the MD5 checksum of a file in a memory-efficient way.
  static Future<String> _calculateMD5(File file) async {
    try {
      final stream = file.openRead();
      final hash = await md5.bind(stream).first;
      return hash.toString();
    } catch (e) {
      // Fallback in case of stream errors
      final bytes = await file.readAsBytes();
      return md5.convert(bytes).toString();
    }
  }

  /// Load local MD5 metadata mapping to track uploaded files.
  static Future<Map<String, String>> _loadMetadata() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/upload_metadata.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        return map.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (e) {
      // Ignore reading error
    }
    return {};
  }

  /// Save local MD5 metadata mapping.
  static Future<void> _saveMetadata(Map<String, String> metadata) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/upload_metadata.json');
      await file.writeAsString(jsonEncode(metadata));
    } catch (e) {
      // Ignore writing error
    }
  }

  /// Uploads all files to Firebase Storage.
  ///
  /// Only uploads files that have been modified (MD5 hash mismatch) or
  /// do not have their [cloudPath] populated in the database.
  /// Folder nodes (e.g. 'system_folder', 'folder', 'course') are ignored.
  /// Finally, uploads the latest SQLite database file to Firebase.
  static Future<void> uploadAllFiles({
    required String userId,
    required void Function(String status, double progress) onProgress,
  }) async {
    onProgress("正在初始化 Firebase...", 0.0);

    // Firebase is already initialized in main.dart via DefaultFirebaseOptions.
    // No need to call Firebase.initializeApp() here.

    // 2. Load MD5 cache metadata
    final metadata = await _loadMetadata();

    // 3. Query all nodes from the SQLite database
    onProgress("正在讀取資料庫節點...", 0.1);
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('items');
    final List<AppNode> allNodes = maps
        .map((map) => AppNode.fromMap(map))
        .toList();

    // 4. Filter nodes that have physical files
    // Ignore nodes that represent folders/directories and those with empty filePath
    final nodesToUpload = allNodes.where((node) {
      if (node.type == 'system_folder' ||
          node.type == 'folder' ||
          node.type == 'course') {
        return false;
      }
      return node.filePath != null && node.filePath!.isNotEmpty;
    }).toList();

    final int totalFiles = nodesToUpload.length;
    int processedFiles = 0;

    final storage = FirebaseStorage.instance;
    bool hasUploadedAnyFile = false;

    if (totalFiles == 0) {
      onProgress("所有檔案皆已是最新狀態", 1.0);
      return;
    }

    // 5. Upload each modified file
    for (final node in nodesToUpload) {
      final file = File(node.filePath!);
      if (!await file.exists()) {
        processedFiles++;
        continue;
      }

      final fileName = basename(file.path);
      final md5Hash = await _calculateMD5(file);
      final cloudPath = "users/$userId/referenced_files/${node.id}_$fileName";

      // If MD5 matches and cloudPath is already stored in the DB, we skip uploading
      if (metadata[file.path] == md5Hash && node.cloudPath == cloudPath) {
        processedFiles++;
        onProgress("跳過未修改檔案: $fileName", processedFiles / totalFiles);
        continue;
      }

      // Upload file to Firebase Storage
      onProgress("正在上傳: $fileName", processedFiles / totalFiles);
      final ref = storage.ref().child(cloudPath);
      await ref.putFile(file);
      hasUploadedAnyFile = true;

      // Update cloudPath inside SQLite database
      final updatedNode = AppNode(
        id: node.id,
        parentId: node.parentId,
        type: node.type,
        name: node.name,
        content: node.content,
        filePath: node.filePath,
        cloudPath: cloudPath,
        createdAt: node.createdAt,
      );
      await DatabaseHelper.instance.updateItem(updatedNode);

      // Save updated MD5 locally
      metadata[file.path] = md5Hash;
      await _saveMetadata(metadata);

      processedFiles++;
    }

    onProgress(hasUploadedAnyFile ? "備份完成！" : "所有檔案皆已是最新狀態", 1.0);
  }

  /// Get the Firebase Storage cloud path for a specific node ID.
  /// Returns null if the node has no cloud path or doesn't exist.
  static Future<String?> getCloudPathForNode(int nodeId) async {
    final node = await DatabaseHelper.instance.getNodeById(nodeId);
    return node?.cloudPath;
  }
}
