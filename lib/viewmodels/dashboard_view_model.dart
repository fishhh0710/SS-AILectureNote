import 'package:flutter/foundation.dart';

import '../database/models.dart';
import '../repositories/file_tree_repository.dart';

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    FileTreeRepository? repository,
    this.backupUserId = 'jenny',
  }) : _repository = repository ?? FileTreeRepository();

  final FileTreeRepository _repository;
  final String backupUserId;

  AppNode? _databaseRoot;
  List<AppNode> _nodes = const [];
  bool _isLoading = false;
  bool _isBackingUp = false;
  String _backupStatus = '';
  double _backupProgress = 0.0;
  String? _errorMessage;

  AppNode? get databaseRoot => _databaseRoot;
  List<AppNode> get nodes => _nodes;
  bool get isLoading => _isLoading;
  bool get isBackingUp => _isBackingUp;
  String get backupStatus => _backupStatus;
  double get backupProgress => _backupProgress;
  String? get errorMessage => _errorMessage;

  Future<void> loadData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final snapshot = await _repository.loadDatabaseRoot();
      _databaseRoot = snapshot?.parent;
      _nodes = snapshot?.children ?? const [];
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createNode({required String type, required String name}) async {
    final rootId = _databaseRoot?.id;
    if (rootId == null) {
      throw Exception('Database root is not loaded.');
    }

    await _repository.createChild(parentId: rootId, type: type, name: name);
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

  Future<void> uploadToFirebase() async {
    _isBackingUp = true;
    _backupStatus = 'Preparing Firebase backup...';
    _backupProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.backupToFirebase(
        userId: backupUserId,
        onProgress: (status, progress) {
          _backupStatus = status;
          _backupProgress = progress;
          notifyListeners();
        },
      );
      await loadData();
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isBackingUp = false;
      notifyListeners();
    }
  }
}
