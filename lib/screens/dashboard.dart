import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../database/database_helper.dart';
import '../database/models.dart';
import '../services/firebase_upload_service.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;
  bool _isMenuOpen = false;

  List<AppNode> _nodes = [];
  AppNode? _databaseRoot;

  bool _isBackingUp = false;
  String _backupStatus = '';
  double _backupProgress = 0.0;
  StateSetter? _dialogSetState;

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

  Future<void> _loadData() async {
    final dbRoot = await DatabaseHelper.instance.getDatabaseRootFolder();
    if (dbRoot != null) {
      final items = await DatabaseHelper.instance.getItemsByParent(dbRoot.id);
      setState(() {
        _databaseRoot = dbRoot;
        _nodes = items;
      });
    }
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
              if (textController.text.isNotEmpty && _databaseRoot != null) {
                final newNode = AppNode(
                  parentId: _databaseRoot!.id,
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  Future<void> _uploadToFirebase() async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    setState(() {
      _isBackingUp = true;
      _backupStatus = '正在準備...';
      _backupProgress = 0.0;
    });

    _showBackupProgressDialog();

    try {
      await FirebaseUploadService.uploadAllFiles(
        userId: 'jenny',
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _backupStatus = status;
              _backupProgress = progress;
            });
            _dialogSetState?.call(() {});
          }
        },
      );
      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e) {
      if (mounted) {
        rootNavigator.pop(); // Dismiss progress dialog
        _showErrorSnackBar(e.toString());
        debugPrint(e.toString());
      }
      if (!mounted) return;
      setState(() {
        _isBackingUp = false;
      });
      return;
    }

    if (mounted) {
      rootNavigator.pop(); // Dismiss progress dialog
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(_backupStatus),
          backgroundColor: const Color(0xFF8E9775),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _isBackingUp = false;
    });
    _loadData();
  }

  void _showBackupProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _dialogSetState = setDialogState;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('備份至 Firebase'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  CircularProgressIndicator(
                    value: _backupProgress <= 0.0 || _backupProgress >= 1.0
                        ? null
                        : _backupProgress,
                    color: const Color(0xFF8E9775),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _backupStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF3D3D3D),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_backupProgress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFA8A08E),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      if (mounted) {
        _dialogSetState = null;
      }
    });
  }

  void _showErrorSnackBar(String errorMsg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('備份失敗: $errorMsg'), backgroundColor: Colors.red),
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
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '目前課程',
                      style: TextStyle(
                        fontSize: 24,
                        fontFamily: 'Serif',
                        color: Color(0xFF3D3D3D),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isBackingUp ? null : _uploadToFirebase,
                      icon: _isBackingUp
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload, size: 18),
                      label: const Text(
                        '備份至 Firebase',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8E9775),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _nodes.isEmpty
                    ? const Text(
                        '目前沒有任何項目，請點擊右下角新增',
                        style: TextStyle(color: Color(0xFFA8A08E)),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 3,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                            ),
                        itemCount: _nodes.length,
                        itemBuilder: (context, index) {
                          return _buildFileItem(context, _nodes[index]);
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedDial() {
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
              const SizedBox(height: 24),
            ],
          ),
        ),
        FloatingActionButton(
          heroTag: 'main_fab',
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
          context.push('/lecture/${_databaseRoot?.id}/${node.id}');
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    overflow: TextOverflow.ellipsis,
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
