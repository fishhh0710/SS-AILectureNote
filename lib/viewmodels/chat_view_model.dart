import 'package:flutter/foundation.dart';

import '../database/models.dart';
import '../repositories/chat_repository.dart';

class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required int notebookId,
    required String courseId,
    required String lectureId,
    required String aiNotes,
    required String transcript,
    ChatRepository? repository,
  }) : _notebookId = notebookId,
       _courseId = courseId,
       _lectureId = lectureId,
       _aiNotes = aiNotes,
       _transcript = transcript,
       _repository = repository ?? ChatRepository();

  final ChatRepository _repository;
  int _notebookId;
  String _courseId;
  String _lectureId;
  String _aiNotes;
  String _transcript;
  int? _conversationId;
  bool _isLoading = false;
  bool _isSending = false;
  List<ChatMessage> _messages = const [];

  List<ChatMessage> get messages => _messages;
  bool get isBusy => _isLoading || _isSending;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      final session = await _repository.loadLatestSession(_notebookId);
      _conversationId = session.conversationId;
      _messages = session.messages;
    } catch (e) {
      _messages = [_errorMessage(0, 'Failed to initialize chat history: $e')];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateLectureContext({
    required int notebookId,
    required String courseId,
    required String lectureId,
    required String aiNotes,
    required String transcript,
  }) {
    _notebookId = notebookId;
    _courseId = courseId;
    _lectureId = lectureId;
    _aiNotes = aiNotes;
    _transcript = transcript;
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    final conversationId = _conversationId;
    if (trimmed.isEmpty || conversationId == null || _isSending) return;

    try {
      final userMessage = await _repository.addUserMessage(
        conversationId: conversationId,
        text: trimmed,
      );

      _messages = [..._messages, userMessage];
      _isSending = true;
      notifyListeners();

      final assistantMessage = await _repository.requestAssistantReply(
        conversationId: conversationId,
        courseId: _courseId,
        lectureId: _lectureId,
        aiNotes: _aiNotes,
        transcript: _transcript,
        question: trimmed,
      );

      _messages = [..._messages, assistantMessage];
    } catch (e) {
      _messages = [..._messages, _errorMessage(conversationId, 'Error: $e')];
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  ChatMessage _errorMessage(int conversationId, String text) {
    return ChatMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: text,
      sequenceNumber: 999,
      createdAt: DateTime.now().toIso8601String(),
    );
  }
}
