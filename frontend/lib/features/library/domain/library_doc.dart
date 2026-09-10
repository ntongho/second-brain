class LibraryDoc {
  const LibraryDoc({
    required this.id,
    required this.title,
    required this.sourceType,
    required this.status,
    required this.createdAt,
    this.tags = const [],
    this.charCount = 0,
    this.chunkCount = 0,
    this.pageCount,
    this.error,
    this.text,
    this.highlightStart,
    this.highlightEnd,
    this.highlightPage,
    this.highlightSnippet,
    this.jobId,
  });

  final String id;
  final String title;
  final String sourceType;
  final String status;
  final DateTime createdAt;
  final List<String> tags;
  final int charCount;
  final int chunkCount;
  final int? pageCount;
  final String? error;
  final String? text;
  final int? highlightStart;
  final int? highlightEnd;
  final int? highlightPage;
  final String? highlightSnippet;
  final String? jobId;

  factory LibraryDoc.fromJson(Map<String, dynamic> json) {
    return LibraryDoc(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? 'text',
      status: json['status'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now().toUtc(),
      tags: [for (final t in (json['tags'] as List? ?? const [])) t.toString()],
      charCount: json['char_count'] as int? ?? 0,
      chunkCount: json['chunk_count'] as int? ?? 0,
      pageCount: json['page_count'] as int?,
      error: json['error'] as String?,
      text: json['text'] as String?,
      highlightStart: json['highlight_start'] as int?,
      highlightEnd: json['highlight_end'] as int?,
      highlightPage: json['highlight_page'] as int?,
      highlightSnippet: json['highlight_snippet'] as String?,
      jobId: json['job_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source_type': sourceType,
        'status': status,
        'created_at': createdAt.toUtc().toIso8601String(),
        'tags': tags,
        'char_count': charCount,
        'chunk_count': chunkCount,
        'page_count': pageCount,
        'error': error,
        'text': text,
        'job_id': jobId,
      };
}
