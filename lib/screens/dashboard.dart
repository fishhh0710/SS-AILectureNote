import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../database/models.dart';
import '../viewmodels/dashboard_view_model.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with SingleTickerProviderStateMixin {
  late final DashboardViewModel _viewModel;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;

  bool _isMenuOpen = false;
  StateSetter? _dialogSetState;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel()..addListener(_handleViewModelChanged);

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

    _viewModel.loadData();
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_handleViewModelChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleViewModelChanged() {
    if (!mounted) return;
    setState(() {});
    _dialogSetState?.call(() {});
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
    final title = switch (type) {
      'course' => '課程',
      'folder' => '資料夾',
      _ => '筆記本',
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('新增$title'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(hintText: '請輸入$title名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _viewModel.createNode(
                  type: type,
                  name: textController.text,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
              } catch (e) {
                if (!context.mounted) return;
                _showErrorSnackBar(e.toString());
              }
            },
            child: const Text('建立'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadToFirebase() async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    _showBackupProgressDialog();

    try {
      await _viewModel.uploadToFirebase();
      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e) {
      if (!mounted) return;
      rootNavigator.pop();
      _showErrorSnackBar(e.toString());
      debugPrint(e.toString());
      return;
    }

    if (!mounted) return;
    rootNavigator.pop();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(_viewModel.backupStatus),
        backgroundColor: const Color(0xFF8E9775),
      ),
    );
  }

  void _showBackupProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _dialogSetState = setDialogState;
            final progress = _viewModel.backupProgress;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('備份到 Firebase'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  CircularProgressIndicator(
                    value: progress <= 0.0 || progress >= 1.0 ? null : progress,
                    color: const Color(0xFF8E9775),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _viewModel.backupStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF3D3D3D),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).toInt()}%',
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失敗：$errorMsg')));
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _viewModel.nodes;

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
                      '課程',
                      style: TextStyle(
                        fontSize: 24,
                        fontFamily: 'Serif',
                        color: Color(0xFF3D3D3D),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _viewModel.isBackingUp
                          ? null
                          : _uploadToFirebase,
                      icon: _viewModel.isBackingUp
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
                        '備份到 Firebase',
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
                if (_viewModel.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: CircularProgressIndicator(color: Color(0xFF8E9775)),
                  )
                else if (_viewModel.errorMessage != null)
                  Text(
                    _viewModel.errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  )
                else if (nodes.isEmpty)
                  const Text(
                    '目前沒有任何項目，請點擊右下角新增。',
                    style: TextStyle(color: Color(0xFFA8A08E)),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 3,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                    itemCount: nodes.length,
                    itemBuilder: (context, index) {
                      return _buildFileItem(context, nodes[index]);
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
          width: 56,
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
          autofocus: true,
          decoration: const InputDecoration(hintText: '請輸入新名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _viewModel.renameNode(node, textController.text);
                if (!context.mounted) return;
                Navigator.pop(context);
              } catch (e) {
                if (!context.mounted) return;
                _showErrorSnackBar(e.toString());
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
        content: Text('確定要刪除「${node.name}」嗎？這將會連同內部所有項目一併刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _viewModel.deleteNode(node);
                if (!context.mounted) return;
                Navigator.pop(context);
              } catch (e) {
                if (!context.mounted) return;
                _showErrorSnackBar(e.toString());
              }
            },
            child: const Text('刪除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(BuildContext context, AppNode node) {
    final isFolder =
        node.type == 'system_folder' ||
        node.type == 'folder' ||
        node.type == 'course';

    final icon = switch (node.type) {
      'system_folder' || 'folder' || 'course' => Icons.folder,
      'notebook' => Icons.book,
      'recording' => Icons.mic,
      'ai_note' => Icons.auto_awesome,
      _ => Icons.description,
    };

    return InkWell(
      onTap: () {
        if (isFolder) {
          context.push('/course/${node.id}');
        } else {
          context.push('/lecture/${_viewModel.databaseRoot?.id}/${node.id}');
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
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(value: 'rename', child: Text('重新命名')),
                  PopupMenuItem<String>(
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
