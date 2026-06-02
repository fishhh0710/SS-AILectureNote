import 'package:flutter/material.dart';
import 'panel_header.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../database/models.dart';

class ChatbotPanel extends StatefulWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final int notebookId; // 補上漏掉的課程 ID，讓 State 類別可以讀取
  final String aiNotes; // 接收外層的真實筆記
  final String transcript; // 接收外層的真實逐字稿

  const ChatbotPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
    required this.notebookId,
    required this.aiNotes,
    required this.transcript,
  });

  @override
  State<ChatbotPanel> createState() => _ChatbotPanelState();
}

class _ChatbotPanelState extends State<ChatbotPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  List<ChatMessage> messages = [];
  bool loading = false;
  int? currentConversationId; // 儲存目前的對話 Session ID

  String loadedAiNotes = "";
  String loadedTranscript = "";

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    setState(() => loading = true);
    try {
      int? convId = await _dbHelper.getLatestConversationId(widget.notebookId);

      // 如果 convId 是 null，代表是這堂課的第一次對話，這時才新建一個 Session
      convId ??= await _dbHelper.createConversation(widget.notebookId);
      final conversationId = convId;

      currentConversationId = conversationId;

      // 帶入傳進來的筆記與逐字稿
      loadedAiNotes = widget.aiNotes;
      loadedTranscript = widget.transcript;

      // 根據這個歷史或既有的 convId，去資料庫撈出所有的歷史對話訊息
      final history = await _dbHelper.getConversationMessages(conversationId);

      setState(() {
        messages = history;
        // 如果連舊的 Session 裡都沒有任何訊息（例如新建的空白 Session），才放歡迎詞
        if (messages.isEmpty) {
          messages.add(
            ChatMessage(
              conversationId: conversationId,
              role: "assistant",
              content:
                  "Hi! I am your AI study assistant. Ask me anything about this lecture!",
              sequenceNumber: 1,
              createdAt: DateTime.now().toIso8601String(),
            ),
          );
        }
        loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => loading = false);
      debugPrint("Failed to initialize chat history: $e");
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || currentConversationId == null) return;

    final convId = currentConversationId!;
    final nowStr = DateTime.now().toIso8601String();

    try {
      // 取得這筆新訊息應有的順序編號 (Sequence)
      final userSeq = await _dbHelper.getNextSequence(convId);

      // 實體化 User 的 ChatMessage 物件
      final userMessage = ChatMessage(
        conversationId: convId,
        role: "user",
        content: text,
        sequenceNumber: userSeq,
        createdAt: nowStr,
      );

      // 先把 User 訊息存入本地 SQLite 資料庫
      await _dbHelper.insertMessage(userMessage);

      setState(() {
        messages.add(userMessage);
        loading = true;
      });

      _controller.clear();
      _scrollToBottom();

      // 撈取「最新 5 輪」歷史紀錄格式化為字串，餵給 AI
      final recentDbMessages = await _dbHelper.getRecentMessages(convId);
      final historyString = recentDbMessages
          .map((e) => "${e.role}: ${e.content}")
          .join("\n");

      final response = await http.post(
        Uri.parse("http://10.0.2.2:8000/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "notes": widget.aiNotes, // 真實筆記內容
          "transcript": widget.transcript, // 真實逐字稿內容
          "history": historyString, // 資料庫撈出的 5 輪歷史
          "question": text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiReply = data["answer"] ?? "無法解析回覆";

        // 計算 AI 回覆的順序編號，並存入本地 SQLite
        final aiSeq = await _dbHelper.getNextSequence(convId);
        final aiMessage = ChatMessage(
          conversationId: convId,
          role: "assistant",
          content: aiReply,
          sequenceNumber: aiSeq,
          createdAt: DateTime.now().toIso8601String(),
        );
        await _dbHelper.insertMessage(aiMessage);

        setState(() {
          messages.add(aiMessage);
          loading = false;
        });
      } else {
        throw Exception("伺服器錯誤 ${response.statusCode}");
      }

      _scrollToBottom();
    } catch (e) {
      setState(() {
        loading = false;
        messages.add(
          ChatMessage(
            conversationId: convId,
            role: "assistant",
            content: "Error: $e",
            sequenceNumber: 999,
            createdAt: nowStr,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Container(
        margin: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEAE7DC)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            PanelHeader(
              title: 'AI CHATBOT',
              icon: Icons.chat_bubble_outline,
              onClose: widget.onClose,
              index: widget.index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(24),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  return _buildChatMessage(
                    isUser: msg.role == "user",
                    message: msg.content,
                  );
                },
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF8E9775),
                ),
              ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Ask a question...',
                        hintStyle: const TextStyle(color: Color(0xFFA8A08E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFFEAE7DC),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFFEAE7DC),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFF8E9775),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF8E9775)),
                    onPressed: loading ? null : sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatMessage({required bool isUser, required String message}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF8E9775) : Colors.white,
          borderRadius: BorderRadius.circular(16).copyWith(
            topLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
          border: isUser ? null : Border.all(color: const Color(0xFFEAE7DC)),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isUser ? Colors.white : const Color(0xFF3D3D3D),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
