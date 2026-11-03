import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/system_status_bar.dart';
import '../../../core/theme/app_theme.dart';
import '../data/remote/profile_api_service.dart';
import 'blocs/auth_cubit.dart';
import '../../../core/presentation/app_message_view.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? account;
  Map<String, dynamic>? roleProfile;
  String? error;
  bool loading = true;

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final user = context.read<AuthCubit>().state.user;
    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final api = context.read<ProfileApiService>();
    try {
      final values = await Future.wait([
        api.account(user.token),
        api.roleProfile(user.token, citizen: user.isCitizen),
      ]);
      if (!mounted) return;
      setState(() {
        account = values[0];
        roleProfile = values[1];
      });
    } on ProfileApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        account = null;
        roleProfile = null;
        error = exception.message;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo cargar el perfil. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Widget _profileField(String label, Object? value) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontHeading,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.slateMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value == null || '$value'.trim().isEmpty ? 'No registrado' : '$value',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppTheme.slate,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppTheme.borderLight, height: 1),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthCubit>().state.user;
    final citizen = user?.isCitizen ?? true;
    final fullName = account != null
        ? '${account!['firstName'] ?? ''} ${account!['lastName'] ?? ''}'.trim()
        : (user?.fullName ?? 'Usuario');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Mi perfil'),
        bottom: const SystemStatusBar(mode: SystemStatusMode.connected),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Cargando perfil',
              ),
            )
          : error != null
          ? AppMessageView(
              icon: Icons.wifi_off_outlined,
              title: 'No se pudo cargar el perfil',
              message: error!,
              actionLabel: 'Reintentar',
              onAction: load,
            )
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                children: [
                  // Avatar and Header (Wireframe M-07)
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person,
                          size: 52,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Full Name
                  Text(
                    fullName.isNotEmpty ? fullName : 'Nombre y apellidos',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Verified Status Badge (Wireframe M-07)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF475569),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        citizen
                            ? 'Ciudadano registrado'
                            : (roleProfile?['verificationStatus'] == 'APPROVED'
                                ? 'Identificación verificada'
                                : 'Identificación profesional'),
                        style: const TextStyle(
                          fontFamily: AppTheme.fontHeading,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Fields List (Wireframe M-07)
                  _profileField('Correo', account?['email']),
                  _profileField('Teléfono', account?['phone']),

                  if (!citizen) ...[
                    _profileField(
                      'Categoría profesional',
                      switch (roleProfile?['professionalCategory']) {
                        'DOCTOR' => 'Médico / Cirujano',
                        'NURSE' => 'Enfermería',
                        'PARAMEDIC' => 'Paramédico',
                        'FIREFIGHTER' => 'Bombero rescatista',
                        'MEDICAL_INTERN' => 'Interno de medicina',
                        'MEDICAL_RESIDENT' => 'Residente médico',
                        final other => other,
                      },
                    ),
                    _profileField(
                      'N.º de identificación profesional',
                      roleProfile?['professionalLicenseNumber'],
                    ),
                    _profileField('Especialidad', roleProfile?['specialty']),
                  ] else ...[
                    _profileField('Ciudad', roleProfile?['city']),
                    _profileField('Distrito', roleProfile?['district']),
                    _profileField('Dirección', roleProfile?['address']),
                    _profileField('Fecha de nacimiento', roleProfile?['dateOfBirth']),
                    _profileField(
                      'Contacto de emergencia',
                      roleProfile?['emergencyContactName'],
                    ),
                    _profileField(
                      'Teléfono del contacto',
                      roleProfile?['emergencyContactPhone'],
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action Button: Editar mis datos (Wireframe M-07)
                  if (account != null && roleProfile != null)
                    SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.slate, width: 1.5),
                          foregroundColor: AppTheme.slate,
                        ),
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileEditPage(
                                initialAccount: account!,
                                initialRoleProfile: roleProfile!,
                                citizen: citizen,
                              ),
                            ),
                          );
                          if (mounted) await load();
                        },
                        child: const Text('Editar mis datos'),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Action Button: Cerrar sesión (Wireframe M-07)
                  SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.border, width: 1.4),
                        foregroundColor: AppTheme.emergency,
                      ),
                      onPressed: () => context.read<AuthCubit>().signOut(),
                      child: const Text('Cerrar sesión'),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.initialAccount,
    required this.initialRoleProfile,
    required this.citizen,
  });
  final Map<String, dynamic> initialAccount;
  final Map<String, dynamic> initialRoleProfile;
  final bool citizen;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final accountForm = GlobalKey<FormState>();
  final roleForm = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late String category;
  bool savingAccount = false;
  bool savingRole = false;

  @override
  void initState() {
    super.initState();
    for (final source in [widget.initialAccount, widget.initialRoleProfile]) {
      for (final entry in source.entries) {
        if (entry.value is String) {
          fields[entry.key] = TextEditingController(
            text: entry.value as String,
          );
        }
      }
    }
    category =
        widget.initialRoleProfile['professionalCategory'] as String? ??
        'DOCTOR';
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String value(String key) => fields[key]?.text.trim() ?? '';
  String? optional(String key) => value(key).isEmpty ? null : value(key);

  Widget input(
    String key,
    String label, {
    String? hint,
    bool required = true,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields.putIfAbsent(key, TextEditingController.new),
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
      validator: (text) => required && (text == null || text.trim().isEmpty)
          ? 'Ingresa $label'
          : null,
    ),
  );

  void notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> saveAll() async {
    await saveAccount();
    if (mounted) {
      await saveRole();
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> saveAccount() async {
    if (!accountForm.currentState!.validate() || savingAccount || savingRole) {
      return;
    }
    setState(() => savingAccount = true);
    try {
      final api = context.read<ProfileApiService>();
      final token = context.read<AuthCubit>().state.user!.token;
      final result = await api.updateAccount(token, {
        'firstName': value('firstName'),
        'lastName': value('lastName'),
        'phone': optional('phone'),
      });
      if (!mounted) return;
      await context.read<AuthCubit>().updateProfileAccount(
        result['firstName'] as String,
        result['lastName'] as String,
        result['phone'] as String?,
      );
    } on ProfileApiException catch (exception) {
      if (mounted) notice('No se guardó la cuenta: ${exception.message}');
    } catch (_) {
      if (mounted) notice('No se guardó la cuenta. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => savingAccount = false);
    }
  }

  Future<void> saveRole() async {
    if (!roleForm.currentState!.validate() || savingAccount || savingRole) {
      return;
    }
    if (widget.citizen &&
        (value('emergencyContactName').isEmpty !=
            value('emergencyContactPhone').isEmpty)) {
      notice('Completa el nombre y teléfono del contacto de emergencia.');
      return;
    }
    setState(() => savingRole = true);
    try {
      final result = await context.read<ProfileApiService>().updateRoleProfile(
        context.read<AuthCubit>().state.user!.token,
        widget.citizen
            ? {
                'city': value('city'),
                'district': value('district'),
                'address': value('address'),
                'emergencyContactName': optional('emergencyContactName'),
                'emergencyContactPhone': optional('emergencyContactPhone'),
                'preExistingConditions': optional('preExistingConditions'),
                'allergies': optional('allergies'),
              }
            : {
                'professionalCategory': category,
                'professionalLicenseNumber': value('professionalLicenseNumber'),
                'specialty': optional('specialty'),
              },
        citizen: widget.citizen,
      );
      if (!mounted) return;
      widget.initialRoleProfile.addAll(result);
      notice('Datos actualizados.');
    } on ProfileApiException catch (exception) {
      if (mounted) notice('No se guardó el perfil: ${exception.message}');
    } catch (_) {
      if (mounted) notice('No se guardó el perfil. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => savingRole = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Editar perfil'),
      bottom: const SystemStatusBar(mode: SystemStatusMode.connected),
    ),
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Form(
          key: accountForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row: Nombres | Apellidos (Wireframe M-07 Edit)
              Row(
                children: [
                  Expanded(
                    child: input('firstName', 'Nombres', hint: 'Nombre'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: input('lastName', 'Apellidos', hint: 'Apellidos'),
                  ),
                ],
              ),
              input(
                'phone',
                'Teléfono (opcional)',
                hint: '999 999 999',
                required: false,
                keyboard: TextInputType.phone,
              ),
            ],
          ),
        ),
        Form(
          key: roleForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.citizen) ...[
                Row(
                  children: [
                    Expanded(child: input('city', 'Ciudad', hint: 'Ej. Lima')),
                    const SizedBox(width: 12),
                    Expanded(child: input('district', 'Distrito', hint: 'Ej. Miraflores')),
                  ],
                ),
                input('address', 'Dirección', hint: 'Av. / calle y número'),
                input(
                  'emergencyContactName',
                  'Contacto de emergencia',
                  required: false,
                ),
                input(
                  'emergencyContactPhone',
                  'Teléfono de contacto',
                  required: false,
                  keyboard: TextInputType.phone,
                ),
                input(
                  'preExistingConditions',
                  'Condiciones preexistentes',
                  required: false,
                ),
                input('allergies', 'Alergias', required: false),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(
                      labelText: 'Categoría profesional',
                    ),
                    items: const [
                      'DOCTOR',
                      'NURSE',
                      'PARAMEDIC',
                      'FIREFIGHTER',
                      'MEDICAL_INTERN',
                      'MEDICAL_RESIDENT',
                    ]
                        .map(
                          (val) => DropdownMenuItem(
                            value: val,
                            child: Text(
                              switch (val) {
                                'DOCTOR' => 'Médico / Doctor',
                                'NURSE' => 'Enfermería',
                                'PARAMEDIC' => 'Paramédico',
                                'FIREFIGHTER' => 'Bombero rescatista',
                                'MEDICAL_INTERN' => 'Interno de medicina',
                                'MEDICAL_RESIDENT' => 'Residente médico',
                                _ => val,
                              },
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => category = val ?? category),
                  ),
                ),
                input(
                  'professionalLicenseNumber',
                  'N.º de identificación profesional',
                  hint: '000000',
                ),
                input(
                  'specialty',
                  'Especialidad (opcional)',
                  hint: 'Ej. Medicina de emergencia',
                  required: false,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action Buttons: Guardar cambios & Cancelar (Wireframe M-07 Edit)
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF64748B),
              foregroundColor: Colors.white,
            ),
            onPressed: savingAccount || savingRole ? null : saveAll,
            child: Text(
              savingAccount || savingRole
                  ? 'Guardando...'
                  : 'Guardar cambios',
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.border, width: 1.4),
              foregroundColor: AppTheme.slate,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}
