import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/features/chat/presentation/widgets/chat_history_rail.dart';

/// Full-page history (deep link `/chats`). The main UI uses the left rail.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key, this.asPanel = false});

  final bool asPanel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: asPanel ? 'Close' : 'Back to chat',
          onPressed: () {
            if (asPanel) {
              Navigator.pop(context);
            } else {
              context.go('/chat');
            }
          },
          icon: Icon(asPanel ? Icons.close : Icons.arrow_back),
        ),
        title: const Text('Chats'),
      ),
      body: ChatHistoryRail(onPicked: asPanel ? () => Navigator.pop(context) : null),
    );
  }
}
