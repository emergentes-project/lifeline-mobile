import 'package:flutter/services.dart';

class Gemma4OnDeviceInference {
  Gemma4OnDeviceInference({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lifeline/gemma4');

  static const modelFileName = 'gemma-4-E2B-it.litertlm';
  static const expectedModelBytes = 2588147712;

  final MethodChannel _channel;

  Future<String> get installedModelPath async {
    final status = await _channel.invokeMapMethod<String, Object?>('status');
    return status!['path'] as String;
  }

  Future<bool> get isInstalled async {
    final status = await _channel.invokeMapMethod<String, Object?>('status');
    return status?['installed'] == true;
  }

  Future<void> load() => _channel.invokeMethod<void>('load');

  Future<String> generate(String prompt, {String? imagePath}) async {
    final result = await _channel.invokeMethod<String>('generate', {
      'prompt': prompt,
      'imagePath': imagePath,
    });
    if (result == null || result.trim().isEmpty) {
      throw StateError('Gemma 4 no devolvió texto');
    }
    return result.trim();
  }

  Future<void> dispose() => _channel.invokeMethod<void>('dispose');
}
