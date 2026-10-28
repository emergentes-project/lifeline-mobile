import 'package:flutter/material.dart';
import 'package:lifeline_mobile/features/consultation/data/ai/gemma4_on_device_inference.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Gemma smoke test')))));

  final inference = Gemma4OnDeviceInference();
  try {
    if (!await inference.isInstalled) {
      throw StateError('El modelo no está instalado en el dispositivo');
    }
    debugPrint('GEMMA_SMOKE: modelo instalado; iniciando carga');
    await inference.load();
    debugPrint('GEMMA_SMOKE: modelo cargado; iniciando inferencia');
    final response = await inference.generate('Responde únicamente con la palabra OK.');
    debugPrint('GEMMA_SMOKE_RESULT: $response');
  } catch (error, stackTrace) {
    debugPrint('GEMMA_SMOKE_ERROR: $error');
    debugPrintStack(stackTrace: stackTrace);
  } finally {
    await inference.dispose();
  }
}
