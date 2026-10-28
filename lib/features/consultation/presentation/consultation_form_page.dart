import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import '../data/local/private_media_store.dart';
import '../domain/models/consultation_draft.dart';
import 'patient_fields_page.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';

class ConsultationFormPage extends StatefulWidget {
  const ConsultationFormPage({super.key, required this.guest});
  final bool guest;
  @override
  State<ConsultationFormPage> createState() => _ConsultationFormPageState();
}

class _ConsultationFormPageState extends State<ConsultationFormPage> {
  final description = TextEditingController();
  final recorder = AudioRecorder();
  final media = PrivateMediaStore();
  String? photoPath;
  String? audioPath;
  bool recording = false;
  bool helpRequested = false;
  bool busy = false;

  @override
  void dispose() {
    description.dispose();
    recorder.dispose();
    super.dispose();
  }

  void message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  Future<void> pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;
      final path = await media.retainPhoto(picked.path);
      if (!mounted) return;
      setState(() => photoPath = path);
    } catch (_) {
      if (mounted) message('No se pudo adjuntar la foto. Revisa los permisos.');
    }
  }

  Future<void> toggleRecording() async {
    try {
      if (recording) {
        final path = await recorder.stop();
        if (!mounted) return;
        setState(() {
          recording = false;
          audioPath = path;
        });
        return;
      }
      if (!await recorder.hasPermission()) {
        if (mounted) {
          message('Permite usar el micrófono para grabar tu descripción.');
        }
        return;
      }
      final path = await media.newAudioPath();
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (mounted) setState(() => recording = true);
    } catch (_) {
      if (mounted) {
        setState(() => recording = false);
        message('No se pudo grabar el audio.');
      }
    }
  }

  void continueToPatient() {
    final draft = ConsultationDraft(
      description: description.text,
      helpRequested: helpRequested,
      photoPath: photoPath,
      audioPath: audioPath,
    );
    if (recording) {
      message('Detén la grabación antes de continuar.');
      return;
    }
    if (!draft.hasInput) {
      message('Describe la situación, graba audio o adjunta una foto.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatientFieldsPage(draft: draft)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Nueva consulta'),
      actions: [
        TextButton(
          onPressed: () => widget.guest
              ? context.read<AuthCubit>().leaveGuest()
              : context.read<AuthCubit>().signOut(),
          child: Text(
            widget.guest ? 'Salir' : 'Cerrar sesión',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Cuéntanos qué pasó',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: 'Describe la situación del paciente...',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : toggleRecording,
                        icon: Icon(recording ? Icons.stop : Icons.mic),
                        label: Text(recording ? 'Detener' : 'Grabar voz'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Tomar foto'),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Elegir de galería'),
                ),
                if (audioPath != null)
                  ListTile(
                    leading: const Icon(Icons.audio_file),
                    title: const Text('Audio grabado'),
                    subtitle: const Text(
                      'Se transcribirá en la siguiente etapa',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => audioPath = null),
                    ),
                  ),
                if (photoPath != null)
                  Card(
                    child: Column(
                      children: [
                        Image.file(
                          File(photoPath!),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() => photoPath = null),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Quitar foto'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Necesito apoyo profesional'),
                  subtitle: const Text(
                    'La solicitud se enviará cuando haya conexión.',
                  ),
                  value: helpRequested,
                  onChanged: (value) => setState(() => helpRequested = value),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La orientación médica con IA estará disponible al integrar la base de conocimientos.',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton(
              onPressed: continueToPatient,
              child: const Text('Continuar con datos del paciente'),
            ),
          ),
        ],
      ),
    ),
  );
}
