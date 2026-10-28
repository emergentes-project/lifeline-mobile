import 'dart:io';
import 'package:flutter/material.dart';
import '../domain/models/consultation_draft.dart';
import '../domain/models/patient_draft.dart';
import '../data/device/device_location_service.dart';

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
  final deviceLocation = DeviceLocationService();
  DeviceLocation? coordinates;
  String? locationError;
  bool locating = false;

  @override
  void initState() {
    super.initState();
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

class ConsultationSummaryPage extends StatelessWidget {
  const ConsultationSummaryPage({
    super.key,
    required this.draft,
    required this.patient,
  });
  final ConsultationDraft draft;
  final PatientDraft patient;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Revisar consulta')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(patient.name, style: Theme.of(context).textTheme.titleLarge),
        Text(
          '${patient.ageYears} años${patient.province == null ? '' : ' · ${patient.province}'}',
        ),
        if (patient.locationDescription != null)
          Text(patient.locationDescription!),
        if (patient.latitude != null && patient.longitude != null)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Coordenadas GPS'),
            subtitle: Text(
              '${patient.latitude!.toStringAsFixed(6)}, ${patient.longitude!.toStringAsFixed(6)}',
            ),
          ),
        const SizedBox(height: 20),
        if (draft.description.trim().isNotEmpty) Text(draft.description),
        if (draft.audioPath != null)
          const ListTile(
            leading: Icon(Icons.mic),
            title: Text('Audio adjunto'),
            subtitle: Text('Transcripción pendiente'),
          ),
        if (draft.photoPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Image.file(
              File(draft.photoPath!),
              height: 220,
              fit: BoxFit.cover,
            ),
          ),
        if (draft.helpRequested)
          const ListTile(
            leading: Icon(Icons.medical_services_outlined),
            title: Text('Solicitar apoyo profesional'),
          ),
        const SizedBox(height: 16),
        const Text(
          'La consulta todavía no se ha guardado ni enviado. En la siguiente etapa integraremos el almacenamiento local y la orientación médica.',
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Editar datos'),
        ),
      ],
    ),
  );
}
