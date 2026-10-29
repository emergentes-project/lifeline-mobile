import 'package:flutter_bloc/flutter_bloc.dart';
import '../../application/restore_session_service.dart';
import '../../application/sign_in_service.dart';
import '../../application/sign_out_service.dart';
import '../../application/unlock_private_data_service.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this.repository) : super(const AuthState());
  final AuthRepository repository;

  Future<void> restore() async {
    try {
      final user = await RestoreSessionService(repository)();
      emit(
        AuthState(
          status: user == null ? AuthStatus.signedOut : AuthStatus.locked,
          user: user,
        ),
      );
    } catch (_) {
      emit(const AuthState(status: AuthStatus.signedOut));
    }
  }

  Future<void> unlock(String password) async {
    final user = state.user;
    if (user == null) return;
    emit(AuthState(status: AuthStatus.busy, user: user));
    try {
      final valid = await UnlockPrivateDataService(repository)(password);
      emit(
        AuthState(
          status: valid ? AuthStatus.authenticated : AuthStatus.locked,
          user: user,
          error: valid ? null : 'Contraseña incorrecta.',
        ),
      );
    } catch (_) {
      emit(
        AuthState(
          status: AuthStatus.locked,
          user: user,
          error: 'No se pudo desbloquear la sesión.',
        ),
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    emit(const AuthState(status: AuthStatus.busy));
    try {
      emit(
        AuthState(
          status: AuthStatus.authenticated,
          user: await SignInService(repository)(email, password),
        ),
      );
    } catch (e) {
      emit(AuthState(status: AuthStatus.signedOut, error: '$e'));
    }
  }

  Future<void> register(
    Map<String, dynamic> data, {
    required bool medical,
  }) async {
    emit(const AuthState(status: AuthStatus.busy));
    try {
      final user = medical
          ? await repository.registerMedicalProfessional(data)
          : await repository.registerCitizen(data);
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (e) {
      emit(AuthState(status: AuthStatus.signedOut, error: '$e'));
    }
  }

  void continueAsGuest() => emit(const AuthState(status: AuthStatus.guest));
  void leaveGuest() => emit(const AuthState(status: AuthStatus.signedOut));

  Future<void> updateProfileAccount(
    String firstName,
    String lastName,
    String? phone,
  ) async {
    final current = state.user;
    if (current == null || state.status != AuthStatus.authenticated) return;
    final updated = current.withAccount(firstName, lastName, phone);
    await repository.updateSavedUser(updated);
    emit(AuthState(status: AuthStatus.authenticated, user: updated));
  }

  Future<void> signOut() async {
    emit(const AuthState(status: AuthStatus.busy));
    try {
      await SignOutService(repository)();
    } finally {
      emit(const AuthState(status: AuthStatus.signedOut));
    }
  }
}
