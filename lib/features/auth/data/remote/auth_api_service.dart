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
    final response = await client
        .post(
          uri('sign-in'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == HttpStatus.ok) {
      return AuthenticatedUser.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw AuthApiException(
      response.statusCode == HttpStatus.unauthorized
          ? 'Correo o contraseña incorrectos.'
          : 'No se pudo iniciar sesión (${response.statusCode}).',
    );
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
