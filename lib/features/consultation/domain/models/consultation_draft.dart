enum TriageAnswer { unknown, yes, no }

class ConsultationDraft {
  const ConsultationDraft({
    required this.description,
    required this.helpRequested,
    this.photoPath,
    this.audioPath,
    this.responds = TriageAnswer.unknown,
    this.breathesNormally = TriageAnswer.unknown,
    this.heavyBleeding = TriageAnswer.unknown,
  });
  final String description;
  final bool helpRequested;
  final String? photoPath;
  final String? audioPath;
  final TriageAnswer responds;
  final TriageAnswer breathesNormally;
  final TriageAnswer heavyBleeding;

  bool get hasInput =>
      description.trim().isNotEmpty || photoPath != null || audioPath != null;
}
