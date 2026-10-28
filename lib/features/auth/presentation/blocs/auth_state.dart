import '../../domain/models/authenticated_user.dart';

enum AuthStatus { loading, signedOut, locked, authenticated, guest, busy }

class AuthState {
  const AuthState({this.status = AuthStatus.loading, this.user, this.error});
  final AuthStatus status;
  final AuthenticatedUser? user;
  final String? error;
}
