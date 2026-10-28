import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/auth_cubit.dart';
import 'blocs/auth_state.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Iniciar sesión')),
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
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
              ),
              validator: (v) => v == null || !v.contains('@')
                  ? 'Ingresa un correo válido'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  context.read<AuthCubit>().signIn(email.text, password.text);
                }
              },
              child: const Text('Iniciar sesión'),
            ),
          ],
        ),
      ),
    ),
  );
}
