import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/blocs/auth_cubit.dart';
import '../features/auth/presentation/blocs/auth_state.dart';
import '../features/auth/presentation/entry_page.dart';
import '../features/auth/presentation/locked_page.dart';
import '../features/auth/presentation/profile_page.dart';
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
              name: state.user!.fullName,
              role: state.user!.role,
              guest: false,
            );
          case AuthStatus.guest:
            return const _CurrentHome(
              name: 'Invitado',
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
    required this.name,
    required this.role,
    required this.guest,
  });
  final String name, role;
  final bool guest;
  @override
  Widget build(BuildContext context) => role == 'CITIZEN'
      ? ConsultationFormPage(
          key: ValueKey(guest ? 'guest' : name),
          guest: guest,
        )
      : Scaffold(
          appBar: AppBar(
            title: const Text('Lifeline'),
            actions: [
              IconButton(
                tooltip: 'Mi perfil',
                icon: const Icon(Icons.person_outline),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guest ? 'Acceso de emergencia' : 'Hola, $name',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  guest
                      ? 'Puedes consultar sin crear una cuenta. El formulario de consulta se conectará en la siguiente parte.'
                      : role == 'CITIZEN'
                      ? 'Tu sesión está disponible sin internet. La consulta se implementará en la siguiente parte.'
                      : 'Tu sesión está disponible sin internet. Los casos necesitan conexión para actualizarse.',
                ),
                const Spacer(),
                if (guest)
                  TextButton(
                    onPressed: () => context.read<AuthCubit>().leaveGuest(),
                    child: const Text('Volver al inicio'),
                  )
                else
                  TextButton(
                    onPressed: () => context.read<AuthCubit>().signOut(),
                    child: const Text('Cerrar sesión'),
                  ),
              ],
            ),
          ),
        );
}
