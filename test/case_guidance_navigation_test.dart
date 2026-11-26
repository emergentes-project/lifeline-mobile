import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/auth/domain/models/authenticated_user.dart';
import 'package:lifeline_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_cubit.dart';
import 'package:lifeline_mobile/features/cases/application/case_management_service.dart';
import 'package:lifeline_mobile/features/cases/data/case_api_service.dart';
import 'package:lifeline_mobile/features/cases/domain/repositories/case_repository.dart';
import 'package:lifeline_mobile/features/cases/presentation/cases_page.dart';

void main() {
  testWidgets('medical staff opens the full guidance from a case', (
    tester,
  ) async {
    const guidance =
        'Medidas iniciales\n'
        '1. Después de un golpe en la cabeza o ante sospecha de lesión de columna, evita movimientos innecesarios.\n'
        '2. Comprueba la respiración.\n\n'
        'Indicaciones médicas\n'
        '1. Mantén a la persona abrigada mientras llega ayuda.';
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/cases/case-1')) {
        return http.Response(
          jsonEncode({
            'id': 'case-1',
            'consultationId': 'consult-1',
            'status': 'CLOSED',
          }),
          200,
        );
      }
      if (path.endsWith('/consultation-submissions/consult-1')) {
        return http.Response(
          jsonEncode({
            'inputText': 'Golpe en la cabeza',
            'helpRequested': true,
            'hasPhoto': false,
            'answer': {
              'guidanceStatus': 'GENERATED',
              'guidanceText': guidance,
              'preliminaryPriority': 'MEDIUM',
              'professionalHelpRecommended': true,
              'sourceReferences': [
                {'institution': 'Cruz Roja', 'title': 'Primeros auxilios'},
              ],
            },
          }),
          200,
        );
      }
      if (path.endsWith('/cases/case-1/history')) {
        return http.Response('[]', 200);
      }
      return http.Response('Not found', 404);
    });
    addTearDown(client.close);
    final auth = AuthCubit(_MedicalAuthRepository());
    addTearDown(auth.close);
    await auth.signIn('medico@example.com', 'clave');
    final service = CaseManagementService(
      cases: CaseApiService(client),
      verification: _ApprovedVerification(),
    );

    await tester.pumpWidget(
      RepositoryProvider<CaseManagementService>.value(
        value: service,
        child: BlocProvider<AuthCubit>.value(
          value: auth,
          child: const MaterialApp(
            home: CaseDetailPage(caseId: 'case-1', citizen: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Orientación generada'), findsOneWidget);

    await tester.ensureVisible(find.text('Orientación generada'));
    await tester.tap(find.text('Orientación generada'));
    await tester.pumpAndSettle();

    expect(find.text('Medidas iniciales'), findsOneWidget);
    expect(find.text('Indicaciones médicas'), findsOneWidget);
    expect(
      find.textContaining('sospecha de lesión de columna'),
      findsOneWidget,
    );
    expect(find.textContaining('Mantén a la persona abrigada'), findsOneWidget);
    expect(find.text('Cruz Roja'), findsOneWidget);
  });
}

class _ApprovedVerification implements ProfessionalVerificationRepository {
  @override
  Future<String> status(String token) async => 'APPROVED';
}

class _MedicalAuthRepository implements AuthRepository {
  @override
  Future<AuthenticatedUser> signIn(String email, String password) async =>
      const AuthenticatedUser(
        id: 'doctor-1',
        email: 'medico@example.com',
        firstName: 'Ana',
        lastName: 'Paz',
        role: 'MEDICAL_PROFESSIONAL',
        token: 'jwt',
      );

  @override
  Future<AuthenticatedUser> registerCitizen(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<AuthenticatedUser> registerMedicalProfessional(
    Map<String, dynamic> data,
  ) => throw UnimplementedError();

  @override
  Future<AuthenticatedUser?> restoreSession() async => null;

  @override
  Future<bool> unlock(String password) async => false;

  @override
  Future<void> updateSavedUser(AuthenticatedUser user) async {}

  @override
  Future<void> signOut() async {}
}
