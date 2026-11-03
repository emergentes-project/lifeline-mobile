import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import '../../../core/presentation/system_status_bar.dart';
import '../../../core/theme/app_theme.dart';
import '../data/ai/offline_audio_transcriber.dart';
import '../data/local/private_media_store.dart';
import '../domain/models/consultation_draft.dart';
import 'patient_fields_page.dart';
import 'consultation_history_page.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/profile_page.dart';
import '../../cases/presentation/cases_page.dart';

enum _HomeAction { history, cases, profile, exit }

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
  bool busy = false;
  String? transcription;
  bool noVoiceDetected = false;
  String? inputError;
  bool needProfessionalHelp = false;
  TriageAnswer responds = TriageAnswer.unknown;
  TriageAnswer breathesNormally = TriageAnswer.unknown;
  TriageAnswer heavyBleeding = TriageAnswer.unknown;

  Widget triageQuestion(
    String label,
    TriageAnswer value,
    ValueChanged<TriageAnswer> onChanged,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<TriageAnswer>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: const [
        DropdownMenuItem(value: TriageAnswer.unknown, child: Text('No sé')),
        DropdownMenuItem(value: TriageAnswer.yes, child: Text('Sí')),
        DropdownMenuItem(value: TriageAnswer.no, child: Text('No')),
      ],
      onChanged: (answer) {
        if (answer != null) setState(() => onChanged(answer));
      },
    ),
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
      setState(() {
        photoPath = path;
        inputError = null;
      });
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
          inputError = null;
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

  void continueToGuidance() {
    final draft = ConsultationDraft(
      description: description.text,
      photoPath: photoPath,
      audioPath: audioPath,
      responds: responds,
      breathesNormally: breathesNormally,
      heavyBleeding: heavyBleeding,
      helpRequested: needProfessionalHelp,
    );
    if (recording || busy) {
      message('Espera a que termine la grabación y transcripción.');
      return;
    }
    if (!draft.hasInput) {
      setState(
        () => inputError =
            'Describe la situación, graba audio o adjunta una foto.',
      );
      return;
    }
    setState(() => inputError = null);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConsultationSummaryPage(draft: draft)),
    );
  }

  Future<void> openSection(_HomeAction action) async {
    switch (action) {
      case _HomeAction.history:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const ConsultationHistoryPage()),
        );
      case _HomeAction.cases:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const CasesPage(citizen: true)),
        );
      case _HomeAction.profile:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      case _HomeAction.exit:
        if (widget.guest) {
          context.read<AuthCubit>().leaveGuest();
        } else {
          await context.read<AuthCubit>().signOut();
        }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Nueva consulta'),
      bottom: const SystemStatusBar(mode: SystemStatusMode.offline),
      actions: [
        PopupMenuButton<_HomeAction>(
          tooltip: 'Abrir menú de secciones',
          icon: const Icon(Icons.menu),
          onSelected: openSection,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _HomeAction.history,
              child: ListTile(
                leading: Icon(Icons.history),
                title: Text('Consultas guardadas'),
              ),
            ),
            if (!widget.guest)
              const PopupMenuItem(
                value: _HomeAction.cases,
                child: ListTile(
                  leading: Icon(Icons.medical_information_outlined),
                  title: Text('Mis casos'),
                ),
              ),
            if (!widget.guest)
              const PopupMenuItem(
                value: _HomeAction.profile,
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Mi perfil'),
                ),
              ),
            PopupMenuItem(
              value: _HomeAction.exit,
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: Text(widget.guest ? 'Salir' : 'Cerrar sesión'),
              ),
            ),
          ],
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Header (Wireframe C-01)
                Text(
                  'Cuéntanos qué pasó',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                // Multi-line Description Field
                TextField(
                  controller: description,
                  onChanged: (_) {
                    if (inputError != null) setState(() => inputError = null);
                  },
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Descripción de la situación',
                    hintText: 'Describe la situación del paciente...',
                    alignLabelWithHint: true,
                    helperText:
                        'Puedes escribir o dictar. Revisa el texto antes de continuar.',
                  ),
                ),
                if (inputError != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        inputError!,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),

                // Multimodal Action Buttons Row (Wireframe C-01)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.styleFrom(
                          backgroundColor: recording
                              ? AppTheme.redSoft
                              : Colors.white,
                          side: BorderSide(
                            color: recording ? AppTheme.emergency : AppTheme.border,
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ).let(
                          (style) => OutlinedButton(
                            style: style,
                            onPressed: busy ? null : toggleRecording,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  recording ? Icons.stop_circle : Icons.mic_rounded,
                                  color: recording
                                      ? AppTheme.emergency
                                      : AppTheme.teal,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    recording ? 'Detener' : 'Grabar voz',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontHeading,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: recording
                                          ? AppTheme.emergency
                                          : AppTheme.slate,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(
                              color: AppTheme.border,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => pickPhoto(ImageSource.camera),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                color: AppTheme.teal,
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Tomar foto',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontHeading,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppTheme.slate,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: () => pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Elegir de galería'),
                  ),
                ),

                // Audio status card
                if (audioPath != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.mic, color: AppTheme.cyan),
                      title: const Text(
                        'Audio grabado',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        busy
                            ? 'Transcribiendo sin internet...'
                            : noVoiceDetected
                            ? 'No se detectó voz; toca para reintentar'
                            : transcription == null
                            ? 'Toca para intentar transcribir de nuevo'
                            : 'Texto agregado a la descripción',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: busy || recording
                          ? null
                          : () => transcribeAudio(audioPath!),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.slateMuted),
                        tooltip: 'Quitar audio grabado',
                        onPressed: busy || recording
                            ? null
                            : () => setState(() {
                                audioPath = null;
                                transcription = null;
                                noVoiceDetected = false;
                              }),
                      ),
                    ),
                  ),

                // Attached Photo Card (Wireframe C-01)
                if (photoPath != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border, width: 1.2),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(photoPath!),
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Foto adjunta',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontHeading,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppTheme.slate,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Solo se admite una foto',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 12,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          color: AppTheme.slateMuted,
                          tooltip: 'Quitar foto',
                          onPressed: () => setState(() => photoPath = null),
                        ),
                      ],
                    ),
                  ),

                // Ubicación registrada (GPS) (Wireframe C-01)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderLight, width: 1.2),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: AppTheme.teal, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ubicación registrada (GPS)',
                          style: TextStyle(
                            fontFamily: AppTheme.fontHeading,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppTheme.slate,
                          ),
                        ),
                      ),
                      Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                    ],
                  ),
                ),

                // Switch: Necesito apoyo profesional (Wireframe C-01)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border, width: 1.2),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: AppTheme.cyan,
                    title: const Text(
                      'Necesito apoyo profesional',
                      style: TextStyle(
                        fontFamily: AppTheme.fontHeading,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.slate,
                      ),
                    ),
                    subtitle: const Text(
                      'Se pedirán los datos del paciente',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    value: needProfessionalHelp,
                    onChanged: (val) => setState(() => needProfessionalHelp = val),
                  ),
                ),

                // Comprobaciones iniciales (Triage questions)
                Text(
                  'Comprobaciones iniciales',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                triageQuestion(
                  '¿La persona responde al hablarle?',
                  responds,
                  (answer) => responds = answer,
                ),
                triageQuestion(
                  '¿Respira normalmente?',
                  breathesNormally,
                  (answer) => breathesNormally = answer,
                ),
                triageQuestion(
                  '¿Hay sangrado intenso?',
                  heavyBleeding,
                  (answer) => heavyBleeding = answer,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Bottom CTA button: "Obtener orientación médica" (Wireframe C-01)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF64748B),
                  foregroundColor: Colors.white,
                ),
                onPressed: continueToGuidance,
                child: const Text('Obtener orientación médica'),
              ),
            ),
          ),
        ],
      ),
    ),
    // BottomNavigationBar matching Wireframe C-01 and C-07
    bottomNavigationBar: Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderLight, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) async {
          if (index == 1) {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const ConsultationHistoryPage()),
            );
          } else if (index == 2) {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: 'Nueva consulta',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Historial / Outbox',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    ),
  );
}

extension _LetExt<T> on T {
  R let<R>(R Function(T it) op) => op(this);
}
