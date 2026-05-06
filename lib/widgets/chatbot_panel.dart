import 'package:flutter/material.dart';
import 'panel_header.dart';

class ChatbotPanel extends StatelessWidget {
  final double width;
  final int index;
  final VoidCallback onClose;

  const ChatbotPanel({
    super.key,
    required this.width,
    required this.index,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
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
              onClose: onClose,
              index: index,
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _buildChatMessage(
                    isUser: false,
                    message: "Hi! I am your AI study assistant. Ask me anything about this lecture!",
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEAE7DC)),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Ask a question...',
                        hintStyle: const TextStyle(color: Color(0xFFA8A08E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFFEAE7DC)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFFEAE7DC)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFF8E9775)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF8E9775)),
                    onPressed: () {},
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
