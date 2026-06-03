import 'package:flutter/foundation.dart';

import '../database/models.dart';
import '../repositories/file_tree_repository.dart';

class CourseDetailsViewModel extends ChangeNotifier {
  CourseDetailsViewModel({
    required String nodeId,
    FileTreeRepository? repository,
  }) : _nodeId = nodeId,
       _repository = repository ?? FileTreeRepository();

  final String _nodeId;
  final FileTreeRepository _repository;

  AppNode? _parentNode;
  List<AppNode> _children = const [];
  bool _isLoading = false;
  String? _errorMessage;

  AppNode? get parentNode => _parentNode;
  List<AppNode> get children => _children;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get allowNestedFolders => _parentNode?.type == 'folder';

  Future<void> loadData() async {
    final id = int.tryParse(_nodeId);
    if (id == null) {
      _errorMessage = 'Invalid course id: $_nodeId';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final snapshot = await _repository.loadNode(id);
      _parentNode = snapshot?.parent;
      _children = snapshot?.children ?? const [];
      if (snapshot == null) {
        _errorMessage = 'Course or folder not found.';
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createNode({required String type, required String name}) async {
    final parentId = _parentNode?.id;
    if (parentId == null) {
      throw Exception('Parent folder is not loaded.');
    }

    await _repository.createChild(parentId: parentId, type: type, name: name);
    await loadData();
  }

  Future<void> renameNode(AppNode node, String name) async {
    await _repository.renameNode(node, name);
    await loadData();
  }

  Future<void> deleteNode(AppNode node) async {
    await _repository.deleteNode(node);
    await loadData();
  }
}
