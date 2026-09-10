import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/chat/domain/chat_message.dart';
import 'package:second_brain/features/chat/presentation/widgets/chat_bubble.dart';

void main() {
  testWidgets('degraded assistant shows keyword label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: ChatMessage(
              id: 'a',
              role: 'assistant',
              content: 'snippet from library',
              degraded: true,
              createdAt: DateTime.utc(2026, 9, 7),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Keyword matches'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
