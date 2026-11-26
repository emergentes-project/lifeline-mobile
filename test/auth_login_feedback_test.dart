import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeline_mobile/app/app.dart';
import 'package:lifeline_mobile/features/auth/data/remote/auth_api_service.dart';
import 'package:lifeline_mobile/features/auth/domain/models/authenticated_user.dart';
import 'package:lifeline_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_cubit.dart';

void main() {
  testWidgets('failed login keeps the form and displays the reason', (
    tester,
  ) async {
    final auth = AuthCubit(_RejectingAuthRepository());
    addTearDown(auth.close);
    await auth.restore();
    await tester.pumpWidget(
      BlocProvider<AuthCubit>.value(value: auth, child: const LifelineApp()),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo electrónico'),
      'ana@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      'incorrecta',
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.text('Correo o contraseña incorrectos para este servidor.'),
      findsOneWidget,
    );
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
  });
}

class _RejectingAuthRepository implements AuthRepository {
  @override
  Future<AuthenticatedUser> signIn(String email, String password) async =>
      throw const AuthApiException(
        'Correo o contraseña incorrectos para este servidor.',
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
