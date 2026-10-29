import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';

class ProfileApiException implements Exception {
  const ProfileApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProfileApiService {
  ProfileApiService(this.client);
  final http.Client client;

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}/api/v1/$path/me');

  Future<Map<String, dynamic>> account(String token) =>
      _request('GET', 'users', token);

  Future<Map<String, dynamic>> roleProfile(
    String token, {
    required bool citizen,
  }) =>
      _request('GET', citizen ? 'citizen-profiles' : 'medical-profiles', token);

  Future<Map<String, dynamic>> updateAccount(
    String token,
    Map<String, dynamic> values,
  ) => _request('PUT', 'users', token, body: values);

  Future<Map<String, dynamic>> updateRoleProfile(
    String token,
    Map<String, dynamic> values, {
    required bool citizen,
  }) => _request(
    'PUT',
    citizen ? 'citizen-profiles' : 'medical-profiles',
    token,
    body: values,
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = http.Request(method, _uri(path))
        ..headers.addAll({
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.acceptHeader: 'application/json',
          if (body != null) HttpHeaders.contentTypeHeader: 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == HttpStatus.ok) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const ProfileApiException(
          'La sesión venció. Inicia sesión de nuevo.',
        );
      }
      if (response.statusCode == HttpStatus.forbidden) {
        throw const ProfileApiException('No tienes acceso a este perfil.');
      }
      throw ProfileApiException(
        'El servidor rechazó la solicitud (${response.statusCode}).',
      );
    } on ProfileApiException {
      rethrow;
    } on SocketException {
      throw const ProfileApiException(
        'No hay conexión con el servidor. Revisa internet e inténtalo de nuevo.',
      );
    } on HttpException {
      throw const ProfileApiException(
        'No se pudo conectar con el servidor. Inténtalo de nuevo.',
      );
    } on FormatException {
      throw const ProfileApiException(
        'El servidor devolvió una respuesta inválida.',
      );
    } catch (_) {
      throw const ProfileApiException(
        'No se pudo conectar con el servidor. Revisa internet e inténtalo de nuevo.',
      );
    }
  }
}
