import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/presentation/system_status_bar.dart';
import '../../../core/presentation/wireframe_components.dart';
import '../../../core/theme/app_theme.dart';
import 'blocs/auth_cubit.dart';
import 'blocs/auth_state.dart';
import 'citizen_registration_page.dart';

class EntryPage extends StatefulWidget {
  const EntryPage({super.key});

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool showPassword = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void submit() {
    if (context.read<AuthCubit>().state.status == AuthStatus.busy) return;
    if (form.currentState!.validate()) {
      context.read<AuthCubit>().signIn(email.text.trim(), password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const SystemStatusBar(mode: SystemStatusMode.offline),
            Expanded(
              child: BlocConsumer<AuthCubit, AuthState>(
                listener: (context, state) {
                  if (state.error != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(state.error!)),
                    );
                  }
                },
                builder: (context, state) {
                  final isBusy = state.status == AuthStatus.busy;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: AutofillGroup(
                      child: Form(
                        key: form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            // Logo Box (Rounded Square from Wireframe A-01)
                            const LifelineLogoBadge(size: 84),
                            const SizedBox(height: 16),
                            // Brand Title
                            Text(
                              'Lifeline',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: AppTheme.slate,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Subtitle
                            const Text(
                              'Orientación de primeros auxilios,\nincluso sin internet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 14,
                                color: AppTheme.slateMuted,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Email Field
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Correo electrónico',
                                hintText: 'nombre@correo.com',
                              ),
                              validator: (v) => v == null || !v.contains('@')
                                  ? 'Ingresa un correo válido'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            // Password Field
                            TextFormField(
                              controller: password,
                              obscureText: !showPassword,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => submit(),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                hintText: '••••••••',
                                suffixIcon: IconButton(
                                  tooltip: showPassword
                                      ? 'Ocultar contraseña'
                                      : 'Mostrar contraseña',
                                  onPressed: () =>
                                      setState(() => showPassword = !showPassword),
                                  icon: Icon(
                                    showPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Ingresa tu contraseña'
                                  : null,
                            ),
                            const SizedBox(height: 24),
                            // Iniciar sesión CTA (Filled Button)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF64748B),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: isBusy ? null : submit,
                              child: Text(
                                isBusy ? 'Ingresando...' : 'Iniciar sesión',
                              ),
                            ),
                            const SizedBox(height: 20),
                            // "¿Aún no tienes cuenta?" Text
                            const Text(
                              '¿Aún no tienes cuenta?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 14,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Crear cuenta CTA (Outlined Button)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.slate, width: 1.5),
                                foregroundColor: AppTheme.slate,
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CitizenRegistrationPage(),
                                ),
                              ),
                              child: const Text('Crear cuenta'),
                            ),
                            const SizedBox(height: 16),
                            // Consulta de emergencia sin cuenta (Dashed Button)
                            DashedOutlineButton(
                              onPressed: () =>
                                  context.read<AuthCubit>().continueAsGuest(),
                              label: 'Consulta de emergencia sin cuenta',
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
