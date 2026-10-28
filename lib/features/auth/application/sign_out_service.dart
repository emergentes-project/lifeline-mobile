import '../domain/repositories/auth_repository.dart';

class SignOutService {
  const SignOutService(this.repository);
  final AuthRepository repository;
  Future<void> call() => repository.signOut();
}
