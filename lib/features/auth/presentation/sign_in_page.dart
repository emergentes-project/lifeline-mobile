import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/presentation/system_status_bar.dart';
import '../../../core/presentation/wireframe_components.dart';
import '../../../core/theme/app_theme.dart';
import 'blocs/auth_cubit.dart';
import 'blocs/auth_state.dart';
import 'citizen_registration_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool showPassword = false;

  void submit() {
    if (context.read<AuthCubit>().state.status == AuthStatus.busy) return;
    if (form.currentState!.validate()) {
      context.read<AuthCubit>().signIn(email.text.trim(), password.text);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Iniciar sesión'),
      bottom: const SystemStatusBar(mode: SystemStatusMode.offline),
    ),
    body: BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.authenticated &&
            Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        if (state.error != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.error!)));
        }
      },
      child: AutofillGroup(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              const SizedBox(height: 12),
              const LifelineLogoBadge(size: 80),
              const SizedBox(height: 16),
              Text(
                'Lifeline',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
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
                      showPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
              ),
              const SizedBox(height: 24),
              BlocBuilder<AuthCubit, AuthState>(
                builder: (context, state) => FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF64748B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: state.status == AuthStatus.busy ? null : submit,
                  child: Text(
                    state.status == AuthStatus.busy
                        ? 'Ingresando...'
                        : 'Iniciar sesión',
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.slate, width: 1.5),
                  foregroundColor: AppTheme.slate,
                ),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CitizenRegistrationPage(),
                  ),
                ),
                child: const Text('Crear cuenta'),
              ),
              const SizedBox(height: 16),
              DashedOutlineButton(
                onPressed: () {
                  context.read<AuthCubit>().continueAsGuest();
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
                label: 'Consulta de emergencia sin cuenta',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
