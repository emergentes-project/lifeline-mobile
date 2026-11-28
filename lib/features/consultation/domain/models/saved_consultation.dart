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
    required this.mobileConsultationId,
    required this.idempotencyKey,
    this.backendConsultationId,
    this.syncStatus = 'pending',
    this.guestAccessToken,
    this.caseId,
    this.caseStatus,
    this.caseUpdatedAt,
    this.syncAttempts = 0,
    this.nextSyncAt,
    this.syncError,
  });

  final int id;
  final DateTime createdAt;
  final ConsultationDraft draft;
  final PatientDraft? patient;
  final ConsultationGuidance? guidance;
  final String mobileConsultationId;
  final String idempotencyKey;
  final String? backendConsultationId;
  final String syncStatus;
  final String? guestAccessToken;
  final String? caseId;
  final String? caseStatus;
  final DateTime? caseUpdatedAt;
  final int syncAttempts;
  final DateTime? nextSyncAt;
  final String? syncError;

  bool get deliveryPending =>
      syncStatus == 'pending' || syncStatus == 'sending';

  String? get caseStatusLabel => switch (caseStatus) {
    'AVAILABLE' => 'Esperando profesional',
    'ASSIGNED' => 'Profesional asignado',
    'IN_PROGRESS' => 'En atención',
    'CLOSED' => 'Atención cerrada',
    _ => null,
  };

  bool get canRetry => guidance == null || !guidance!.isReady;
}
