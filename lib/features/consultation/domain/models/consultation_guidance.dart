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
}
