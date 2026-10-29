import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    final user = context.read<AuthCubit>().state.user!;
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

  Widget row(String label, Object? value) => ListTile(
    title: Text(label),
    subtitle: SelectableText(
      value == null || '$value'.trim().isEmpty ? 'No registrado' : '$value',
    ),
  );

  String verificationLabel(Object? status) => switch (status) {
    'APPROVED' => 'Aprobado',
    'PENDING' => 'Pendiente de verificación',
    'REJECTED' => 'Rechazado',
    _ => '$status',
  };

  @override
  Widget build(BuildContext context) {
    final citizen = context.read<AuthCubit>().state.user!.isCitizen;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
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
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Column(
                      children: [
                        const ListTile(title: Text('Cuenta')),
                        row('Nombres', account!['firstName']),
                        row('Apellidos', account!['lastName']),
                        row('Correo electrónico', account!['email']),
                        row('Teléfono', account!['phone']),
                      ],
                    ),
                  ),
                  Card(
                    child: Column(
                      children: citizen
                          ? [
                              const ListTile(title: Text('Datos de ciudadano')),
                              row('Ciudad', roleProfile!['city']),
                              row('Distrito', roleProfile!['district']),
                              row('Dirección', roleProfile!['address']),
                              row(
                                'Fecha de nacimiento',
                                roleProfile!['dateOfBirth'],
                              ),
                              row(
                                'Contacto de emergencia',
                                roleProfile!['emergencyContactName'],
                              ),
                              row(
                                'Teléfono de contacto',
                                roleProfile!['emergencyContactPhone'],
                              ),
                              row(
                                'Condiciones preexistentes',
                                roleProfile!['preExistingConditions'],
                              ),
                              row('Alergias', roleProfile!['allergies']),
                            ]
                          : [
                              const ListTile(
                                title: Text('Datos profesionales'),
                              ),
                              row(
                                'Categoría',
                                roleProfile!['professionalCategory'],
                              ),
                              row(
                                'Identificación profesional',
                                roleProfile!['professionalLicenseNumber'],
                              ),
                              row('Especialidad', roleProfile!['specialty']),
                              row(
                                'Verificación',
                                verificationLabel(
                                  roleProfile!['verificationStatus'],
                                ),
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
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
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar perfil'),
                  ),
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
    bool required = true,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: fields.putIfAbsent(key, TextEditingController.new),
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: (text) => required && (text == null || text.trim().isEmpty)
          ? 'Ingresa $label'
          : null,
    ),
  );

  void notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

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
      if (mounted) notice('Datos de cuenta actualizados.');
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
    final oldLicense =
        '${widget.initialRoleProfile['professionalLicenseNumber']}'
            .trim()
            .toUpperCase();
    final licenseChanged =
        !widget.citizen &&
        oldLicense != value('professionalLicenseNumber').toUpperCase();
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
      notice(
        licenseChanged
            ? 'Datos profesionales actualizados. La identificación cambió; revisa el estado de verificación.'
            : 'Datos del perfil actualizados.',
      );
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
    appBar: AppBar(title: const Text('Editar perfil')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Form(
          key: accountForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cuenta', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              input('firstName', 'Nombres'),
              input('lastName', 'Apellidos'),
              input(
                'phone',
                'Teléfono',
                required: false,
                keyboard: TextInputType.phone,
              ),
              FilledButton(
                onPressed: savingAccount || savingRole ? null : saveAccount,
                child: Text(savingAccount ? 'Guardando...' : 'Guardar cuenta'),
              ),
            ],
          ),
        ),
        const Divider(height: 40),
        Form(
          key: roleForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.citizen ? 'Datos de ciudadano' : 'Datos profesionales',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (widget.citizen) ...[
                input('city', 'Ciudad'),
                input('district', 'Distrito'),
                input('address', 'Dirección'),
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
                input(
                  'preExistingConditions',
                  'Condiciones preexistentes',
                  required: false,
                ),
                input('allergies', 'Alergias', required: false),
              ] else ...[
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
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                  onChanged: (item) =>
                      setState(() => category = item ?? category),
                ),
                const SizedBox(height: 12),
                input(
                  'professionalLicenseNumber',
                  'Identificación profesional',
                ),
                input('specialty', 'Especialidad', required: false),
                const Text(
                  'Si cambias la identificación profesional, tu habilitación volverá a evaluarse.',
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: savingAccount || savingRole ? null : saveRole,
                child: Text(
                  savingRole ? 'Guardando...' : 'Guardar datos del perfil',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
