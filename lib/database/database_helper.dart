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
      version: 3,
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
    if (oldVersion < 3) {
      // 升級版本 3 時建立對話相關資料表
      await db.execute('''
        CREATE TABLE conversations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          courseId INTEGER NOT NULL,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (courseId) REFERENCES items(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          conversationId INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          sequenceNumber INTEGER NOT NULL,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (conversationId) REFERENCES conversations(id) ON DELETE CASCADE
        )
      ''');
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

    await db.execute('''
      CREATE TABLE conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        courseId INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (courseId)
        REFERENCES items(id)
        ON DELETE CASCADE
      )
      ''');

    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversationId INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        sequenceNumber INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (conversationId)
        REFERENCES conversations(id)
        ON DELETE CASCADE
      )
      ''');
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

  // ================= 3. Chatbot Operations =================

  // 建立一個新的對話 Session (回傳 conversationId)
  Future<int> createConversation(int notebookId) async {
    final db = await instance.database;
    
    return await db.insert('conversations', {
      'courseId': notebookId,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  // 儲存一筆新的對話訊息 (User 或 AI)
  Future<int> insertMessage(ChatMessage message) async {
    final db = await instance.database;
    return await db.insert('messages', message.toMap());
  }

  // 獲取某個對話 Session 的所有歷史紀錄 (依照順序排列)
  Future<List<ChatMessage>> getConversationMessages(int conversationId) async {
    final db = await instance.database;
    final result = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'sequenceNumber ASC',
    );
    return result.map((e) => ChatMessage.fromMap(e)).toList();
  }

  // 獲取最新 5 輪 (10 筆) 對話，用於丟給 AI 當作上下文 (反轉為正確時間順序)
  Future<List<ChatMessage>> getRecentMessages(int conversationId) async {
    final db = await instance.database;
    final result = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'sequenceNumber DESC',
      limit: 10,
    );
    return result
        .map((e) => ChatMessage.fromMap(e))
        .toList()
        .reversed
        .toList();
  }

  // 獲取下一個對話的順序編號 (sequenceNumber)
  Future<int> getNextSequence(int conversationId) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      '''
      SELECT MAX(sequenceNumber) as seq
      FROM messages
      WHERE conversationId = ?
      ''',
      [conversationId],
    );

    final seq = result.first['seq'];
    return (seq as int? ?? 0) + 1;
  }

  Future<int?> getLatestConversationId(int notebookId) async {
    final db = await instance.database;
    final result = await db.query(
      'conversations',
      where: 'courseId = ?',
      whereArgs: [notebookId],
      orderBy: 'id DESC', // 讓最新的 Session 排在最上面
      limit: 1,           // 只取最新的一筆
    );
    
    if (result.isNotEmpty) {
      return result.first['id'] as int;
    }
    return null; // 回傳 null 代表這堂課從來沒聊過天
  }

  // ================= 4. Auto-Aggregation for Chatbot =================

  // 自動撈取該課程資料夾下，所有分頁的 AI 筆記並組合成單一字串
  Future<String> getCombinedAiNotes(int courseId) async {
    final db = await instance.database;
    
    // 1. 先找到該課程底下的 "AI notes" 系統資料夾節點取得其 ID
    final folderResult = await db.query(
      'items',
      where: 'parentId = ? AND type = ? AND name = ?',
      whereArgs: [courseId, 'system_folder', 'AI notes'],
    );
    if (folderResult.isEmpty) return "";
    final folderNodeId = folderResult.first['id'] as int;

    // 2. 撈出該資料夾內所有的筆記頁面
    final notesResult = await db.query(
      'items',
      where: 'parentId = ?',
      whereArgs: [folderNodeId],
    );

    // 3. 將每一頁的 content (Markdown) 用換行串聯起來
    return notesResult
        .map((row) => row['content'] as String? ?? "")
        .where((text) => text.isNotEmpty)
        .join("\n\n");
  }

  // 自動撈取該課程資料夾下，所有錄音檔的逐字稿並組合成單一字串
  Future<String> getCombinedTranscripts(int courseId) async {
    final db = await instance.database;
    
    // 1. 先找到該課程底下的 "Recordings" 系統資料夾節點取得其 ID
    final folderResult = await db.query(
      'items',
      where: 'parentId = ? AND type = ? AND name = ?',
      whereArgs: [courseId, 'system_folder', 'Recordings'],
    );
    if (folderResult.isEmpty) return "";
    final folderNodeId = folderResult.first['id'] as int;

    // 2. 撈出該資料夾內所有的錄音文字檔
    final recResult = await db.query(
      'items',
      where: 'parentId = ?',
      whereArgs: [folderNodeId],
    );

    // 3. 將所有逐字稿拼接起來
    return recResult
        .map((row) => row['content'] as String? ?? "")
        .where((text) => text.isNotEmpty)
        .join("\n\n");
  }
}
