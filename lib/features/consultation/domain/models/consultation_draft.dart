class ConsultationDraft {
  const ConsultationDraft({
    required this.description,
    required this.helpRequested,
    this.photoPath,
    this.audioPath,
  });
  final String description;
  final bool helpRequested;
  final String? photoPath;
  final String? audioPath;

  bool get hasInput =>
      description.trim().isNotEmpty || photoPath != null || audioPath != null;
}
