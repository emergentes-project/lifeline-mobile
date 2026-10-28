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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
              ),
              if (state.error != null)
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: state.status == AuthStatus.busy
                    ? null
                    : () {
                        context.read<AuthCubit>().unlock(password.text);
                        password.clear();
                      },
                child: const Text('Desbloquear'),
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
      ),
    );
  }
}
