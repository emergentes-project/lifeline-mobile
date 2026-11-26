import '../../../medical_bases/data/index/local_medical_knowledge_repository.dart';

enum GuidanceStatus {
  ready,
  needsDescription,
  noEvidence,
  modelUnavailable,
  failed,
}

enum PreliminaryPriority { low, medium, high }

class ConsultationGuidance {
  const ConsultationGuidance({
    required this.status,
    required this.message,
    this.measures = const [],
    this.medicalIndications = const [],
    this.professionalHelp = const [],
    this.sources = const [],
    this.cardTitles = const [],
    this.chunkIds = const [],
    this.urgent = false,
    this.preliminaryPriority,
    this.priorityReason,
    this.professionalHelpRecommended,
  });

  final GuidanceStatus status;
  final String message;
  final List<String> measures;
  final List<String> medicalIndications;
  final List<String> professionalHelp;
  final List<MedicalSource> sources;
  final List<String> cardTitles;
  final List<String> chunkIds;
  final bool urgent;
  final PreliminaryPriority? preliminaryPriority;
  final String? priorityReason;
  final bool? professionalHelpRecommended;

  bool get isReady => status == GuidanceStatus.ready;

  String get fullTextForProfessional {
    String numbered(List<String> items) => [
      for (var i = 0; i < items.length; i++) '${i + 1}. ${items[i]}',
    ].join('\n');

    final sections = [
      if (measures.isNotEmpty) 'Medidas iniciales\n${numbered(measures)}',
      if (medicalIndications.isNotEmpty)
        'Indicaciones médicas\n${numbered(medicalIndications)}',
      if (professionalHelp.isNotEmpty)
        'Apoyo profesional\n${numbered(professionalHelp)}',
    ];
    return sections.isEmpty ? message : sections.join('\n\n');
  }
}
