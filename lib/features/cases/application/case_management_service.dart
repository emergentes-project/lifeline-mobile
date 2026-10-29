import '../domain/models/managed_case.dart';
import '../domain/repositories/case_repository.dart';

class ProfessionalVerificationRequired implements Exception {
  const ProfessionalVerificationRequired(this.status);
  final String status;
  @override
  String toString() =>
      'Tu perfil profesional requiere verificación para ver o gestionar casos. Estado: $status.';
}

class CaseTransitionUnavailable implements Exception {
  const CaseTransitionUnavailable();
  @override
  String toString() =>
      'El caso ya no permite esta acción. Actualiza la pantalla.';
}

class CaseManagementService {
  const CaseManagementService({
    required this.cases,
    required this.verification,
  });

  final CaseRepository cases;
  final ProfessionalVerificationRepository verification;

  Future<void> _requireApproved(String token) async {
    final status = await verification.status(token);
    if (status != 'APPROVED') {
      throw ProfessionalVerificationRequired(status);
    }
  }

  Future<CaseLists> loadLists(String token, {required bool citizen}) async {
    if (!citizen) await _requireApproved(token);
    final lists = citizen
        ? [await cases.listForCitizen(token)]
        : await Future.wait([
            cases.listAvailable(token),
            cases.listAssignedToMe(token),
          ]);
    Future<List<CaseListItem>> enrich(List<ManagedCase> items) => Future.wait(
      items.map((item) async {
        try {
          return CaseListItem(
            item,
            await cases.consultation(token, item.consultationId),
          );
        } catch (_) {
          return CaseListItem(item, null);
        }
      }),
    );
    final groups = await Future.wait([
      enrich(citizen ? const [] : lists[0]),
      enrich(citizen ? lists[0] : lists[1]),
    ]);
    return CaseLists(available: groups[0], mine: groups[1]);
  }

  Future<CasePage<CaseListItem>> loadPage(
    String token, {
    required bool citizen,
    required bool assignedToMe,
    required CaseFilters filters,
    required int page,
    int size = 10,
  }) async {
    if (!citizen) await _requireApproved(token);
    final result = await cases.listPage(
      token,
      citizen: citizen,
      assignedToMe: assignedToMe,
      filters: filters,
      page: page,
      size: size,
    );
    final items = await Future.wait(
      result.items.map((item) async {
        try {
          return CaseListItem(
            item,
            await cases.consultation(token, item.consultationId),
          );
        } catch (_) {
          return CaseListItem(item, null);
        }
      }),
    );
    return CasePage(
      items: items,
      page: result.page,
      size: result.size,
      totalElements: result.totalElements,
      totalPages: result.totalPages,
    );
  }

  Future<CaseDetail> loadDetail(
    String token,
    String id, {
    required bool citizen,
  }) async {
    if (!citizen) await _requireApproved(token);
    final item = await cases.get(token, id);
    final values = await Future.wait<Object>([
      cases.consultation(token, item.consultationId),
      cases.history(token, id),
    ]);
    return CaseDetail(
      caseRecord: item,
      consultation: values[0] as CaseConsultation,
      history: values[1] as List<CaseStatusChange>,
    );
  }

  Future<CaseDetail> perform(
    String token,
    String professionalUserId,
    String id,
    CaseAction action, {
    String? observation,
  }) async {
    await _requireApproved(token);
    final current = await cases.get(token, id);
    if (!current.canPerform(action, professionalUserId)) {
      throw const CaseTransitionUnavailable();
    }
    switch (action) {
      case CaseAction.assign:
        await cases.assign(token, id);
      case CaseAction.start:
        await cases.changeStatus(token, id, CaseStatus.inProgress);
      case CaseAction.release:
        await cases.changeStatus(token, id, CaseStatus.available);
      case CaseAction.close:
        final text = observation?.trim() ?? '';
        if (text.isEmpty) {
          throw ArgumentError('La observación de cierre es obligatoria.');
        }
        await cases.close(token, id, text);
    }
    return loadDetail(token, id, citizen: false);
  }
}
