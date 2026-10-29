import 'package:flutter/material.dart';
import 'package:lifeline_mobile/features/consultation/data/ai/consultation_guidance_service.dart';
import 'package:lifeline_mobile/features/consultation/data/ai/gemma4_on_device_inference.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/patient_draft.dart';
import 'package:lifeline_mobile/features/medical_bases/data/index/local_medical_knowledge_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Consulta local'))),
    ),
  );
  final knowledge = LocalMedicalKnowledgeRepository();
  final inference = Gemma4OnDeviceInference();
  try {
    await knowledge.load();
    final guidance =
        await ConsultationGuidanceService(
          knowledge: knowledge,
          inference: inference,
        ).create(
          draft: const ConsultationDraft(
            description:
                'Tiene un corte superficial en la mano, está consciente, respira normalmente y no hay sangrado intenso.',
            helpRequested: false,
            responds: TriageAnswer.yes,
            breathesNormally: TriageAnswer.yes,
            heavyBleeding: TriageAnswer.no,
          ),
          patient: const PatientDraft(name: 'Prueba', ageYears: 32),
        );
    debugPrint('CONSULTATION_SMOKE_STATUS: ${guidance.status.name}');
    debugPrint('CONSULTATION_SMOKE_CARDS: ${guidance.cardTitles.join(', ')}');
    debugPrint('CONSULTATION_SMOKE_CHUNKS: ${guidance.chunkIds.join(', ')}');
    debugPrint(
      'CONSULTATION_SMOKE_PRIORITY: ${guidance.preliminaryPriority?.name}',
    );
    debugPrint(
      'CONSULTATION_SMOKE_HELP: ${guidance.professionalHelpRecommended}',
    );
  } catch (error, stackTrace) {
    debugPrint('CONSULTATION_SMOKE_ERROR: $error');
    debugPrintStack(stackTrace: stackTrace);
  } finally {
    await inference.dispose();
    await knowledge.close();
  }
}
