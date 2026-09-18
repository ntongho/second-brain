class Citation {
  const Citation({
    required this.chunkId,
    required this.documentId,
    required this.title,
    required this.snippet,
    this.page,
    this.startChar,
    this.endChar,
    this.score = 0,
    this.retrieval,
  });

  final String chunkId;
  final String documentId;
  final String title;
  final String snippet;
  final int? page;
  final int? startChar;
  final int? endChar;
  final double score;
  final String? retrieval;

  String get label {
    final pageBit = page == null ? '' : ' · p.$page';
    final scoreBit = score > 0 ? ' · ${score.toStringAsFixed(2)}' : '';
    return '${title.isEmpty ? 'Doc' : title}$pageBit$scoreBit';
  }

  factory Citation.fromJson(Map<String, dynamic> json) {
    return Citation(
      chunkId: json['chunk_id'] as String? ?? '',
      documentId: json['document_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      page: (json['page'] as num?)?.toInt(),
      startChar: (json['start_char'] as num?)?.toInt(),
      endChar: (json['end_char'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      retrieval: json['retrieval'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'chunk_id': chunkId,
        'document_id': documentId,
        'title': title,
        'snippet': snippet,
        'page': page,
        'start_char': startChar,
        'end_char': endChar,
        'score': score,
        'retrieval': retrieval,
      };
}
