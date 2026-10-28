import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/auth_cubit.dart';
import 'sign_in_page.dart';
import 'citizen_registration_page.dart';

class EntryPage extends StatelessWidget {
  const EntryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            Icon(
              Icons.health_and_safety_outlined,
              size: 76,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Lifeline',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Orientación de primeros auxilios, incluso sin internet.',
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SignInPage()),
              ),
              child: const Text('Iniciar sesión'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CitizenRegistrationPage(),
                ),
              ),
              child: const Text('Crear cuenta'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.read<AuthCubit>().continueAsGuest(),
              child: const Text('Consulta de emergencia sin cuenta'),
            ),
          ],
        ),
      ),
    ),
  );
}
