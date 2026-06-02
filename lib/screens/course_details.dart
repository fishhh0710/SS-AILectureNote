import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../database/database_helper.dart';
import '../database/models.dart';

class CourseDetails extends StatefulWidget {
  final String courseId;

  const CourseDetails({super.key, required this.courseId});

  @override
  State<CourseDetails> createState() => _CourseDetailsState();
}

class _CourseDetailsState extends State<CourseDetails>
    with SingleTickerProviderStateMixin {
  AppNode? _parentNode;
  List<AppNode> _children = [];

  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;
  bool _isMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.fastOutSlowIn,
    );
    _rotateAnimation = Tween<double>(
      begin: 0.0,
      end: 0.125,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _loadData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final id = int.tryParse(widget.courseId);
    if (id == null) return;

    final node = await DatabaseHelper.instance.getNodeById(id);
    if (node != null) {
      final items = await DatabaseHelper.instance.getItemsByParent(node.id);
      setState(() {
        _parentNode = node;
        _children = items;
      });
    }
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _showCreateDialog(String type) {
    final textController = TextEditingController();
    String title = type == 'course' ? '課程' : (type == 'folder' ? '資料夾' : '筆記本');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('新增 $title'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(hintText: '請輸入名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (textController.text.isNotEmpty && _parentNode != null) {
                final newNode = AppNode(
                  parentId: _parentNode!.id, // Set parent to current folder
                  type: type,
                  name: textController.text,
                  createdAt: DateTime.now().toIso8601String(),
                );

                if (type == 'course') {
                  await DatabaseHelper.instance.insertCourse(newNode);
                } else {
                  await DatabaseHelper.instance.insertItem(newNode);
                }

                if (!context.mounted) return;
                Navigator.pop(context);
                _loadData();
              }
            },
            child: const Text('建立'),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedDial() {
    bool allowAll = _parentNode?.type == 'folder';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IgnorePointer(
          ignoring: !_isMenuOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ScaleTransition(
                scale: _expandAnimation,
                child: FadeTransition(
                  opacity: _expandAnimation,
                  child: _buildSubButton(
                    label: 'Notebook',
                    icon: Icons.book,
                    onPressed: () {
                      _toggleMenu();
                      _showCreateDialog('notebook');
                    },
                  ),
                ),
              ),
              if (allowAll) ...[
                const SizedBox(height: 12),
                ScaleTransition(
                  scale: _expandAnimation,
                  child: FadeTransition(
                    opacity: _expandAnimation,
                    child: _buildSubButton(
                      label: 'Folder',
                      icon: Icons.folder,
                      onPressed: () {
                        _toggleMenu();
                        _showCreateDialog('folder');
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ScaleTransition(
                  scale: _expandAnimation,
                  child: FadeTransition(
                    opacity: _expandAnimation,
                    child: _buildSubButton(
                      label: 'Course',
                      icon: Icons.menu_book,
                      onPressed: () {
                        _toggleMenu();
                        _showCreateDialog('course');
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
        FloatingActionButton(
          heroTag: 'course_details_fab',
          onPressed: _toggleMenu,
          backgroundColor: const Color(0xFF8E9775),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: RotationTransition(
            turns: _rotateAnimation,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildSubButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: const Color(0xFFEAE7DC)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D3D3D),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 56, // Perfectly matches the 56dp width of the main FAB
          child: Center(
            child: FloatingActionButton.small(
              heroTag: null,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF8E9775),
              elevation: 3,
              onPressed: onPressed,
              child: Icon(icon, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  void _showRenameDialog(AppNode node) {
    final textController = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新命名'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(hintText: '請輸入新名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (textController.text.isNotEmpty) {
                final updatedNode = AppNode(
                  id: node.id,
                  parentId: node.parentId,
                  type: node.type,
                  name: textController.text,
                  content: node.content,
                  filePath: node.filePath,
                  cloudPath: node.cloudPath,
                  createdAt: node.createdAt,
                );
                await DatabaseHelper.instance.updateItem(updatedNode);
                if (!context.mounted) return;
                Navigator.pop(context);
                _loadData();
              }
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(AppNode node) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除確認'),
        content: Text('確定要刪除「${node.name}」嗎？這將會連同內部所有檔案一併刪除！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.deleteItem(node.id!);
              if (!context.mounted) return;
              Navigator.pop(context);
              _loadData();
            },
            child: const Text('刪除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _buildSpeedDial(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Container(
          alignment: AlignmentGeometry.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.pop(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back,
                        size: 14,
                        color: Color(0xFFA8A08E),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '返回上層',
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
                  _parentNode?.name ?? '載入中...',
                  style: const TextStyle(
                    fontSize: 36,
                    fontFamily: 'Serif',
                    color: Color(0xFF3D3D3D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _parentNode?.type.toUpperCase() ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFA8A08E),
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  '內部檔案',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFA8A08E),
                    letterSpacing: 3.0,
                  ),
                ),
                const SizedBox(height: 24),
                _children.isEmpty
                    ? const Text(
                        '這個資料夾是空的',
                        style: TextStyle(color: Color(0xFFA8A08E)),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 4,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                            ),
                        itemCount: _children.length,
                        itemBuilder: (context, index) {
                          return _buildFileItem(context, _children[index]);
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileItem(BuildContext context, AppNode node) {
    bool isFolder =
        node.type == 'system_folder' ||
        node.type == 'folder' ||
        node.type == 'course';

    IconData icon;
    if (isFolder) {
      icon = Icons.folder;
    } else if (node.type == 'notebook') {
      icon = Icons.book;
    } else if (node.type == 'recording') {
      icon = Icons.mic;
    } else if (node.type == 'ai_note') {
      icon = Icons.auto_awesome;
    } else {
      icon = Icons.description;
    }

    return InkWell(
      onTap: () {
        if (isFolder) {
          context.push('/course/${node.id}');
        } else {
          context.push('/lecture/${_parentNode?.id}/${node.id}');
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
                color: isFolder
                    ? const Color(0xFFF5F2EA)
                    : const Color(0xFFFAF9F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isFolder
                    ? const Color(0xFF8E9775)
                    : const Color(0xFFA8A08E),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF3D3D3D),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    node.type.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFA8A08E),
                    ),
                  ),
                ],
              ),
            ),
            if (node.type != 'system_folder')
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFFEAE7DC)),
                onSelected: (value) {
                  if (value == 'rename') {
                    _showRenameDialog(node);
                  } else if (value == 'delete') {
                    _showDeleteDialog(node);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'rename',
                    child: Text('重新命名'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('刪除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
