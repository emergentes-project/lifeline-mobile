class IncomingNotice {
  const IncomingNotice({required this.title, required this.body, this.caseId});

  final String title;
  final String body;
  final String? caseId;

  String get visibleText =>
      [title, body].where((line) => line.isNotEmpty).join('\n');

  factory IncomingNotice.from({
    String? title,
    String? body,
    Map<String, dynamic>? data,
  }) {
    final raw = data?['caseId'];
    final caseId = raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    return IncomingNotice(
      title: title?.trim() ?? (data?['title'] is String ? (data!['title'] as String).trim() : ''),
      body: body?.trim() ?? (data?['body'] is String ? (data!['body'] as String).trim() : ''),
      caseId: caseId,
    );
  }
}
