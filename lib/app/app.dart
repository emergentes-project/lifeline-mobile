import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/blocs/auth_cubit.dart';
import '../features/auth/presentation/blocs/auth_state.dart';
import '../features/auth/presentation/entry_page.dart';
import '../features/auth/presentation/locked_page.dart';
import '../features/cases/presentation/cases_page.dart';
import '../features/consultation/application/consultation_owner.dart';
import '../features/consultation/data/local/local_consultation_repository.dart';
import '../features/consultation/domain/models/saved_consultation.dart';
import '../features/consultation/presentation/consultation_form_page.dart';
import '../features/consultation/presentation/consultation_history_page.dart';
import '../features/notifications/application/publish_notification_token.dart';
import '../features/notifications/data/firebase_device_notifications.dart';

class LifelineApp extends StatefulWidget {
  const LifelineApp({super.key});

  @override
  State<LifelineApp> createState() => _LifelineAppState();
}

class _LifelineAppState extends State<LifelineApp> {
  final navigatorKey = GlobalKey<NavigatorState>();

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
      onOpenHistory: _openHistory,
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

  void _showMessage(String title, String body) {
    final host = navigatorKey.currentContext;
    if (host == null) return;
    final text = [
      title.trim(),
      body.trim(),
    ].where((line) => line.isNotEmpty).join('\n');
    if (text.isEmpty) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(host).hideCurrentSnackBar();
            _openHistory();
          },
          child: Text(text),
        ),
      ),
    );
  }

  void _openHistory() {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const ConsultationHistoryPage()),
    );
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
