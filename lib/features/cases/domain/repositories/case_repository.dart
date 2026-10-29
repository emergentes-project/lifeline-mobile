import '../models/managed_case.dart';

abstract class CaseRepository {
  Future<List<ManagedCase>> listAvailable(String token);
  Future<List<ManagedCase>> listAssignedToMe(String token);
  Future<List<ManagedCase>> listForCitizen(String token);
  Future<ManagedCase> get(String token, String id);
  Future<CaseConsultation> consultation(String token, String id);
  Future<List<CaseStatusChange>> history(String token, String id);
  Future<ManagedCase> assign(String token, String id);
  Future<ManagedCase> changeStatus(String token, String id, CaseStatus status);
  Future<ManagedCase> close(String token, String id, String observation);
}

abstract class ProfessionalVerificationRepository {
  Future<String> status(String token);
}
