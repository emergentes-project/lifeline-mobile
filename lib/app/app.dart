import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/blocs/auth_cubit.dart';
import '../features/auth/presentation/blocs/auth_state.dart';
import '../features/auth/presentation/entry_page.dart';
import '../features/auth/presentation/locked_page.dart';
import '../features/cases/presentation/cases_page.dart';
import '../features/consultation/presentation/consultation_form_page.dart';

class LifelineApp extends StatelessWidget {
  const LifelineApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lifeline',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: BlocBuilder<AuthCubit, AuthState>(
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
