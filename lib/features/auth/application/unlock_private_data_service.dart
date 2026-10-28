import '../domain/repositories/auth_repository.dart';

class UnlockPrivateDataService {
  const UnlockPrivateDataService(this.repository);
  final AuthRepository repository;
  Future<bool> call(String password) => repository.unlock(password);
}
