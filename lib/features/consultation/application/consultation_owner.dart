import '../../auth/presentation/blocs/auth_state.dart';

String consultationOwnerKey(AuthState auth) {
  if (auth.status == AuthStatus.guest) return 'guest';
  if (auth.status == AuthStatus.authenticated && auth.user != null) {
    return 'user:${auth.user!.id}';
  }
  throw StateError('Desbloquea la sesión para acceder a las consultas.');
}
