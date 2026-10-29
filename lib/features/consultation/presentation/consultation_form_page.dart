import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import '../data/ai/offline_audio_transcriber.dart';
import '../data/local/private_media_store.dart';
import '../domain/models/consultation_draft.dart';
import 'patient_fields_page.dart';
import 'consultation_history_page.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/profile_page.dart';

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
  final transcriber = OfflineAudioTranscriber();
  String? photoPath;
  String? audioPath;
  bool recording = false;
  bool helpRequested = false;
  bool busy = false;
  String? transcription;
  bool noVoiceDetected = false;
  TriageAnswer responds = TriageAnswer.unknown;
  TriageAnswer breathesNormally = TriageAnswer.unknown;
  TriageAnswer heavyBleeding = TriageAnswer.unknown;

  Widget triageQuestion(
    String label,
    TriageAnswer value,
    ValueChanged<TriageAnswer> onChanged,
  ) => DropdownButtonFormField<TriageAnswer>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: const [
      DropdownMenuItem(value: TriageAnswer.unknown, child: Text('No sé')),
      DropdownMenuItem(value: TriageAnswer.yes, child: Text('Sí')),
      DropdownMenuItem(value: TriageAnswer.no, child: Text('No')),
    ],
    onChanged: (answer) {
      if (answer != null) setState(() => onChanged(answer));
    },
  );

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
    if (busy) return;
    try {
      if (recording) {
        setState(() => busy = true);
        final path = await recorder.stop();
        if (!mounted) return;
        setState(() {
          recording = false;
          audioPath = path;
          busy = false;
        });
        if (path == null) {
          message('No se guardó el audio. Intenta grabar de nuevo.');
        } else {
          await transcribeAudio(path);
        }
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
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (mounted) {
        setState(() {
          recording = true;
          audioPath = null;
          transcription = null;
          noVoiceDetected = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          recording = false;
          busy = false;
        });
        message('No se pudo grabar el audio.');
      }
    }
  }

  Future<void> transcribeAudio(String path) async {
    if (busy || recording) return;
    setState(() => busy = true);
    try {
      final text = await transcriber.transcribe(path);
      if (!mounted) return;
      if (text.isEmpty) {
        setState(() {
          transcription = null;
          noVoiceDetected = true;
        });
        message(
          'No se detectó voz. Puedes escribir la descripción o grabar de nuevo.',
        );
        return;
      }
      final current = description.text.trim();
      final withoutPrevious =
          transcription != null && current.endsWith(transcription!)
          ? current.substring(0, current.length - transcription!.length).trim()
          : current;
      description.text = withoutPrevious.isEmpty
          ? text
          : '$withoutPrevious\n$text';
      setState(() {
        transcription = text;
        noVoiceDetected = false;
      });
      message('Audio transcrito. Revisa y corrige el texto si es necesario.');
    } catch (_) {
      if (mounted) {
        setState(() => noVoiceDetected = false);
        message(
          'No se pudo transcribir. Puedes volver a intentarlo o escribir la descripción.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void continueToPatient() {
    final draft = ConsultationDraft(
      description: description.text,
      helpRequested: helpRequested,
      photoPath: photoPath,
      audioPath: audioPath,
      responds: responds,
      breathesNormally: breathesNormally,
      heavyBleeding: heavyBleeding,
    );
    if (recording || busy) {
      message('Espera a que termine la grabación y transcripción.');
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
        if (!widget.guest)
          IconButton(
            tooltip: 'Mi perfil',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
        IconButton(
          tooltip: 'Consultas guardadas',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ConsultationHistoryPage()),
          ),
        ),
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
                    subtitle: Text(
                      busy
                          ? 'Transcribiendo sin internet...'
                          : noVoiceDetected
                          ? 'No se detectó voz; toca para reintentar'
                          : transcription == null
                          ? 'Toca para intentar transcribir de nuevo'
                          : 'Texto agregado a la descripción',
                    ),
                    onTap: busy || recording
                        ? null
                        : () => transcribeAudio(audioPath!),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: busy || recording
                          ? null
                          : () => setState(() {
                              audioPath = null;
                              transcription = null;
                              noVoiceDetected = false;
                            }),
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
                const SizedBox(height: 16),
                Text(
                  'Comprobaciones iniciales',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                triageQuestion(
                  '¿La persona responde al hablarle?',
                  responds,
                  (answer) => responds = answer,
                ),
                const SizedBox(height: 8),
                triageQuestion(
                  '¿Respira normalmente?',
                  breathesNormally,
                  (answer) => breathesNormally = answer,
                ),
                const SizedBox(height: 8),
                triageQuestion(
                  '¿Hay sangrado intenso?',
                  heavyBleeding,
                  (answer) => heavyBleeding = answer,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Necesito apoyo profesional'),
                  subtitle: const Text(
                    'La consulta se guardará localmente. El envío a profesionales aún no está disponible.',
                  ),
                  value: helpRequested,
                  onChanged: (value) => setState(() => helpRequested = value),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La orientación y la prioridad preliminar se calcularán con las fichas locales.',
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
