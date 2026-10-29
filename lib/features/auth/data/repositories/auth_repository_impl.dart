import '../../domain/models/authenticated_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/secure_session_storage.dart';
import '../remote/auth_api_service.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required this.api, required this.sessions});
  final AuthApiService api;
  final SecureSessionStorage sessions;

  @override
  Future<AuthenticatedUser> signIn(String email, String password) async {
    final user = await api.signIn(email.trim(), password);
    await sessions.save(user, password);
    return user;
  }

  @override
  Future<AuthenticatedUser> registerCitizen(Map<String, dynamic> data) async {
    await api.register('sign-up/citizens', data);
    return signIn(data['email'] as String, data['password'] as String);
  }

  @override
  Future<AuthenticatedUser> registerMedicalProfessional(
    Map<String, dynamic> data,
  ) async {
    await api.register('sign-up/medical-professionals', data);
    return signIn(data['email'] as String, data['password'] as String);
  }

  @override
  Future<AuthenticatedUser?> restoreSession() => sessions.read();
  @override
  Future<bool> unlock(String password) => sessions.verify(password);

  @override
  Future<void> updateSavedUser(AuthenticatedUser user) =>
      sessions.updateUser(user);
  @override
  Future<void> signOut() async {
    final user = await sessions.read();
    await sessions.clear();
    if (user != null) await api.signOut(user.token);
  }
}
