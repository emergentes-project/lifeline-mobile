import '../models/authenticated_user.dart';

abstract class AuthRepository {
  Future<AuthenticatedUser> signIn(String email, String password);
  Future<AuthenticatedUser> registerCitizen(Map<String, dynamic> data);
  Future<AuthenticatedUser> registerMedicalProfessional(
    Map<String, dynamic> data,
  );
  Future<AuthenticatedUser?> restoreSession();
  Future<bool> unlock(String password);
  Future<void> signOut();
}
