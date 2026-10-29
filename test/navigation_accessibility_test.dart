import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeline_mobile/features/auth/domain/models/authenticated_user.dart';
import 'package:lifeline_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_cubit.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_state.dart';
import 'package:lifeline_mobile/features/auth/presentation/entry_page.dart';
import 'package:lifeline_mobile/features/auth/presentation/sign_in_page.dart';
import 'package:lifeline_mobile/features/consultation/presentation/consultation_form_page.dart';

void main() {
  testWidgets('emergency entry stays reachable with large text', (
    tester,
  ) async {
    final auth = AuthCubit(_AuthRepository());
    addTearDown(auth.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: auth,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const EntryPage(),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Consulta de emergencia sin cuenta'));
    await tester.tap(find.text('Consulta de emergencia sin cuenta'));
    expect(auth.state.status, AuthStatus.guest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign in lets users reveal and hide their password', (
    tester,
  ) async {
    final auth = AuthCubit(_AuthRepository());
    addTearDown(auth.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: auth,
        child: const MaterialApp(home: SignInPage()),
      ),
    );
    final password = find.widgetWithText(TextFormField, 'Contraseña');
    final editable = find.descendant(
      of: password,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).obscureText, isTrue);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(tester.widget<EditableText>(editable).obscureText, isFalse);
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pump();
    expect(tester.widget<EditableText>(editable).obscureText, isTrue);
  });

  testWidgets('guest menu exposes history and exit', (tester) async {
    final auth = AuthCubit(_AuthRepository())..continueAsGuest();
    addTearDown(auth.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: auth,
        child: const MaterialApp(home: ConsultationFormPage(guest: true)),
      ),
    );
    await tester.tap(find.byTooltip('Abrir menú de secciones'));
    await tester.pumpAndSettle();
    expect(find.text('Consultas guardadas'), findsOneWidget);
    expect(find.text('Mis casos'), findsNothing);
    await tester.tap(find.text('Salir'));
    await tester.pumpAndSettle();
    expect(auth.state.status, AuthStatus.signedOut);
  });
}

class _AuthRepository implements AuthRepository {
  @override
  Future<AuthenticatedUser> signIn(String email, String password) =>
      throw UnimplementedError();
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
