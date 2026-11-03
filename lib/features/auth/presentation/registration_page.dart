import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/presentation/system_status_bar.dart';
import '../../../core/theme/app_theme.dart';
import 'blocs/auth_cubit.dart';
import 'blocs/auth_state.dart';
import 'sign_in_page.dart';

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
    String? hint,
    bool required = true,
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
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
        hintText: hint,
        suffixIcon: secret
            ? IconButton(
                tooltip: showPassword
                    ? 'Ocultar contraseña'
                    : 'Mostrar contraseña',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                  showPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.slateMuted,
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
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Crear cuenta'),
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
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Role Selector matching Wireframe A-02 and A-03
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: context.watch<AuthCubit>().state.status == AuthStatus.busy
                          ? null
                          : () => setState(() => medical = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !medical ? const Color(0xFF475569) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Ciudadano',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTheme.fontHeading,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: !medical ? Colors.white : AppTheme.slateMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: context.watch<AuthCubit>().state.status == AuthStatus.busy
                          ? null
                          : () => setState(() => medical = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: medical ? const Color(0xFF475569) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Personal médico',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTheme.fontHeading,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: medical ? Colors.white : AppTheme.slateMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Nombres y Apellidos en Row (Wireframe A-02/A-03)
            Row(
              children: [
                Expanded(
                  child: input(
                    'firstName',
                    'Nombres',
                    hint: medical ? 'Ej. Luis' : 'Ej. Adriana',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: input(
                    'lastName',
                    'Apellidos',
                    hint: medical ? 'Ej. Mendoza' : 'Ej. Rojas',
                  ),
                ),
              ],
            ),

            input(
              'email',
              'Correo electrónico',
              hint: 'nombre@correo.com',
              keyboard: TextInputType.emailAddress,
            ),
            input(
              'phone',
              'Teléfono (opcional)',
              hint: '999 999 999',
              required: false,
              keyboard: TextInputType.phone,
            ),

            if (medical) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Categoría profesional',
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down),
                  items: const [
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
                          child: Text(
                            switch (value) {
                              'DOCTOR' => 'Médico / Doctor',
                              'NURSE' => 'Enfermería',
                              'PARAMEDIC' => 'Paramédico',
                              'FIREFIGHTER' => 'Bombero rescatista',
                              'MEDICAL_INTERN' => 'Interno de medicina',
                              'MEDICAL_RESIDENT' => 'Residente médico',
                              _ => value,
                            },
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => category = value ?? category),
                ),
              ),
              input(
                'professionalLicenseNumber',
                'N.º de identificación profesional',
                hint: 'Ej. 000000',
              ),
              input(
                'specialty',
                'Especialidad (opcional)',
                hint: 'Ej. Medicina de emergencia',
                required: false,
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text(
                  'Validaremos tu identificación profesional antes de habilitar el rol.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 12,
                    color: AppTheme.slateMuted,
                  ),
                ),
              ),
            ] else ...[
              // Ciudad y Distrito en Row (Wireframe A-02)
              Row(
                children: [
                  Expanded(
                    child: input('city', 'Ciudad', hint: 'Ej. Lima'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: input('district', 'Distrito', hint: 'Ej. Miraflores'),
                  ),
                ],
              ),
              input('address', 'Dirección', hint: 'Av. / calle y número'),
              // Fecha de nacimiento estilizada con ícono de calendario
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InkWell(
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: DateTime(2000),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (selected != null) setState(() => birthDate = selected);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                    ),
                    child: Text(
                      birthDate == null
                          ? 'DD / MM / AAAA'
                          : '${birthDate!.day.toString().padLeft(2, '0')} / ${birthDate!.month.toString().padLeft(2, '0')} / ${birthDate!.year}',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        color: birthDate == null ? const Color(0xFF94A3B8) : AppTheme.slate,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              input(
                'emergencyContactName',
                'Contacto de emergencia (opcional)',
                hint: 'Ej. María Rojas',
                required: false,
              ),
              input(
                'emergencyContactPhone',
                'Teléfono del contacto (opcional)',
                hint: '999 888 777',
                required: false,
                keyboard: TextInputType.phone,
              ),
            ],

            input(
              'password',
              'Contraseña',
              hint: 'Mínimo 8 caracteres',
              secret: true,
            ),
            const SizedBox(height: 8),

            // Submit Button
            BlocBuilder<AuthCubit, AuthState>(
              builder: (context, state) => FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF64748B),
                  foregroundColor: Colors.white,
                ),
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
            const SizedBox(height: 16),

            // "¿Ya tienes cuenta? Inicia sesión"
            TextButton(
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const SignInPage()),
                  );
                }
              },
              child: const Text(
                '¿Ya tienes cuenta? Inicia sesión',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  color: AppTheme.slateMuted,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
