import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/auth_cubit.dart';
import 'blocs/auth_state.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key, required this.medical});
  final bool medical;
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String category = 'DOCTOR';
  late bool medical;
  bool showPassword = false;
  DateTime? birthDate;
  @override
  void initState() {
    super.initState();
    medical = widget.medical;
  }

  TextEditingController field(String name) =>
      fields.putIfAbsent(name, TextEditingController.new);
  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget input(
    String key,
    String label, {
    bool required = true,
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: field(key),
      obscureText: secret && !showPassword,
      keyboardType: keyboard,
      autofillHints: key == 'email'
          ? const [AutofillHints.email]
          : key == 'password'
          ? const [AutofillHints.newPassword]
          : null,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: secret
            ? IconButton(
                tooltip: showPassword
                    ? 'Ocultar contraseña'
                    : 'Mostrar contraseña',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                  showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              )
            : null,
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Ingresa $label';
        }
        if (key == 'email' && value != null && !value.contains('@')) {
          return 'Correo inválido';
        }
        if (key == 'password' && value != null && value.length < 8) {
          return 'Mínimo 8 caracteres';
        }
        return null;
      },
    ),
  );

  Future<void> submit() async {
    if (context.read<AuthCubit>().state.status == AuthStatus.busy) return;
    if (!form.currentState!.validate()) return;
    if (!medical && birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona tu fecha de nacimiento')),
      );
      return;
    }
    if (!medical &&
        field('emergencyContactName').text.trim().isEmpty !=
            field('emergencyContactPhone').text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa el nombre y teléfono del contacto de emergencia.',
          ),
        ),
      );
      return;
    }
    final allowed = <String>{
      'firstName',
      'lastName',
      'email',
      'phone',
      'password',
      if (medical) ...{
        'professionalLicenseNumber',
        'specialty',
      } else ...{
        'city',
        'district',
        'address',
        'emergencyContactName',
        'emergencyContactPhone',
      },
    };
    final data = <String, dynamic>{
      for (final entry in fields.entries)
        if (allowed.contains(entry.key))
          entry.key: entry.value.text.trim().isEmpty
              ? null
              : entry.value.text.trim(),
    };
    data['password'] = field('password').text;
    if (medical) {
      data['professionalCategory'] = category;
    } else {
      data['dateOfBirth'] =
          '${birthDate!.year.toString().padLeft(4, '0')}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}';
    }
    await context.read<AuthCubit>().register(data, medical: medical);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear cuenta')),
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
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Ciudadano')),
                ButtonSegment(value: true, label: Text('Personal médico')),
              ],
              selected: {medical},
              onSelectionChanged:
                  context.watch<AuthCubit>().state.status == AuthStatus.busy
                  ? null
                  : (selection) => setState(() => medical = selection.first),
            ),
            const SizedBox(height: 20),
            input('firstName', 'Nombres'),
            input('lastName', 'Apellidos'),
            input(
              'email',
              'Correo electrónico',
              keyboard: TextInputType.emailAddress,
            ),
            input(
              'phone',
              'Teléfono',
              required: false,
              keyboard: TextInputType.phone,
            ),
            if (medical) ...[
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                  labelText: 'Categoría profesional',
                ),
                items:
                    const [
                          'DOCTOR',
                          'NURSE',
                          'PARAMEDIC',
                          'FIREFIGHTER',
                          'MEDICAL_INTERN',
                          'MEDICAL_RESIDENT',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) =>
                    setState(() => category = value ?? category),
              ),
              const SizedBox(height: 12),
              input(
                'professionalLicenseNumber',
                'N.º de identificación profesional',
              ),
              input('specialty', 'Especialidad', required: false),
            ] else ...[
              input('city', 'Ciudad'),
              input('district', 'Distrito'),
              input('address', 'Dirección'),
              OutlinedButton(
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: DateTime(2000),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (selected != null) setState(() => birthDate = selected);
                },
                child: Text(
                  birthDate == null
                      ? 'Fecha de nacimiento'
                      : '${birthDate!.day}/${birthDate!.month}/${birthDate!.year}',
                ),
              ),
              const SizedBox(height: 12),
              input(
                'emergencyContactName',
                'Contacto de emergencia',
                required: false,
              ),
              input(
                'emergencyContactPhone',
                'Teléfono del contacto',
                required: false,
                keyboard: TextInputType.phone,
              ),
            ],
            input('password', 'Contraseña', secret: true),
            const SizedBox(height: 12),
            BlocBuilder<AuthCubit, AuthState>(
              builder: (context, state) => FilledButton(
                onPressed: state.status == AuthStatus.busy ? null : submit,
                child: Text(
                  state.status == AuthStatus.busy
                      ? 'Creando cuenta...'
                      : medical
                      ? 'Registrarme como personal médico'
                      : 'Crear cuenta',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
