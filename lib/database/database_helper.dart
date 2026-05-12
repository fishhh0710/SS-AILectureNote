// database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('claw_note.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB, onConfigure: _onConfigure);
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _createDB(Database db, int version) async {
    // 建立課程表 (Home 畫面顯示)
    await db.execute('''
      CREATE TABLE courses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        subtitle TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');

    // 建立檔案與資料夾表 (CourseDetails 畫面顯示)
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        courseId INTEGER NOT NULL,
        parentId INTEGER, 
        type TEXT NOT NULL, 
        name TEXT NOT NULL,
        filePath TEXT,
        transcript TEXT,
        FOREIGN KEY (courseId) REFERENCES courses (id) ON DELETE CASCADE,
        FOREIGN KEY (parentId) REFERENCES items (id) ON DELETE CASCADE
      )
    ''');
  }

  // ================= 1. 課程 (Home) 操作 =================
  Future<int> insertCourse(Course course) async {
    final db = await instance.database;
    return await db.insert('courses', course.toMap());
  }

  Future<List<Course>> getAllCourses() async {
    final db = await instance.database;
    final result = await db.query('courses', orderBy: 'id DESC');
    return result.map((map) => Course.fromMap(map)).toList();
  }

  // ================= 2. 檔案/資料夾 (CourseDetails) 操作 =================
  Future<int> insertItem(CourseItem item) async {
    final db = await instance.database;
    return await db.insert('items', item.toMap());
  }

  // 【核心功能】抓取特定目錄下的所有內容
  // 如果 parentId 是 null，代表抓取該課程最外層的內容
  // 如果 parentId 有值，代表抓取特定資料夾內部的內容
  Future<List<CourseItem>> getItems(int courseId, {int? parentId}) async {
    final db = await instance.database;
    
    // 依據是否有傳入 parentId 來決定 SQL 查詢條件
    final whereString = parentId == null 
        ? 'courseId = ? AND parentId IS NULL' 
        : 'courseId = ? AND parentId = ?';
    
    final args = parentId == null ? [courseId] : [courseId, parentId];

    final result = await db.query(
      'items',
      where: whereString,
      whereArgs: args,
    );
    return result.map((map) => CourseItem.fromMap(map)).toList();
  }
  // 刪除特定課程，同時也會因為我們之前設定的 ON DELETE CASCADE 自動刪除該課程的所有內容
  Future<int> deleteCourse(int id) async {
    final db = await database;
    return await db.delete(
      'courses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 刪除特定的課程項目 (PDF, 語音, 或資料夾)
  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete(
      'course_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
