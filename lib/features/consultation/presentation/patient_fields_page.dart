import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/presentation/system_status_bar.dart';
import '../../../core/presentation/wireframe_components.dart';
import '../../../core/theme/app_theme.dart';
import '../application/consultation_sync_service.dart';
import '../data/ai/consultation_guidance_service.dart';
import '../data/ai/gemma4_on_device_inference.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/consultation_draft.dart';
import '../domain/models/saved_consultation.dart';
import '../domain/models/consultation_guidance.dart';
import '../domain/models/patient_draft.dart';
import '../data/device/device_location_service.dart';
import '../../medical_bases/data/index/local_medical_knowledge_repository.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/blocs/auth_state.dart';
import '../../cases/data/case_api_service.dart';
import '../../cases/presentation/cases_page.dart' show caseStatusLabel;
import '../../notifications/application/delivery_confirmation_notices.dart';
import '../../notifications/application/publish_notification_token.dart';
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
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Datos del paciente'),
      bottom: const SystemStatusBar(mode: SystemStatusMode.offline),
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // Subtitle (Wireframe C-02)
                  const Text(
                    'Estos datos ayudan al personal médico a atender el caso.',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      color: AppTheme.slateMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Nombre del paciente
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del paciente',
                      hintText: 'Ej. Juan Pérez',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Ingresa el nombre'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  // Row: Edad (años) y Provincia (Wireframe C-02)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: age,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Edad (años)',
                            hintText: 'Ej. 34',
                          ),
                          validator: (value) {
                            final number = int.tryParse(value ?? '');
                            return number == null || number < 0 || number > 120
                                ? 'Edad inválida'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: province,
                          decoration: const InputDecoration(
                            labelText: 'Provincia',
                            hintText: 'Ej. Lima',
                            suffixIcon: Icon(Icons.keyboard_arrow_down, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Referencia de ubicación
                  TextFormField(
                    controller: location,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Referencia de ubicación',
                      hintText: 'Ej. Frente al parque, 2.° piso',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Teléfono de quien solicita ayuda
                  TextFormField(
                    controller: requesterPhone,
                    keyboardType: TextInputType.phone,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono de quien solicita ayuda',
                      hintText: '999 999 999',
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
                  const SizedBox(height: 8),

                  // Ubicación del paciente (Map preview - Wireframe C-02)
                  const Text(
                    'Ubicación del paciente',
                    style: TextStyle(
                      fontFamily: AppTheme.fontHeading,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.slate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MapPreviewCard(
                    height: 130,
                    coordinatesText: locating
                        ? 'Obteniendo coordenadas GPS...'
                        : coordinates != null
                        ? '${coordinates!.latitude.toStringAsFixed(6)}, ${coordinates!.longitude.toStringAsFixed(6)} · precisión ${coordinates!.accuracyMeters.round()}m'
                        : locationError ?? 'Coordenadas capturadas por GPS',
                    onTap: captureLocation,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Button: Guardar y continuar (Wireframe C-02)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF64748B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: preview,
                  child: const Text('Guardar y continuar'),
                ),
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
    if (busy) return;
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

  Future<void> confirmProfessionalHelpModal() async {
    // Show Wireframe C-06 Modal Bottom Sheet
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '¿Solicitar apoyo profesional?',
              style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.slate,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tu consulta, los datos del paciente y la ubicación se enviarán al personal médico apenas haya conexión.',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                color: AppTheme.slateMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            // Primary Red CTA (Wireframe C-06)
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.emergency,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Sí, solicitar apoyo'),
              ),
            ),
            const SizedBox(height: 12),
            // Cancel Button
            SizedBox(
              height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border, width: 1.4),
                  foregroundColor: AppTheme.slate,
                ),
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => helpRequested = true);
      if (patient == null) {
        await continueToPatient();
      } else {
        await saveConsultation();
      }
    }
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
      if (consultationId == null) {
        consultationId = await consultations.saveCompleteConsultation(
          draft: widget.draft.withHelpRequested(helpRequested),
          patient: patient,
          guidance: guidance!,
          ownerKey: ownerKey,
        );
      } else {
        await consultations.saveGuidance(
          consultationId!,
          guidance!,
          ownerKey: ownerKey,
        );
      }
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
    SavedConsultation? beforeRow;
    var knowBefore = false;
    if (consultationId != null) {
      try {
        beforeRow = await consultations.get(
          consultationId!,
          ownerKey: ownerKey,
        );
        knowBefore = true;
      } catch (_) {}
    }
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
    if (!mounted || row == null) return;
    final notices = _provided<DeliveryConfirmationNotices>(context);
    if (knowBefore && notices != null) {
      await notices.announce([?beforeRow], [row]);
    }
    if (!mounted) return;
    await publishNotificationToken(context, auth: auth, consultations: [row]);
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
    if (syncStatus != 'pending') return null;
    return 'Envío pendiente. Se reintentará con la misma consulta.';
  }

  String priorityLabel(PreliminaryPriority? priority) => switch (priority) {
    PreliminaryPriority.high => 'Alta',
    PreliminaryPriority.medium => 'Media',
    PreliminaryPriority.low => 'Baja',
    null => 'Pendiente',
  };

  @override
  Widget build(BuildContext context) {
    // 1. Screen C-03: Processing in device view
    if (busy && guidance == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Procesando consulta'),
          bottom: const SystemStatusBar(mode: SystemStatusMode.offline),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                // Large circular progress ring
                const SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    strokeWidth: 6,
                    color: AppTheme.teal,
                    backgroundColor: Color(0xFFE2E8F0),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Analizando tu consulta',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Todo ocurre en tu dispositivo. No necesitas internet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.slateMuted,
                  ),
                ),
                const SizedBox(height: 40),
                // Stepper checklist (Wireframe C-03)
                _buildProcessingStep(
                  done: true,
                  active: false,
                  label: 'Consulta recibida',
                ),
                const SizedBox(height: 16),
                _buildProcessingStep(
                  done: false,
                  active: true,
                  label: 'Buscando en la base médica local',
                ),
                const SizedBox(height: 16),
                _buildProcessingStep(
                  done: false,
                  active: false,
                  label: 'Generando indicaciones',
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
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
              ],
            ),
          ),
        ),
      );
    }

    // 2. Screen C-05: Safe Response when insufficient info
    if (guidance != null && !guidance!.isReady) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Orientación médica'),
          bottom: const SystemStatusBar(mode: SystemStatusMode.offline),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            children: [
              const SizedBox(height: 16),
              const Center(
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 72,
                  color: AppTheme.amber,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No hay información suficiente',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'No podemos darte una orientación confiable para esta situación. Para evitar acciones inseguras, no generaremos instrucciones.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  color: AppTheme.slateMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              // Highlight Card (Wireframe C-05)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Text(
                  'Agrega más detalles: qué ocurrió, dónde está la herida y si la persona responde.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.slate,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              // Primary Button: Editar consulta
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF64748B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Editar consulta'),
                ),
              ),
              const SizedBox(height: 12),
              // Emergency CTA: Solicitar apoyo profesional
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.emergency, width: 1.4),
                    foregroundColor: AppTheme.emergency,
                  ),
                  onPressed: confirmProfessionalHelpModal,
                  child: const Text('Solicitar apoyo profesional'),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Si hay signos graves, busca ayuda profesional de inmediato.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Screen C-04: Orientación médica
    final result = guidance;
    final allSteps = <String>[
      if (result != null) ...result.measures,
      if (result != null) ...result.medicalIndications,
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(saved ? 'Revisar consulta' : 'Orientación médica'),
        bottom: const SystemStatusBar(mode: SystemStatusMode.offline),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // Priority Pill Chip (Wireframe C-04)
                  if (result != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PriorityBadge(
                        label: 'Prioridad preliminar: ${priorityLabel(result.preliminaryPriority)}',
                        priorityLevel: result.preliminaryPriority?.name,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Severity warning banner (Wireframe C-04)
                  if (result?.urgent == true ||
                      result?.preliminaryPriority == PreliminaryPriority.high) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.redSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppTheme.emergency, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Señales de gravedad detectadas',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontHeading,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.emergency,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Busca atención profesional de inmediato.',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 12.5,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Sequential Numbered Steps (Checklist Cards - Wireframe C-04)
                  if (allSteps.isNotEmpty)
                    for (var i = 0; i < allSteps.length; i++)
                      StepCard(
                        number: i + 1,
                        title: _extractStepTitle(allSteps[i]),
                        description: _extractStepDescription(allSteps[i]),
                      )
                  else if (result != null && result.message.isNotEmpty)
                    StepCard(
                      number: 1,
                      title: 'Orientación',
                      description: result.message,
                    ),

                  const SizedBox(height: 12),

                  // Fuentes médicas utilizadas (Wireframe C-04)
                  if (result != null && result.sources.isNotEmpty) ...[
                    const Text(
                      'Fuentes médicas utilizadas',
                      style: TextStyle(
                        fontFamily: AppTheme.fontHeading,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final source in result.sources)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.border, width: 1.2),
                            ),
                            child: Text(
                              source.institution.isNotEmpty
                                  ? source.institution
                                  : source.title,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Disclaimer text (Wireframe C-04)
                  const Text(
                    'Orientación preliminar. No reemplaza la evaluación de un profesional de la salud.',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                      height: 1.4,
                    ),
                  ),

                  // Patient info and delivery status if saved or present
                  if (patient case final currentPatient?) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paciente: ${currentPatient.name} · ${currentPatient.ageYears} años',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontHeading,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (currentPatient.province != null)
                            Text('Provincia: ${currentPatient.province}'),
                          if (currentPatient.locationDescription != null)
                            Text('Ubicación: ${currentPatient.locationDescription}'),
                        ],
                      ),
                    ),
                  ],

                  if (deliveryTitle() case final title?) ...[
                    const SizedBox(height: 12),
                    StatusPill(
                      label: title,
                      isUrgent: helpRequested && syncStatus == 'pending',
                    ),
                  ],

                  if (saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        saveError!,
                        style: const TextStyle(color: AppTheme.emergency),
                      ),
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Bottom Buttons (Wireframe C-04)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Emergency CTA: Solicitar apoyo profesional
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF94A3B8),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: busy ? null : confirmProfessionalHelpModal,
                      child: const Text('Solicitar apoyo profesional'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Secondary Button: Guardar consulta
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.slate, width: 1.4),
                        foregroundColor: AppTheme.slate,
                      ),
                      onPressed: busy
                          ? null
                          : saved
                          ? () => Navigator.pop(context)
                          : saveConsultation,
                      child: Text(saved ? 'Volver' : 'Guardar consulta'),
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

  Widget _buildProcessingStep({
    required bool done,
    required bool active,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppTheme.teal
                : active
                ? Colors.transparent
                : Colors.transparent,
            border: Border.all(
              color: done
                  ? AppTheme.teal
                  : active
                  ? AppTheme.teal
                  : AppTheme.border,
              width: 2,
            ),
          ),
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : active
              ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.teal,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 14),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontHeading,
            fontSize: 14,
            fontWeight: active || done ? FontWeight.w700 : FontWeight.w500,
            color: active || done ? AppTheme.slate : AppTheme.slateMuted,
          ),
        ),
      ],
    );
  }

  String _extractStepTitle(String text) {
    if (text.contains(':')) {
      return text.split(':').first.trim();
    }
    if (text.contains('.')) {
      final first = text.split('.').first.trim();
      if (first.length < 50) return first;
    }
    return text.length > 40 ? '${text.substring(0, 37)}...' : text;
  }

  String _extractStepDescription(String text) {
    if (text.contains(':')) {
      final parts = text.split(':');
      if (parts.length > 1) return parts.sublist(1).join(':').trim();
    }
    if (text.contains('.')) {
      final parts = text.split('.');
      if (parts.length > 1 && parts[0].length < 50) {
        return parts.sublist(1).join('.').trim();
      }
    }
    return text;
  }
}

T? _provided<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
