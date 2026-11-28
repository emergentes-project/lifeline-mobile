import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/blocs/auth_cubit.dart';
import '../features/auth/presentation/blocs/auth_state.dart';
import '../features/auth/presentation/entry_page.dart';
import '../features/auth/presentation/locked_page.dart';
import '../features/cases/application/case_management_service.dart';
import '../features/cases/presentation/cases_page.dart';
import '../features/consultation/application/consultation_owner.dart';
import '../features/consultation/application/consultation_sync_service.dart';
import '../features/consultation/application/consultation_sync_coordinator.dart';
import '../features/notifications/application/delivery_confirmation_notices.dart';
import '../features/consultation/data/local/local_consultation_repository.dart';
import '../features/consultation/domain/models/saved_consultation.dart';
import '../features/consultation/presentation/consultation_form_page.dart';
import '../features/consultation/presentation/consultation_history_page.dart';
import '../features/notifications/application/incoming_notice.dart';
import '../features/notifications/application/open_case_notice.dart';
import '../features/notifications/application/publish_notification_token.dart';
import '../features/notifications/application/notification_registration.dart';
import '../features/consultation/presentation/patient_fields_page.dart';
import '../features/notifications/data/firebase_device_notifications.dart';

class LifelineApp extends StatefulWidget {
  const LifelineApp({super.key});

  @override
  State<LifelineApp> createState() => _LifelineAppState();
}

class _LifelineAppState extends State<LifelineApp> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  String? _pendingCaseId;
  var _noticeWaiting = false;
  ConsultationSyncCoordinator? _syncCoordinator;
  AuthState? _lastNotificationAuth;
  Future<void> _registrationQueue = Future<void>.value();
  FirebaseDeviceNotifications? _deviceNotifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSynchronization();
      unawaited(_startNotifications());
    });
  }

  void _startSynchronization() {
    if (!mounted) return;
    final repository = _provided<LocalConsultationRepository>(context);
    final sync = _provided<ConsultationSyncService>(context);
    if (repository == null || sync == null) return;
    final auth = context.read<AuthCubit>();
    _syncCoordinator = ConsultationSyncCoordinator(repository: repository, sync: sync,
      currentAuth: () => auth.state, authChanges: auth.stream,
      connectivityChanges: Connectivity().onConnectivityChanged.map(
        (states) => states.any((value) => value != ConnectivityResult.none)),
      onSynced: (snapshot, before, after) async {
        if (!mounted || consultationOwnerKey(auth.state) != consultationOwnerKey(snapshot)) return;
        await _provided<DeliveryConfirmationNotices>(context)?.announce(before, after);
        if (mounted) await _register(snapshot);
      });
    _syncCoordinator!.start();
    unawaited(Connectivity().checkConnectivity().then<void>((states) {
      _syncCoordinator?.setOnline(states.any((value) => value != ConnectivityResult.none));
    }).catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncCoordinator?.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_syncCoordinator?.dispose() ?? Future<void>.value());
    unawaited(_deviceNotifications?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _startNotifications() async {
    if (!mounted) return;
    final device = _provided<FirebaseDeviceNotifications>(context);
    if (device == null) return;
    _deviceNotifications = device;
    await device.start(
      onForeground: _showMessage,
      onOpened: (notice) {
        unawaited(_openNotice(notice.caseId));
      },
      onTokenChanged: () {
        if (!mounted) return;
        unawaited(_register(context.read<AuthCubit>().state));
      },
    );
    if (!mounted) return;
    await _register(context.read<AuthCubit>().state);
  }

  Future<void> _register(AuthState auth) {
    _registrationQueue = _registrationQueue.then<void>((_) => _registerNow(auth))
        .catchError((Object _) {});
    return _registrationQueue;
  }

  Future<void> _registerNow(AuthState auth) async {
    if (!mounted) return;
    if (!const [AuthStatus.authenticated, AuthStatus.guest, AuthStatus.signedOut].contains(auth.status)) return;
    final current = context.read<AuthCubit>().state;
    if (current.status != auth.status || current.user?.id != auth.user?.id) return;
    final previous = _lastNotificationAuth;
    _lastNotificationAuth = auth;
    if (previous?.status == AuthStatus.guest && auth.status != AuthStatus.guest) {
      final device = _provided<FirebaseDeviceNotifications>(context);
      final registration = _provided<NotificationRegistration>(context);
      final repository = _provided<LocalConsultationRepository>(context);
      final token = await device?.currentToken();
      if (token != null && registration != null && repository != null) {
        final guests = await repository.list(ownerKey: 'guest');
        for (final row in guests) {
          if (row.backendConsultationId == null || row.guestAccessToken == null) continue;
          await registration.revokeGuest(deviceToken: token, consultationId: row.backendConsultationId!,
            consultationAccessToken: row.guestAccessToken!);
        }
      }
    }
    if (!mounted) return;
    var consultations = const <SavedConsultation>[];
    if (auth.status == AuthStatus.guest) {
      final repository = _provided<LocalConsultationRepository>(context);
      if (repository != null) {
        try {
          consultations = await repository.list(
            ownerKey: consultationOwnerKey(auth),
          );
        } catch (_) {
          consultations = const [];
        }
      }
    }
    if (!mounted) return;
    await publishNotificationToken(
      context,
      auth: auth,
      consultations: consultations,
    );
  }

  void _showMessage(IncomingNotice notice) {
    _syncCoordinator?.requestSweep();
    final host = navigatorKey.currentContext;
    if (host == null || notice.visibleText.isEmpty) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(host).hideCurrentSnackBar();
            unawaited(_openNotice(notice.caseId));
          },
          child: Text(notice.visibleText),
        ),
      ),
    );
  }

  Future<void> _openNotice(String? caseId) async {
    if (!mounted) return;
    final auth = context.read<AuthCubit>().state;
    if (auth.status == AuthStatus.loading ||
        auth.status == AuthStatus.signedOut ||
        auth.status == AuthStatus.busy ||
        auth.status == AuthStatus.locked) {
      _noticeWaiting = true;
      _pendingCaseId = caseId;
      return;
    }
    _noticeWaiting = false;
    await _navigateNotice(auth, caseId);
  }

  Future<void> _navigateNotice(AuthState auth, String? caseId) async {
    if (auth.status != AuthStatus.guest && auth.status != AuthStatus.authenticated) return;
    if (auth.status == AuthStatus.guest && caseId != null) {
      final repository = _provided<LocalConsultationRepository>(context);
      final sync = _provided<ConsultationSyncService>(context);
      if (repository != null) {
        await sync?.refreshTracking(ownerKey: 'guest');
        final rows = await repository.list(ownerKey: 'guest');
        final row = rows.where((item) => item.caseId == caseId).firstOrNull;
        if (!mounted || context.read<AuthCubit>().state.status != AuthStatus.guest) return;
        if (row != null) {
          navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => ConsultationSummaryPage(
            draft: row.draft, patient: row.patient, savedId: row.id, initialGuidance: row.guidance,
            fromHistory: true, initialSyncStatus: row.syncStatus,
            initialBackendConsultationId: row.backendConsultationId,
          )));
          return;
        }
      }
    }
    final service = _provided<CaseManagementService>(context);
    final citizen =
        auth.status == AuthStatus.authenticated && auth.user?.isCitizen == true;
    final destination = await destinationForCaseNotice(
      citizenSignedIn: auth.status == AuthStatus.authenticated &&
          (citizen || auth.user?.role == 'MEDICAL_PROFESSIONAL'),
      caseId: caseId,
      loadCase: (id) async {
        final token = auth.user?.token;
        if (service == null || token == null || token.isEmpty) {
          throw StateError('sin caso');
        }
        await service.loadDetail(token, id, citizen: citizen);
      },
    );
    if (!mounted) return;
    final id = destination.caseId;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    if (id == null) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const ConsultationHistoryPage(),
        ),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CaseDetailPage(caseId: id, citizen: citizen),
      ),
    );
  }

  void _openPendingNotice(AuthState auth) {
    if (!_noticeWaiting) return;
    if (auth.status == AuthStatus.loading ||
        auth.status == AuthStatus.signedOut ||
        auth.status == AuthStatus.busy ||
        auth.status == AuthStatus.locked) {
      return;
    }
    _noticeWaiting = false;
    final caseId = _pendingCaseId;
    _pendingCaseId = null;
    unawaited(_navigateNotice(auth, caseId));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'Lifeline',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        unawaited(_register(state));
        _openPendingNotice(state);
      },
      child: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          switch (state.status) {
            case AuthStatus.loading:
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            case AuthStatus.busy:
              if (state.user != null) return const LockedPage();
              return const EntryPage();
            case AuthStatus.signedOut:
              return const EntryPage();
            case AuthStatus.locked:
              return const LockedPage();
            case AuthStatus.authenticated:
              return _CurrentHome(
                userId: state.user!.id,
                role: state.user!.role,
                guest: false,
              );
            case AuthStatus.guest:
              return const _CurrentHome(
                userId: 'guest',
                role: 'CITIZEN',
                guest: true,
              );
          }
        },
      ),
    ),
  );
}

class _CurrentHome extends StatelessWidget {
  const _CurrentHome({
    required this.userId,
    required this.role,
    required this.guest,
  });
  final String userId, role;
  final bool guest;
  @override
  Widget build(BuildContext context) => role == 'CITIZEN'
      ? ConsultationFormPage(key: ValueKey(userId), guest: guest)
      : const CasesPage(citizen: false);
}

T? _provided<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
