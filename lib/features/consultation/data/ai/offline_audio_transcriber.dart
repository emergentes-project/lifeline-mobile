import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class OfflineAudioTranscriber {
  static const _folder = 'assets/models/whisper_tiny';
  static const _files = {
    'tiny-encoder.int8.onnx': 12937772,
    'tiny-decoder.int8.onnx': 89855401,
    'tiny-tokens.txt': 816730,
  };

  Future<String> transcribe(String audioPath) async {
    final folder = Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}whisper_tiny',
    );
    await folder.create(recursive: true);
    for (final entry in _files.entries) {
      final name = entry.key;
      final file = File('${folder.path}${Platform.pathSeparator}$name');
      if (await file.exists() && await file.length() == entry.value) continue;
      final data = await rootBundle.load('$_folder/$name');
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
    return Isolate.run(() => _decode(audioPath, folder.path));
  }
}

String _decode(String audioPath, String folder) {
  sherpa.initBindings();
  final wave = sherpa.readWave(audioPath);
  if (wave.samples.isEmpty) return '';
  var squared = 0.0;
  for (final sample in wave.samples) {
    squared += sample * sample;
  }
  if (squared / wave.samples.length < 0.000025) return '';
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$folder${Platform.pathSeparator}tiny-encoder.int8.onnx',
          decoder: '$folder${Platform.pathSeparator}tiny-decoder.int8.onnx',
          language: 'es',
          task: 'transcribe',
        ),
        tokens: '$folder${Platform.pathSeparator}tiny-tokens.txt',
        modelType: 'whisper',
        numThreads: 2,
      ),
    ),
  );
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text.trim();
    if (RegExp(
      r'^[\[(]?\s*(música|silencio|aplausos)\s*[\])]?$',
      caseSensitive: false,
    ).hasMatch(text)) {
      return '';
    }
    return text;
  } finally {
    stream.free();
    recognizer.free();
  }
}
