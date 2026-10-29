import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/ai/consultation_guidance_service.dart';
import '../data/ai/gemma4_on_device_inference.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/consultation_draft.dart';
import '../domain/models/consultation_guidance.dart';
import '../domain/models/patient_draft.dart';
import '../data/device/device_location_service.dart';
import '../../medical_bases/data/index/local_medical_knowledge_repository.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ConsultationSummaryPage(draft: widget.draft, patient: patient),
      ),
    );
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
                child: const Text('Revisar consulta'),
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
    required this.patient,
    this.savedId,
    this.initialGuidance,
    this.fromHistory = false,
  });
  final ConsultationDraft draft;
  final PatientDraft patient;
  final int? savedId;
  final ConsultationGuidance? initialGuidance;
  final bool fromHistory;

  @override
  State<ConsultationSummaryPage> createState() =>
      _ConsultationSummaryPageState();
}

class _ConsultationSummaryPageState extends State<ConsultationSummaryPage> {
  ConsultationGuidance? guidance;
  int? consultationId;
  bool busy = false;
  String? saveError;

  @override
  void initState() {
    super.initState();
    consultationId = widget.savedId;
    guidance = widget.initialGuidance;
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
      consultationId ??= await consultations.saveDraft(
        widget.draft,
        widget.patient,
        ownerKey: ownerKey,
      );
      if (!mounted) return;
      final service = ConsultationGuidanceService(
        knowledge: context.read<LocalMedicalKnowledgeRepository>(),
        inference: context.read<Gemma4OnDeviceInference>(),
      );
      final result = await service.create(
        draft: widget.draft,
        patient: widget.patient,
      );
      await consultations.saveGuidance(
        consultationId!,
        result,
        ownerKey: ownerKey,
      );
      if (mounted) setState(() => guidance = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError =
              'No se pudo guardar la consulta. Vuelve a intentarlo antes de salir.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    appBar: AppBar(title: const Text('Revisar consulta')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.patient.name,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          '${widget.patient.ageYears} años${widget.patient.province == null ? '' : ' · ${widget.patient.province}'}',
        ),
        if (widget.patient.locationDescription != null)
          Text(widget.patient.locationDescription!),
        if (widget.patient.requesterPhone != null)
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Teléfono de quien solicita ayuda'),
            subtitle: Text(widget.patient.requesterPhone!),
          ),
        if (widget.patient.latitude != null && widget.patient.longitude != null)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Coordenadas GPS'),
            subtitle: Text(
              '${widget.patient.latitude!.toStringAsFixed(6)}, ${widget.patient.longitude!.toStringAsFixed(6)}',
            ),
          ),
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
        if (widget.draft.helpRequested)
          const ListTile(
            leading: Icon(Icons.medical_services_outlined),
            title: Text('Deseas solicitar apoyo profesional'),
            subtitle: Text(
              'La solicitud aún no se ha enviado a un profesional.',
            ),
          ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Antes de seguir: ¿el lugar es seguro?, ¿la persona responde?, ¿respira normalmente?, ¿hay sangrado intenso? Si falta una respuesta, vuelve y añádela a la descripción para elegir la indicación adecuada. Si la persona no puede responder o hay una señal grave, busca ayuda profesional inmediatamente. El envío a profesionales aún no está disponible en esta versión de la app.',
            ),
          ),
        ),
        if (guidance?.urgent == true)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Busca apoyo profesional inmediatamente. El envío desde la app aún no está disponible.',
              ),
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
            section('Fuentes', [
              for (final source in result.sources)
                '${source.institution}: ${source.title}\n${source.url}',
            ]),
          ],
        ] else if (consultationId != null)
          const Text(
            'Orientación pendiente. Puedes reintentarla cuando el modelo esté listo.',
          ),
        if (saveError != null) Text(saveError!),
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
        if (!widget.fromHistory)
          OutlinedButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Editar datos'),
          ),
      ],
    ),
  );
}
