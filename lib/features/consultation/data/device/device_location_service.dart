import 'package:geolocator/geolocator.dart';

class DeviceLocation {
  const DeviceLocation(this.latitude, this.longitude, this.accuracyMeters);
  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DeviceLocationService {
  Future<DeviceLocation> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        'Activa la ubicación del dispositivo para registrar las coordenadas.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(
        'Permite el acceso a la ubicación para registrar las coordenadas.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        'El permiso de ubicación está bloqueado. Habilítalo en ajustes del teléfono.',
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceLocation(
        position.latitude,
        position.longitude,
        position.accuracy,
      );
    } catch (_) {
      throw const DeviceLocationException(
        'No se pudo obtener la ubicación. Reintenta o escribe una referencia.',
      );
    }
  }
}
