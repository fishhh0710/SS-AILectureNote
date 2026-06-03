import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../database/models.dart';
import '../viewmodels/course_details_view_model.dart';

class CourseDetails extends StatefulWidget {
  final String courseId;

  const CourseDetails({super.key, required this.courseId});

  @override
  State<CourseDetails> createState() => _CourseDetailsState();
}

class _CourseDetailsState extends State<CourseDetails>
    with SingleTickerProviderStateMixin {
  late CourseDetailsViewModel _viewModel;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;

  bool _isMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();

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
  void didUpdateWidget(covariant CourseDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId == widget.courseId) return;

    _viewModel
      ..removeListener(_handleViewModelChanged)
      ..dispose();
    _viewModel = _createViewModel();
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

  CourseDetailsViewModel _createViewModel() {
    final viewModel = CourseDetailsViewModel(nodeId: widget.courseId);
    viewModel.addListener(_handleViewModelChanged);
    return viewModel;
  }

  void _handleViewModelChanged() {
    if (!mounted) return;
    setState(() {});
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

  Widget _buildSpeedDial() {
    final allowAll = _viewModel.allowNestedFolders;

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

  void _showErrorSnackBar(String errorMsg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失敗：$errorMsg')));
  }

  @override
  Widget build(BuildContext context) {
    final parentNode = _viewModel.parentNode;
    final children = _viewModel.children;

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
                  parentNode?.name ?? '載入中...',
                  style: const TextStyle(
                    fontSize: 36,
                    fontFamily: 'Serif',
                    color: Color(0xFF3D3D3D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  parentNode?.type.toUpperCase() ?? '',
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
                else if (children.isEmpty)
                  const Text(
                    '這個資料夾是空的。',
                    style: TextStyle(color: Color(0xFFA8A08E)),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 4,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                    itemCount: children.length,
                    itemBuilder: (context, index) {
                      return _buildFileItem(context, children[index]);
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
          context.push('/lecture/${_viewModel.parentNode?.id}/${node.id}');
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
