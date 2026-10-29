import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/auth_cubit.dart';
import 'blocs/auth_state.dart';

class LockedPage extends StatefulWidget {
  const LockedPage({super.key});
  @override
  State<LockedPage> createState() => _LockedPageState();
}

class _LockedPageState extends State<LockedPage> {
  final password = TextEditingController();
  bool showPassword = false;

  void unlock() {
    if (context.read<AuthCubit>().state.status == AuthStatus.busy) return;
    context.read<AuthCubit>().unlock(password.text);
    password.clear();
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthCubit>().state;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            Text(
              'Bienvenida, ${state.user?.firstName ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Desbloquea tus datos con tu contraseña de Lifeline. Funciona sin internet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: password,
              obscureText: !showPassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unlock(),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  tooltip: showPassword
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña',
                  onPressed: () => setState(() => showPassword = !showPassword),
                  icon: Icon(
                    showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: state.status == AuthStatus.busy ? null : unlock,
              child: Text(
                state.status == AuthStatus.busy
                    ? 'Desbloqueando...'
                    : 'Desbloquear',
              ),
            ),
            TextButton(
              onPressed: () => context.read<AuthCubit>().continueAsGuest(),
              child: const Text('Consulta de emergencia sin cuenta'),
            ),
            TextButton(
              onPressed: () => context.read<AuthCubit>().signOut(),
              child: const Text('Cerrar sesión en este dispositivo'),
            ),
          ],
        ),
      ),
    );
  }
}
