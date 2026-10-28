import '../domain/models/authenticated_user.dart';
import '../domain/repositories/auth_repository.dart';

class SignInService {
  const SignInService(this.repository);
  final AuthRepository repository;
  Future<AuthenticatedUser> call(String email, String password) =>
      repository.signIn(email, password);
}
