// database_helper.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models.dart';
import '../data/annotation_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // Using a new filename to avoid schema conflicts with the old design
    _database = await _initDB('lecture_system_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE items ADD COLUMN cloudPath TEXT');
      } catch (e) {
        // Column may already exist
      }
    }
  }

  Future _createDB(Database db, int version) async {
    // Single unified table for the recursive file system
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parentId INTEGER, 
        type TEXT NOT NULL, 
        name TEXT NOT NULL,
        content TEXT,
        filePath TEXT,
        cloudPath TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (parentId) REFERENCES items (id) ON DELETE CASCADE
      )
    ''');

    final now = DateTime.now().toIso8601String();

    // 1. Create the absolute root system folders (Home level)
    await db.insert('items', {
      'parentId': null,
      'type': 'system_folder',
      'name': 'Database',
      'createdAt': now
    });

    await db.insert('items', {
      'parentId': null,
      'type': 'system_folder',
      'name': 'Temp',
      'createdAt': now
    });
  }

  // ================= 1. Standard CRUD =================

  Future<int> insertItem(AppNode item) async {
    final db = await instance.database;
    return await db.insert('items', item.toMap());
  }

  // Fetch items inside a specific folder (or root if parentId is null)
  Future<List<AppNode>> getItemsByParent(int? parentId) async {
    final db = await instance.database;
    final whereString = parentId == null ? 'parentId IS NULL' : 'parentId = ?';
    final args = parentId == null ? [] : [parentId];

    final result = await db.query('items', where: whereString, whereArgs: args, orderBy: 'createdAt DESC');
    return result.map((map) => AppNode.fromMap(map)).toList();
  }

  Future<int> deleteItem(int id) async {
    final db = await instance.database;
    // Due to ON DELETE CASCADE, deleting a folder/course will delete all nested items automatically.
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateItem(AppNode item) async {
    final db = await instance.database;
    return await db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  // ================= 2. Specialized Operations =================

  // Create a Course and automatically generate its nested system folders
  Future<int> insertCourse(AppNode course) async {
    final db = await instance.database;
    
    // Ensure the item type is course
    if (course.type != 'course') {
      throw Exception('Item type must be "course"');
    }

    final courseId = await db.insert('items', course.toMap());
    final now = DateTime.now().toIso8601String();

    // Auto-create "Recordings" system folder inside this course
    await db.insert('items', {
      'parentId': courseId,
      'type': 'system_folder',
      'name': 'Recordings',
      'createdAt': now
    });

    // Auto-create "AI notes" system folder inside this course
    await db.insert('items', {
      'parentId': courseId,
      'type': 'system_folder',
      'name': 'AI notes',
      'createdAt': now
    });

    return courseId;
  }

  // Helper to fetch the root "Database" folder id easily
  Future<AppNode?> getDatabaseRootFolder() async {
    final db = await instance.database;
    final result = await db.query('items', where: 'parentId IS NULL AND name = ?', whereArgs: ['Database']);
    if (result.isNotEmpty) {
      return AppNode.fromMap(result.first);
    }
    return null;
  }

  // Helper to fetch the root "Temp" folder id easily
  Future<AppNode?> getTempRootFolder() async {
    final db = await instance.database;
    final result = await db.query('items', where: 'parentId IS NULL AND name = ?', whereArgs: ['Temp']);
    if (result.isNotEmpty) {
      return AppNode.fromMap(result.first);
    }
    return null;
  }

  // Fetch a single node by its ID
  Future<AppNode?> getNodeById(int id) async {
    final db = await instance.database;
    final result = await db.query('items', where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) {
      return AppNode.fromMap(result.first);
    }
    return null;
  }
}

extension DatabaseHelperAnnotationExtension on DatabaseHelper {
  // 1. 取得指定 PDF 某頁的標記
  Future<List<Annotation>> getPageAnnotations(int pdfId, int pageIndex) async {
    final db = await database;
    final result = await db.query(
      'items',
      where: 'parentId = ? AND type = ? AND name = ?',
      whereArgs: [pdfId, 'slide_annotation', 'page_$pageIndex'],
    );

    if (result.isEmpty) return [];

    final contentJson = result.first['content'] as String?;
    if (contentJson == null || contentJson.isEmpty) return [];

    try {
      final decoded = jsonDecode(contentJson) as List<dynamic>;
      return decoded.map((e) => Annotation.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('解析頁面 $pageIndex 標記失敗: $e');
      return [];
    }
  }

  // 2. 儲存/更新特定頁面的標記
  Future<void> savePageAnnotations(int pdfId, int pageIndex, List<Annotation> annotations) async {
    final db = await database;
    final jsonString = jsonEncode(annotations.map((e) => e.toJson()).toList());
    
    final existing = await db.query(
      'items',
      where: 'parentId = ? AND type = ? AND name = ?',
      whereArgs: [pdfId, 'slide_annotation', 'page_$pageIndex'],
    );

    if (existing.isNotEmpty) {
      final nodeId = existing.first['id'] as int;
      await db.update(
        'items',
        {'content': jsonString},
        where: 'id = ?',
        whereArgs: [nodeId],
      );
    } else {
      await db.insert(
        'items',
        {
          'parentId': pdfId,
          'type': 'slide_annotation',
          'name': 'page_$pageIndex',
          'content': jsonString,
          'createdAt': DateTime.now().toIso8601String(),
        },
      );
    }
  }

  // 3. 刪除整頁的標記子節點
  Future<void> deletePageAnnotationsNode(int pdfId, int pageIndex) async {
    final db = await database;
    await db.delete(
      'items',
      where: 'parentId = ? AND type = ? AND name = ?',
      whereArgs: [pdfId, 'slide_annotation', 'page_$pageIndex'],
    );
  }

  // 4. 一鍵清除該 PDF 的所有標記子節點
  Future<void> clearAllPdfAnnotations(int pdfId) async {
    final db = await database;
    await db.delete(
      'items',
      where: 'parentId = ? AND type = ?',
      whereArgs: [pdfId, 'slide_annotation'],
    );
  }
}
