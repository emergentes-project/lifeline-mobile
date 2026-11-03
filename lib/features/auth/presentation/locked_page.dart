import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/presentation/system_status_bar.dart';
import '../../../core/theme/app_theme.dart';
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
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const SystemStatusBar(mode: SystemStatusMode.offline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                children: [
                  const SizedBox(height: 32),
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.teal, width: 2),
                      ),
                      child: const Center(
                        child: Icon(Icons.lock_outline_rounded, size: 40, color: AppTheme.teal),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Bienvenida, ${state.user?.firstName ?? ''}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Desbloquea tus datos con tu contraseña de Lifeline. Funciona sin internet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      color: AppTheme.slateMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: password,
                    obscureText: !showPassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unlock(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      hintText: '••••••••',
                      suffixIcon: IconButton(
                        tooltip: showPassword
                            ? 'Ocultar contraseña'
                            : 'Mostrar contraseña',
                        onPressed: () => setState(() => showPassword = !showPassword),
                        icon: Icon(
                          showPassword ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ),
                  ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF64748B),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: state.status == AuthStatus.busy ? null : unlock,
                      child: Text(
                        state.status == AuthStatus.busy
                            ? 'Desbloqueando...'
                            : 'Desbloquear',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.read<AuthCubit>().continueAsGuest(),
                    child: const Text('Consulta de emergencia sin cuenta'),
                  ),
                  TextButton(
                    onPressed: () => context.read<AuthCubit>().signOut(),
                    child: const Text(
                      'Cerrar sesión en este dispositivo',
                      style: TextStyle(color: AppTheme.slateMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
