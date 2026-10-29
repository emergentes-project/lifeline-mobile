import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../application/consultation_sync_service.dart';
import '../data/ai/consultation_guidance_service.dart';
import '../data/ai/gemma4_on_device_inference.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/consultation_draft.dart';
import '../domain/models/consultation_guidance.dart';
import '../domain/models/patient_draft.dart';
import '../data/device/device_location_service.dart';
import '../../medical_bases/data/index/local_medical_knowledge_repository.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/blocs/auth_state.dart';
import '../../cases/data/case_api_service.dart';
import '../../cases/presentation/cases_page.dart' show caseStatusLabel;
import '../application/consultation_owner.dart';

class PatientFieldsPage extends StatefulWidget {
  const PatientFieldsPage({super.key, required this.draft});
  final ConsultationDraft draft;
  @override
  State<PatientFieldsPage> createState() => _PatientFieldsPageState();
}

class _PatientFieldsPageState extends State<PatientFieldsPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final age = TextEditingController();
  final province = TextEditingController();
  final location = TextEditingController();
  final requesterPhone = TextEditingController();
  final deviceLocation = DeviceLocationService();
  DeviceLocation? coordinates;
  String? locationError;
  bool locating = false;

  @override
  void initState() {
    super.initState();
    requesterPhone.text = context.read<AuthCubit>().state.user?.phone ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => captureLocation());
  }

  Future<void> captureLocation() async {
    if (locating) return;
    setState(() {
      locating = true;
      locationError = null;
    });
    try {
      final result = await deviceLocation.capture();
      if (!mounted) return;
      setState(() => coordinates = result);
    } on DeviceLocationException catch (error) {
      if (!mounted) return;
      setState(() {
        coordinates = null;
        locationError = error.message;
      });
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    age.dispose();
    province.dispose();
    location.dispose();
    requesterPhone.dispose();
    super.dispose();
  }

  void preview() {
    if (!form.currentState!.validate()) return;
    final patient = PatientDraft(
      name: name.text.trim(),
      ageYears: int.parse(age.text),
      province: province.text.trim().isEmpty ? null : province.text.trim(),
      locationDescription: location.text.trim().isEmpty
          ? null
          : location.text.trim(),
      latitude: coordinates?.latitude,
      longitude: coordinates?.longitude,
      requesterPhone: requesterPhone.text.trim().isEmpty
          ? null
          : requesterPhone.text.trim(),
    );
    Navigator.pop(context, patient);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Datos del paciente')),
    body: SafeArea(
      child: Form(
        key: form,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Estos datos ayudan al personal médico a atender el caso.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del paciente',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Ingresa el nombre'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Edad (años)'),
                    validator: (value) {
                      final number = int.tryParse(value ?? '');
                      return number == null || number < 0 || number > 120
                          ? 'Ingresa una edad válida'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: requesterPhone,
                    keyboardType: TextInputType.phone,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono de quien solicita ayuda',
                      helperText:
                          'El personal médico podrá verlo para contactarte.',
                    ),
                    validator: (value) {
                      final phone = value?.trim() ?? '';
                      if (widget.draft.helpRequested && phone.isEmpty) {
                        return 'Ingresa un teléfono de contacto';
                      }
                      if (phone.isNotEmpty &&
                          !RegExp(r'^\+?[0-9 ()-]{6,30}$').hasMatch(phone)) {
                        return 'Ingresa un teléfono válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: province,
                    decoration: const InputDecoration(
                      labelText: 'Provincia (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: location,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Referencia de ubicación (opcional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        coordinates == null
                            ? Icons.location_searching
                            : Icons.location_on_outlined,
                      ),
                      title: Text(
                        locating
                            ? 'Obteniendo ubicación...'
                            : coordinates == null
                            ? 'Ubicación no disponible'
                            : 'Ubicación registrada',
                      ),
                      subtitle: Text(
                        coordinates == null
                            ? (locationError ??
                                  'Puedes continuar con una referencia escrita.')
                            : '${coordinates!.latitude.toStringAsFixed(6)}, ${coordinates!.longitude.toStringAsFixed(6)} · precisión aproximada ${coordinates!.accuracyMeters.round()} m',
                      ),
                      trailing: locating
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Reintentar ubicación',
                              onPressed: captureLocation,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton(
                onPressed: preview,
                child: const Text('Guardar consulta'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ConsultationSummaryPage extends StatefulWidget {
  const ConsultationSummaryPage({
    super.key,
    required this.draft,
    this.patient,
    this.savedId,
    this.initialGuidance,
    this.fromHistory = false,
    this.initialSyncStatus = 'pending',
    this.initialBackendConsultationId,
  });
  final ConsultationDraft draft;
  final PatientDraft? patient;
  final int? savedId;
  final ConsultationGuidance? initialGuidance;
  final bool fromHistory;
  final String initialSyncStatus;
  final String? initialBackendConsultationId;

  @override
  State<ConsultationSummaryPage> createState() =>
      _ConsultationSummaryPageState();
}

class _ConsultationSummaryPageState extends State<ConsultationSummaryPage> {
  ConsultationGuidance? guidance;
  PatientDraft? patient;
  int? consultationId;
  bool saved = false;
  late bool helpRequested;
  bool busy = false;
  String? saveError;
  late String syncStatus;
  String? backendConsultationId;
  String? deliveryError;
  String? remoteCaseLabel;

  @override
  void initState() {
    super.initState();
    consultationId = widget.savedId;
    saved = consultationId != null;
    guidance = widget.initialGuidance;
    patient = widget.patient;
    helpRequested = widget.draft.helpRequested;
    syncStatus = widget.initialSyncStatus;
    backendConsultationId = widget.initialBackendConsultationId;
    if (consultationId == null && guidance == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) generateGuidance();
      });
    } else if (saved && helpRequested && syncStatus == 'confirmed') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadRemoteCase();
      });
    }
  }

  Future<void> generateGuidance() async {
    if (busy) return;
    setState(() {
      busy = true;
      saveError = null;
    });
    try {
      final consultations = context.read<LocalConsultationRepository>();
      final ownerKey = consultationOwnerKey(context.read<AuthCubit>().state);
      final service = ConsultationGuidanceService(
        knowledge: context.read<LocalMedicalKnowledgeRepository>(),
        inference: context.read<Gemma4OnDeviceInference>(),
      );
      final result = await service.create(
        draft: widget.draft,
        patient: patient,
      );
      if (consultationId != null) {
        await consultations.saveGuidance(
          consultationId!,
          result,
          ownerKey: ownerKey,
        );
      }
      if (mounted) setState(() => guidance = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError =
              'No se pudo obtener o guardar la orientación. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> continueToPatient() async {
    if (guidance?.isReady != true || busy || !helpRequested) return;
    final selected = await Navigator.push<PatientDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => PatientFieldsPage(
          draft: widget.draft.withHelpRequested(helpRequested),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => patient = selected);
    await saveConsultation();
  }

  Future<void> saveConsultation() async {
    if (busy ||
        (helpRequested && patient == null) ||
        guidance?.isReady != true) {
      return;
    }
    setState(() {
      busy = true;
      saveError = null;
    });
    try {
      final consultations = context.read<LocalConsultationRepository>();
      final ownerKey = consultationOwnerKey(context.read<AuthCubit>().state);
      consultationId ??= await consultations.saveDraft(
        widget.draft.withHelpRequested(helpRequested),
        patient,
        ownerKey: ownerKey,
      );
      await consultations.saveGuidance(
        consultationId!,
        guidance!,
        ownerKey: ownerKey,
      );
      if (!mounted) return;
      await deliver(consultations, ownerKey);
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError = 'No se pudo guardar la consulta. Reinténtalo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deliver(
    LocalConsultationRepository consultations,
    String ownerKey,
  ) async {
    final auth = context.read<AuthCubit>().state;
    final sync = _provided<ConsultationSyncService>(context);
    ConsultationSyncAttempt? attempt;
    if (sync != null && consultationId != null) {
      try {
        final outcomes = await sync.syncPending(
          ownerKey: ownerKey,
          citizenUserId: auth.status == AuthStatus.authenticated
              ? auth.user?.id
              : null,
        );
        attempt = outcomes
            .where((item) => item.localId == consultationId)
            .firstOrNull;
      } catch (_) {
        attempt = null;
      }
    }
    if (!mounted || consultationId == null) return;
    final row = await consultations.get(consultationId!, ownerKey: ownerKey);
    if (!mounted) return;
    final label =
        row?.syncStatus == 'confirmed' &&
            helpRequested &&
            row?.backendConsultationId != null
        ? await lookupCaseLabel(row!.backendConsultationId!)
        : null;
    if (!mounted) return;
    setState(() {
      saved = true;
      if (row != null) {
        syncStatus = row.syncStatus;
        backendConsultationId = row.backendConsultationId;
      }
      deliveryError = attempt?.errorMessage;
      remoteCaseLabel = label;
    });
  }

  Future<void> loadRemoteCase() async {
    final backendId = backendConsultationId;
    if (!helpRequested || syncStatus != 'confirmed' || backendId == null) {
      return;
    }
    final label = await lookupCaseLabel(backendId);
    if (!mounted || label == null) return;
    setState(() => remoteCaseLabel = label);
  }

  Future<String?> lookupCaseLabel(String backendId) async {
    final auth = context.read<AuthCubit>().state;
    if (auth.status != AuthStatus.authenticated ||
        auth.user?.isCitizen != true) {
      return null;
    }
    final token = auth.user!.token;
    final api = _provided<CaseApiService>(context);
    if (api == null) return null;
    try {
      final cases = await api.listForCitizen(token);
      for (final item in cases) {
        if (item.consultationId == backendId) {
          return caseStatusLabel(item.status);
        }
      }
    } catch (_) {}
    return null;
  }

  String? deliveryTitle() {
    if (!saved || !helpRequested) return null;
    if (syncStatus == 'confirmed') {
      return remoteCaseLabel ?? 'Envío confirmado.';
    }
    return 'Envío pendiente. Se reintentará con la misma consulta.';
  }

  Widget section(String title, List<String> items, {String? lead}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (lead != null)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(lead)),
      for (var index = 0; index < items.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SelectableText('${index + 1}. ${items[index]}'),
        ),
    ],
  );

  String priorityLabel(PreliminaryPriority? priority) => switch (priority) {
    PreliminaryPriority.high => 'Alta: atención inmediata',
    PreliminaryPriority.medium => 'Media: valoración pronta',
    PreliminaryPriority.low => 'Baja: puede esperar',
    null => 'Pendiente por información insuficiente',
  };

  String helpLabel(bool? recommended) => switch (recommended) {
    true => 'Sí, solicita ayuda profesional.',
    false =>
      'No parece necesaria de inmediato con los datos actuales. Vigila las condiciones indicadas abajo.',
    null =>
      'No se puede determinar con los datos disponibles. Busca valoración profesional si hay dudas o empeora.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(saved ? 'Revisar consulta' : 'Orientación de la consulta'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (patient case final currentPatient?) ...[
          Text(
            currentPatient.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '${currentPatient.ageYears} años${currentPatient.province == null ? '' : ' · ${currentPatient.province}'}',
          ),
          if (currentPatient.locationDescription != null)
            Text(currentPatient.locationDescription!),
          if (currentPatient.requesterPhone != null)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('Teléfono de quien solicita ayuda'),
              subtitle: Text(currentPatient.requesterPhone!),
            ),
          if (currentPatient.latitude != null &&
              currentPatient.longitude != null)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Coordenadas GPS'),
              subtitle: Text(
                '${currentPatient.latitude!.toStringAsFixed(6)}, ${currentPatient.longitude!.toStringAsFixed(6)}',
              ),
            ),
        ],
        const SizedBox(height: 20),
        if (widget.draft.description.trim().isNotEmpty)
          Text(widget.draft.description),
        if (widget.draft.audioPath != null)
          const ListTile(
            leading: Icon(Icons.mic),
            title: Text('Audio adjunto'),
            subtitle: Text(
              'La descripción transcrita puede revisarse antes de continuar.',
            ),
          ),
        if (widget.draft.photoPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Image.file(
              File(widget.draft.photoPath!),
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Text(
                'La foto adjunta ya no está disponible en este dispositivo.',
              ),
            ),
          ),
        if (widget.draft.photoPath != null)
          const Text(
            'Gemma analizará señales visibles de la foto junto con tu descripción. No usará la imagen para inferir un diagnóstico, la respiración ni el estado de conciencia.',
          ),
        if (deliveryTitle() case final title?)
          ListTile(
            leading: Icon(
              syncStatus == 'confirmed'
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_upload_outlined,
            ),
            title: Text(title),
            subtitle: deliveryError == null ? null : Text(deliveryError!),
          ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Antes de seguir: ¿el lugar es seguro?, ¿la persona responde?, ¿respira normalmente?, ¿hay sangrado intenso? Si falta una respuesta, vuelve y añádela a la descripción para elegir la indicación adecuada. Si la persona no puede responder o hay una señal grave, busca ayuda profesional inmediatamente.',
            ),
          ),
        ),
        if (guidance?.urgent == true)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Busca apoyo profesional inmediatamente.'),
            ),
          ),
        if (guidance case final result?) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.priority_high),
              title: const Text('Prioridad preliminar'),
              subtitle: Text(
                '${priorityLabel(result.preliminaryPriority)}\n'
                '${result.priorityReason ?? 'Completa los datos o solicita valoración profesional.'}',
              ),
            ),
          ),
          Text(result.message),
          if (result.isReady) ...[
            section('1. Medidas a tomar', result.measures),
            section(
              '2. Indicaciones médicas a ejecutar',
              result.medicalIndications,
            ),
            section(
              '3. ¿Es necesario pedir ayuda profesional?',
              result.professionalHelp,
              lead: helpLabel(result.professionalHelpRecommended),
            ),
          ],
          if (result.isReady && !saved && patient == null) ...[
            const SizedBox(height: 20),
            Text(
              '¿Deseas solicitar apoyo profesional?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(helpLabel(result.professionalHelpRecommended)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Solicitar apoyo profesional'),
              subtitle: const Text('Decide después de leer la orientación.'),
              value: helpRequested,
              onChanged: busy
                  ? null
                  : (value) => setState(() => helpRequested = value),
            ),
          ],
          if (result.isReady)
            section('Fuentes', [
              for (final source in result.sources)
                '${source.institution}: ${source.title}\n${source.url}',
            ]),
        ] else if (consultationId != null)
          const Text(
            'Orientación pendiente. Puedes reintentarla cuando el modelo esté listo.',
          ),
        if (saveError != null) Text(saveError!),
        if (deliveryError != null && !helpRequested) Text(deliveryError!),
        const SizedBox(height: 16),
        if (guidance == null || !guidance!.isReady)
          FilledButton(
            onPressed: busy ? null : generateGuidance,
            child: Text(
              busy
                  ? 'Preparando orientación local...'
                  : consultationId == null
                  ? 'Guardar y obtener orientación'
                  : 'Reintentar orientación',
            ),
          ),
        if (busy) const Center(child: CircularProgressIndicator()),
        if (!saved && guidance?.isReady == true)
          FilledButton(
            onPressed: busy
                ? null
                : helpRequested && patient == null
                ? continueToPatient
                : saveConsultation,
            child: Text(
              helpRequested && patient == null
                  ? 'Continuar con datos del paciente'
                  : patient == null
                  ? 'Guardar consulta'
                  : 'Reintentar guardado',
            ),
          ),
        if (saved && !widget.fromHistory)
          const Text('Consulta guardada en este dispositivo.'),
        if (!widget.fromHistory && !saved)
          OutlinedButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Editar descripción'),
          ),
      ],
    ),
  );
}

T? _provided<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
