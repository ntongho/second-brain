import 'package:second_brain/features/chat/domain/citation.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.chatRemoteId,
    this.remoteId,
    this.citations = const [],
    this.degraded = false,
    this.streaming = false,
    this.failed = false,
    this.queued = false,
    this.idempotencyKey,
    this.promptTokens,
    this.completionTokens,
    this.latencyMs,
    this.mode,
  });

  final String id;
  final String? chatRemoteId;
  final String? remoteId;
  final String role; // user | assistant
  final String content;
  final List<Citation> citations;
  final bool degraded;
  final bool streaming;
  final bool failed;
  final bool queued;
  final String? idempotencyKey;
  final DateTime createdAt;
  final int? promptTokens;
  final int? completionTokens;
  final int? latencyMs;
  final String? mode;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  ChatMessage copyWith({
    String? id,
    String? chatRemoteId,
    String? remoteId,
    String? role,
    String? content,
    List<Citation>? citations,
    bool? degraded,
    bool? streaming,
    bool? failed,
    bool? queued,
    String? idempotencyKey,
    DateTime? createdAt,
    int? promptTokens,
    int? completionTokens,
    int? latencyMs,
    String? mode,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatRemoteId: chatRemoteId ?? this.chatRemoteId,
      remoteId: remoteId ?? this.remoteId,
      role: role ?? this.role,
      content: content ?? this.content,
      citations: citations ?? this.citations,
      degraded: degraded ?? this.degraded,
      streaming: streaming ?? this.streaming,
      failed: failed ?? this.failed,
      queued: queued ?? this.queued,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdAt: createdAt ?? this.createdAt,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      latencyMs: latencyMs ?? this.latencyMs,
      mode: mode ?? this.mode,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      chatRemoteId: json['chatRemoteId'] as String?,
      remoteId: json['remoteId'] as String?,
      role: json['role'] as String,
      content: json['content'] as String? ?? '',
      citations: [
        for (final c in (json['citations'] as List? ?? const []))
          Citation.fromJson((c as Map).cast<String, dynamic>()),
      ],
      degraded: json['degraded'] as bool? ?? false,
      failed: json['failed'] as bool? ?? false,
      queued: json['queued'] as bool? ?? false,
      idempotencyKey: json['idempotencyKey'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      promptTokens: json['promptTokens'] as int?,
      completionTokens: json['completionTokens'] as int?,
      latencyMs: json['latencyMs'] as int?,
      mode: json['mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatRemoteId': chatRemoteId,
        'remoteId': remoteId,
        'role': role,
        'content': content,
        'citations': [for (final c in citations) c.toJson()],
        'degraded': degraded,
        'failed': failed,
        'queued': queued,
        'idempotencyKey': idempotencyKey,
        'createdAt': createdAt.toIso8601String(),
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'latencyMs': latencyMs,
        'mode': mode,
      };
}
