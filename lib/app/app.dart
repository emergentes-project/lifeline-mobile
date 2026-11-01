import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/blocs/auth_cubit.dart';
import '../features/auth/presentation/blocs/auth_state.dart';
import '../features/auth/presentation/entry_page.dart';
import '../features/auth/presentation/locked_page.dart';
import '../features/cases/application/case_management_service.dart';
import '../features/cases/presentation/cases_page.dart';
import '../features/consultation/application/consultation_owner.dart';
import '../features/consultation/data/local/local_consultation_repository.dart';
import '../features/consultation/domain/models/saved_consultation.dart';
import '../features/consultation/presentation/consultation_form_page.dart';
import '../features/consultation/presentation/consultation_history_page.dart';
import '../features/notifications/application/incoming_notice.dart';
import '../features/notifications/application/open_case_notice.dart';
import '../features/notifications/application/publish_notification_token.dart';
import '../features/notifications/data/firebase_device_notifications.dart';

class LifelineApp extends StatefulWidget {
  const LifelineApp({super.key});

  @override
  State<LifelineApp> createState() => _LifelineAppState();
}

class _LifelineAppState extends State<LifelineApp> {
  final navigatorKey = GlobalKey<NavigatorState>();
  String? _pendingCaseId;
  var _noticeWaiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startNotifications());
    });
  }

  Future<void> _startNotifications() async {
    if (!mounted) return;
    final device = _provided<FirebaseDeviceNotifications>(context);
    if (device == null) return;
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

  Future<void> _register(AuthState auth) async {
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
    final service = _provided<CaseManagementService>(context);
    final citizen =
        auth.status == AuthStatus.authenticated && auth.user?.isCitizen == true;
    final destination = await destinationForCaseNotice(
      citizenSignedIn: citizen,
      caseId: caseId,
      loadCase: (id) async {
        final token = auth.user?.token;
        if (service == null || token == null || token.isEmpty) {
          throw StateError('sin caso');
        }
        await service.loadDetail(token, id, citizen: true);
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
        builder: (_) => CaseDetailPage(caseId: id, citizen: true),
      ),
    );
  }

  void _openPendingNotice(AuthState auth) {
    if (!_noticeWaiting) return;
    if (auth.status == AuthStatus.loading ||
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
            case AuthStatus.busy:
              if (state.user != null) return const LockedPage();
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
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
