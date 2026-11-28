import 'dart:async';

import '../../auth/presentation/blocs/auth_state.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/saved_consultation.dart';
import 'consultation_owner.dart';
import 'consultation_sync_service.dart';

/// Runs while the app is active. Persisted work resumes after a restart/unlock.
class ConsultationSyncCoordinator {
  ConsultationSyncCoordinator({
    required this.repository,
    required this.sync,
    required this.currentAuth,
    required this.authChanges,
    required this.connectivityChanges,
    this.onSynced,
    this.interval = const Duration(seconds: 30),
  });

  final LocalConsultationRepository repository;
  final ConsultationSyncService sync;
  final AuthState Function() currentAuth;
  final Stream<AuthState> authChanges;
  final Stream<bool> connectivityChanges;
  final Future<void> Function(
    AuthState auth,
    List<SavedConsultation> before,
    List<SavedConsultation> after,
  )?
  onSynced;
  final Duration interval;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<bool>? _network;
  StreamSubscription<({String ownerKey, bool needsSync})>? _local;
  Timer? _timer;
  Timer? _debounce;
  bool _disposed = false, _started = false, _online = true, _foreground = true;
  bool _running = false, _queued = false, _forceRetry = false;
  String? _lastOwner;

  String? _owner(AuthState auth) {
    if (auth.status != AuthStatus.guest &&
        auth.status != AuthStatus.authenticated) {
      return null;
    }
    return consultationOwnerKey(auth);
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _lastOwner = _owner(currentAuth());
    _auth = authChanges.listen((auth) {
      final owner = _owner(auth);
      final changed = owner != _lastOwner;
      _lastOwner = owner;
      if (owner != null) requestSweep(forceRetry: changed);
    });
    _network = connectivityChanges.distinct().listen(
      setOnline,
      onError: (Object _) {},
    );
    _local = repository.changes.listen((change) {
      if (_disposed ||
          !change.needsSync ||
          change.ownerKey != _owner(currentAuth())) {
        return;
      }
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), requestSweep);
    });
    _timer = Timer.periodic(interval, (_) => requestSweep());
    requestSweep();
  }

  void setOnline(bool value) {
    final restored = !_online && value;
    _online = value;
    if (restored) requestSweep(forceRetry: true);
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) requestSweep(forceRetry: true);
  }

  void requestSweep({bool forceRetry = false}) {
    if (_disposed || !_online || !_foreground) return;
    _queued = true;
    _forceRetry = _forceRetry || forceRetry;
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_queued && !_disposed && _online && _foreground) {
        _queued = false;
        final force = _forceRetry;
        _forceRetry = false;
        final auth = currentAuth();
        final owner = _owner(auth);
        if (owner == null) continue;
        final citizen =
            auth.status == AuthStatus.authenticated &&
            auth.user?.isCitizen == true;
        final citizenId = citizen ? auth.user!.id : null;
        final token = citizen ? auth.user!.token : null;
        try {
          final before = await repository.list(ownerKey: owner);
          if (_disposed || _owner(currentAuth()) != owner) continue;
          await sync.syncPending(
            ownerKey: owner,
            citizenUserId: citizenId,
            accessToken: token,
            forceRetry: force,
          );
          if (_disposed || _owner(currentAuth()) != owner) continue;
          await sync.refreshTracking(
            ownerKey: owner,
            citizenUserId: citizenId,
            accessToken: token,
          );
          if (_disposed || _owner(currentAuth()) != owner) continue;
          final after = await repository.list(ownerKey: owner);
          if (!_disposed && _owner(currentAuth()) == owner) {
            await onSynced?.call(auth, before, after);
          }
        } catch (_) {
          // Local storage and server errors never discard pending work or block the UI.
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _debounce?.cancel();
    await _auth?.cancel();
    await _network?.cancel();
    await _local?.cancel();
  }
}
