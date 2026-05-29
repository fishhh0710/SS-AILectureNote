import 'dart:math';
import 'package:flutter/material.dart';
import '../data/annotation_model.dart';
import '../services/annotation_manager.dart';

class SlideAnnotationTestControls extends StatelessWidget {
  final PageAnnotationManager manager;

  const SlideAnnotationTestControls({
    super.key,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'annotation_test_fab',
      backgroundColor: const Color(0xFF8E9775),
      elevation: 4,
      onPressed: () => _showManageDialog(context),
      child: const Icon(
        Icons.gesture,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  void _showManageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AnnotationManageDialog(manager: manager);
      },
    );
  }
}

class AnnotationManageDialog extends StatefulWidget {
  final PageAnnotationManager manager;

  const AnnotationManageDialog({
    super.key,
    required this.manager,
  });

  @override
  State<AnnotationManageDialog> createState() => _AnnotationManageDialogState();
}

class _AnnotationManageDialogState extends State<AnnotationManageDialog> {
  String _selectedType = 'rect'; // 'rect' | 'text'
  Color _selectedColor = Colors.red;

  final _pageController = TextEditingController(text: '1');
  final _xController = TextEditingController(text: '0.1');
  final _yController = TextEditingController(text: '0.2');
  final _widthController = TextEditingController(text: '0.2');
  final _heightController = TextEditingController(text: '0.1');
  final _textController = TextEditingController(text: '測試標記');
  final _fontSizeController = TextEditingController(text: '14.0');
  final _fontFamilyController = TextEditingController(text: '');
  bool _autoWrap = true;

  final List<Map<String, dynamic>> _colorOptions = [
    {'name': '紅色', 'color': Colors.red},
    {'name': '藍色', 'color': Colors.blue},
    {'name': '綠色', 'color': Colors.green},
    {'name': '黑色', 'color': Colors.black},
    {'name': '黃色', 'color': Colors.yellow.shade700},
  ];

  String _generateId(String type) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1000000);
    return '${type}_${timestamp}_$random';
  }

  void _addAnnotation() {
    final pageIndex = int.tryParse(_pageController.text) ?? 1;
    final x = double.tryParse(_xController.text) ?? 0.1;
    final y = double.tryParse(_yController.text) ?? 0.2;
    final id = _generateId(_selectedType);

    Annotation newAnn;

    if (_selectedType == 'rect') {
      final w = double.tryParse(_widthController.text) ?? 0.2;
      final h = double.tryParse(_heightController.text) ?? 0.1;
      newAnn = RectAnnotation(
        id: id,
        pageIndex: pageIndex,
        color: _selectedColor,
        x: x,
        y: y,
        width: w,
        height: h,
      );
    } else {
      final size = double.tryParse(_fontSizeController.text) ?? 14.0;
      final font = _fontFamilyController.text.trim();
      newAnn = TextAnnotation(
        id: id,
        pageIndex: pageIndex,
        color: _selectedColor,
        x: x,
        y: y,
        text: _textController.text,
        fontSize: size,
        fontFamily: font.isEmpty ? null : font,
        autoWrap: _autoWrap,
      );
    }

    widget.manager.addAnnotation(pageIndex, newAnn);
    setState(() {}); // Refresh list of existing annotations in dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已於第 $pageIndex 頁新增標記')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingAnnotations = widget.manager.getAllLoadedAnnotations();

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '管理 PDF 標記 (測試用)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D3D3D),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- FORM SECTION ---
              const Text(
                '新增標記',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8E9775),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('類型：'),
                  Radio<String>(
                    value: 'rect',
                    groupValue: _selectedType,
                    activeColor: const Color(0xFF8E9775),
                    onChanged: (val) => setState(() => _selectedType = val!),
                  ),
                  const Text('方框 (Rect)'),
                  Radio<String>(
                    value: 'text',
                    groupValue: _selectedType,
                    activeColor: const Color(0xFF8E9775),
                    onChanged: (val) => setState(() => _selectedType = val!),
                  ),
                  const Text('文字 (Text)'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '頁碼 (1-indexed)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<Color>(
                      value: _selectedColor,
                      decoration: const InputDecoration(
                        labelText: '顏色',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      items: _colorOptions.map((opt) {
                        return DropdownMenuItem<Color>(
                          value: opt['color'] as Color,
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                color: opt['color'] as Color,
                              ),
                              const SizedBox(width: 8),
                              Text(opt['name'] as String),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedColor = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _xController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '相對 X (0.0 ~ 1.0)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _yController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '相對 Y (0.0 ~ 1.0)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Conditional Forms
              if (_selectedType == 'rect') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _widthController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '相對寬度 (0.0 ~ 1.0)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _heightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '相對高度 (0.0 ~ 1.0)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: '文字內容',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _fontSizeController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '字型大小 (例如: 14)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _fontFamilyController,
                        decoration: const InputDecoration(
                          labelText: '字型名稱 (可選)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Checkbox(
                      value: _autoWrap,
                      activeColor: const Color(0xFF8E9775),
                      onChanged: (val) => setState(() => _autoWrap = val ?? true),
                    ),
                    const Text('是否自動折行 (autoWrap)'),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addAnnotation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8E9775),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('新增此標記'),
                ),
              ),

              const SizedBox(height: 24),
              const Divider(color: Color(0xFFEAE7DC), thickness: 1.5),
              const SizedBox(height: 12),

              // --- EXISTING LIST SECTION ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '目前已存在的標記 (${existingAnnotations.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3D3D3D),
                    ),
                  ),
                  if (existingAnnotations.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        await widget.manager.clearAll();
                        setState(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清除所有頁面的標記')),
                          );
                        }
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.delete_sweep, size: 18),
                      label: const Text('全部清除'),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (existingAnnotations.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '目前沒有任何標記',
                      style: TextStyle(color: Color(0xFFA8A08E), fontSize: 13),
                    ),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFEAE7DC)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: existingAnnotations.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFEAE7DC)),
                    itemBuilder: (context, idx) {
                      final ann = existingAnnotations[idx];
                      String typeName = ann.type == 'rect' ? '方框' : '文字';
                      String details = '';
                      if (ann is RectAnnotation) {
                        details = 'x:${ann.x.toStringAsFixed(2)}, y:${ann.y.toStringAsFixed(2)}, w:${ann.width.toStringAsFixed(2)}, h:${ann.height.toStringAsFixed(2)}';
                      } else if (ann is TextAnnotation) {
                        details = '"${ann.text.length > 10 ? '${ann.text.substring(0, 10)}...' : ann.text}" at (${ann.x.toStringAsFixed(2)}, ${ann.y.toStringAsFixed(2)})';
                      }

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 10,
                          backgroundColor: ann.color,
                        ),
                        title: Text('第 ${ann.pageIndex} 頁：$typeName標記'),
                        subtitle: Text(details, style: const TextStyle(fontSize: 11, color: Color(0xFFA8A08E))),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                          onPressed: () {
                            widget.manager.deleteAnnotation(ann.pageIndex, ann.id);
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已刪除指定標記')),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
