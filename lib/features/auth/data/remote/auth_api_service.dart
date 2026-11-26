import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../../core/config/api_config.dart';
import '../../domain/models/authenticated_user.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthApiService {
  AuthApiService(this.client);
  final http.Client client;
  Uri uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v1/authentication/$path');

  Future<AuthenticatedUser> signIn(String email, String password) async {
    try {
      final response = await client
          .post(
            uri('sign-in'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == HttpStatus.ok) {
        try {
          return AuthenticatedUser.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
        } catch (_) {
          throw const AuthApiException(
            'El servidor devolvió una respuesta de inicio de sesión inválida.',
          );
        }
      }
      throw AuthApiException(_signInFailure(response));
    } on AuthApiException {
      rethrow;
    } on TimeoutException {
      throw const AuthApiException(
        'Se agotó el tiempo de espera del servidor. Inténtalo de nuevo.',
      );
    } on HandshakeException {
      throw const AuthApiException(
        'No se pudo establecer una conexión segura con el servidor.',
      );
    } on SocketException {
      throw const AuthApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const AuthApiException(
        'La conexión con el servidor se interrumpió. Inténtalo de nuevo.',
      );
    }
  }

  String _signInFailure(http.Response response) {
    final status = response.statusCode;
    if (status == HttpStatus.unauthorized) {
      return 'Correo o contraseña incorrectos para este servidor.';
    }
    if (status == HttpStatus.badRequest) {
      return 'Revisa los datos de inicio de sesión e inténtalo de nuevo.';
    }
    if (status == HttpStatus.forbidden &&
        response.body.toLowerCase().contains('web app is stopped')) {
      return 'El servidor está detenido. Inténtalo más tarde.';
    }
    if (status == HttpStatus.forbidden) {
      return 'El servidor rechazó el acceso a esta cuenta.';
    }
    if (status == HttpStatus.notFound) {
      return 'El servicio de inicio de sesión no está disponible.';
    }
    if (status == HttpStatus.tooManyRequests) {
      return 'Hay demasiados intentos de ingreso. Espera un momento e inténtalo de nuevo.';
    }
    if (status >= 500) {
      return 'El servidor tuvo un fallo interno ($status). Inténtalo más tarde.';
    }
    return 'No se pudo iniciar sesión. El servidor respondió con el código $status.';
  }

  Future<void> register(String path, Map<String, dynamic> data) async {
    final response = await client
        .post(
          uri(path),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == HttpStatus.created) return;
    throw AuthApiException(
      response.statusCode == HttpStatus.conflict
          ? 'Este correo ya está registrado.'
          : 'No se pudo crear la cuenta (${response.statusCode}).',
    );
  }

  Future<void> signOut(String token) async {
    try {
      await client
          .post(uri('sign-out'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Local sign-out works offline. */
    }
  }
}
