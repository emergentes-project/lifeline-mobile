import 'package:flutter_test/flutter_test.dart';
import 'package:lifeline_mobile/features/cases/application/case_management_service.dart';
import 'package:lifeline_mobile/features/cases/domain/models/managed_case.dart';
import 'package:lifeline_mobile/features/cases/domain/repositories/case_repository.dart';

void main() {
  test('professional must be approved before loading cases', () async {
    final cases = _Cases();
    final service = CaseManagementService(
      cases: cases,
      verification: _Verification('PENDING'),
    );

    await expectLater(
      service.loadLists('token', citizen: false),
      throwsA(isA<ProfessionalVerificationRequired>()),
    );
    expect(cases.reads, 0);
  });

  test('action checks fresh state and reloads detail after success', () async {
    final cases = _Cases();
    final service = CaseManagementService(
      cases: cases,
      verification: _Verification('APPROVED'),
    );

    await expectLater(
      service.perform('token', 'doctor', 'case-1', CaseAction.start),
      throwsA(isA<CaseTransitionUnavailable>()),
    );
    expect(cases.transitions, 0);

    final detail = await service.perform(
      'token',
      'doctor',
      'case-1',
      CaseAction.assign,
    );
    expect(detail.caseRecord.status, CaseStatus.assigned);
    expect(cases.transitions, 1);
    expect(cases.reads, 3);
  });

  test('only assignee may close and observation is required', () async {
    final cases = _Cases()
      ..current = const ManagedCase(
        id: 'case-1',
        consultationId: 'consult-1',
        status: CaseStatus.inProgress,
        assignedProfessionalUserId: 'doctor',
      );
    final service = CaseManagementService(
      cases: cases,
      verification: _Verification('APPROVED'),
    );

    await expectLater(
      service.perform(
        'token',
        'other',
        'case-1',
        CaseAction.close,
        observation: 'Atendido',
      ),
      throwsA(isA<CaseTransitionUnavailable>()),
    );
    await expectLater(
      service.perform(
        'token',
        'doctor',
        'case-1',
        CaseAction.close,
        observation: '  ',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(cases.transitions, 0);

    final detail = await service.perform(
      'token',
      'doctor',
      'case-1',
      CaseAction.close,
      observation: '  Atendido  ',
    );
    expect(detail.caseRecord.status, CaseStatus.closed);
    expect(detail.caseRecord.observation, 'Atendido');
  });
}

class _Verification implements ProfessionalVerificationRepository {
  _Verification(this.value);
  final String value;
  @override
  Future<String> status(String token) async => value;
}

class _Cases implements CaseRepository {
  ManagedCase current = const ManagedCase(
    id: 'case-1',
    consultationId: 'consult-1',
    status: CaseStatus.available,
  );
  int reads = 0;
  int transitions = 0;

  @override
  Future<CasePage<ManagedCase>> listPage(
    String token, {
    required bool citizen,
    required bool assignedToMe,
    required CaseFilters filters,
    required int page,
    required int size,
  }) async => CasePage(
    items: [current],
    page: page,
    size: size,
    totalElements: 1,
    totalPages: 1,
  );

  @override
  Future<ManagedCase> get(String token, String id) async {
    reads++;
    return current;
  }

  @override
  Future<ManagedCase> assign(String token, String id) async {
    transitions++;
    current = const ManagedCase(
      id: 'case-1',
      consultationId: 'consult-1',
      status: CaseStatus.assigned,
      assignedProfessionalUserId: 'doctor',
    );
    return current;
  }

  @override
  Future<ManagedCase> changeStatus(
    String token,
    String id,
    CaseStatus status,
  ) async {
    transitions++;
    current = ManagedCase(
      id: 'case-1',
      consultationId: 'consult-1',
      status: status,
      assignedProfessionalUserId: status == CaseStatus.available
          ? null
          : 'doctor',
    );
    return current;
  }

  @override
  Future<ManagedCase> close(String token, String id, String observation) async {
    transitions++;
    current = ManagedCase(
      id: 'case-1',
      consultationId: 'consult-1',
      status: CaseStatus.closed,
      assignedProfessionalUserId: 'doctor',
      observation: observation,
    );
    return current;
  }

  @override
  Future<CaseConsultation> consultation(String token, String id) async =>
      const CaseConsultation(helpRequested: true, hasPhoto: false);
  @override
  Future<List<CaseStatusChange>> history(String token, String id) async => [];
  @override
  Future<List<ManagedCase>> listAvailable(String token) async {
    reads++;
    return [current];
  }

  @override
  Future<List<ManagedCase>> listAssignedToMe(String token) async => [];
  @override
  Future<List<ManagedCase>> listForCitizen(String token) async => [];
}
