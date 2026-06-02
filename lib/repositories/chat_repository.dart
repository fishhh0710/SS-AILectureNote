import '../database/database_helper.dart';
import '../database/models.dart';
import '../services/chat_api_service.dart';

class ChatSession {
  final int conversationId;
  final List<ChatMessage> messages;

  const ChatSession({required this.conversationId, required this.messages});
}

class ChatRepository {
  ChatRepository({DatabaseHelper? dbHelper, ChatApiService? apiService})
    : _dbHelper = dbHelper ?? DatabaseHelper.instance,
      _apiService = apiService ?? ChatApiService();

  static const welcomeText =
      'Hi! I am your AI study assistant. Ask me anything about this lecture!';

  final DatabaseHelper _dbHelper;
  final ChatApiService _apiService;

  Future<ChatSession> loadLatestSession(int notebookId) async {
    var conversationId = await _dbHelper.getLatestConversationId(notebookId);
    conversationId ??= await _dbHelper.createConversation(notebookId);

    final messages = await _dbHelper.getConversationMessages(conversationId);
    return ChatSession(
      conversationId: conversationId,
      messages: messages.isEmpty ? [_welcomeMessage(conversationId)] : messages,
    );
  }

  Future<ChatMessage> addUserMessage({
    required int conversationId,
    required String text,
  }) async {
    final sequence = await _dbHelper.getNextSequence(conversationId);
    final message = ChatMessage(
      conversationId: conversationId,
      role: 'user',
      content: text,
      sequenceNumber: sequence,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _dbHelper.insertMessage(message);
    return message;
  }

  Future<ChatMessage> requestAssistantReply({
    required int conversationId,
    required String aiNotes,
    required String transcript,
    required String question,
  }) async {
    final recentMessages = await _dbHelper.getRecentMessages(conversationId);
    final history = recentMessages
        .map((message) => '${message.role}: ${message.content}')
        .join('\n');

    final answer = await _apiService.ask(
      notes: aiNotes,
      transcript: transcript,
      history: history,
      question: question,
    );

    final sequence = await _dbHelper.getNextSequence(conversationId);
    final assistantMessage = ChatMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: answer,
      sequenceNumber: sequence,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _dbHelper.insertMessage(assistantMessage);
    return assistantMessage;
  }

  void dispose() {
    _apiService.dispose();
  }

  ChatMessage _welcomeMessage(int conversationId) {
    return ChatMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: welcomeText,
      sequenceNumber: 1,
      createdAt: DateTime.now().toIso8601String(),
    );
  }
}
