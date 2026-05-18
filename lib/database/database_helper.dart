// database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models.dart';

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
      version: 1,
      onCreate: _createDB,
      onConfigure: _onConfigure,
    );
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
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
