import 'dart:async';

import 'package:flutter/material.dart';

import '../viewmodels/chat_view_model.dart';
import 'panel_header.dart';

class ChatbotPanel extends StatefulWidget {
  final double width;
  final int index;
  final VoidCallback onClose;
  final int notebookId;
  final String aiNotes;
  final String transcript;

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

  late ChatViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    unawaited(_viewModel.load());
  }

  @override
  void didUpdateWidget(ChatbotPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.notebookId != widget.notebookId) {
      _viewModel
        ..removeListener(_handleChatStateChanged)
        ..dispose();
      _viewModel = _createViewModel();
      unawaited(_viewModel.load());
      return;
    }

    _viewModel.updateLectureContext(
      notebookId: widget.notebookId,
      aiNotes: widget.aiNotes,
      transcript: widget.transcript,
    );
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_handleChatStateChanged)
      ..dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ChatViewModel _createViewModel() {
    final viewModel = ChatViewModel(
      notebookId: widget.notebookId,
      aiNotes: widget.aiNotes,
      transcript: widget.transcript,
    );
    viewModel.addListener(_handleChatStateChanged);
    return viewModel;
  }

  void _handleChatStateChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _viewModel.isBusy) return;

    _controller.clear();
    await _viewModel.sendMessage(text);
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
                itemCount: _viewModel.messages.length,
                itemBuilder: (context, index) {
                  final message = _viewModel.messages[index];
                  return _buildChatMessage(
                    isUser: message.role == 'user',
                    message: message.content,
                  );
                },
              ),
            ),
            if (_viewModel.isBusy)
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
                      onSubmitted: (_) {
                        unawaited(_sendMessage());
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF8E9775)),
                    onPressed: _viewModel.isBusy
                        ? null
                        : () {
                            unawaited(_sendMessage());
                          },
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
