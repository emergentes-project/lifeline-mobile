import 'consultation_draft.dart';
import 'consultation_guidance.dart';
import 'patient_draft.dart';

class SavedConsultation {
  const SavedConsultation({
    required this.id,
    required this.createdAt,
    required this.draft,
    required this.patient,
    required this.guidance,
  });

  final int id;
  final DateTime createdAt;
  final ConsultationDraft draft;
  final PatientDraft? patient;
  final ConsultationGuidance? guidance;

  bool get canRetry => guidance == null || !guidance!.isReady;
}
