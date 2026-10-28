import '../domain/models/authenticated_user.dart';
import '../domain/repositories/auth_repository.dart';

class RestoreSessionService {
  const RestoreSessionService(this.repository);
  final AuthRepository repository;
  Future<AuthenticatedUser?> call() => repository.restoreSession();
}
