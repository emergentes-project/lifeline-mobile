import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PrivateMediaStore {
  Future<String> directory() async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${root.path}${Platform.pathSeparator}consultation_media',
    );
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder.path;
  }

  Future<String> retainPhoto(String source) async {
    final extension = source.toLowerCase().endsWith('.png')
        ? 'png'
        : source.toLowerCase().endsWith('.webp')
        ? 'webp'
        : 'jpg';
    final target =
        '${await directory()}${Platform.pathSeparator}photo_${DateTime.now().microsecondsSinceEpoch}.$extension';
    return (await File(source).copy(target)).path;
  }

  Future<String> newAudioPath() async =>
      '${await directory()}${Platform.pathSeparator}voice_${DateTime.now().microsecondsSinceEpoch}.wav';
}
