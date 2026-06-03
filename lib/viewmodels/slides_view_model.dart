import 'package:flutter/foundation.dart';

import '../repositories/file_tree_repository.dart';

class SlidesViewModel extends ChangeNotifier {
  SlidesViewModel({required String fileId, FileTreeRepository? repository})
    : _fileId = fileId,
      _repository = repository ?? FileTreeRepository();

  final String _fileId;
  final FileTreeRepository _repository;

  int? get _nodeId => int.tryParse(_fileId);

  Future<String?> loadSavedPdfPath() async {
    final nodeId = _nodeId;
    if (nodeId == null) return null;

    final node = await _repository.getNode(nodeId);
    return node?.filePath;
  }

  Future<void> savePdfPath(String filePath) async {
    final nodeId = _nodeId;
    if (nodeId == null) {
      throw Exception('Cannot save PDF because fileId is invalid.');
    }

    await _repository.updateFilePath(nodeId: nodeId, filePath: filePath);
  }
}
