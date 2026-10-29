import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';

class CaseApiException implements Exception {
  const CaseApiException(this.message, {this.conflict = false});
  final String message;
  final bool conflict;
  @override
  String toString() => message;
}

class RemoteCase {
  const RemoteCase(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get consultationId => data['consultationId'] as String;
  String get status => data['status'] as String;
  String? get assignee => data['assignedProfessionalUserId'] as String?;
  String? get observation => data['observation'] as String?;
  DateTime? get createdAt =>
      DateTime.tryParse(data['createdAt'] as String? ?? '');
  DateTime? get closedAt =>
      DateTime.tryParse(data['closedAt'] as String? ?? '');
}

class CaseApiService {
  CaseApiService(this.client);
  final http.Client client;

  Uri _url(String path, [Map<String, String>? query]) => Uri.parse(
    '${ApiConfig.baseUrl}/api/v1/$path',
  ).replace(queryParameters: query);

  Future<List<RemoteCase>> listAvailable(String token) async {
    final result = await _request(
      'GET',
      'cases',
      token,
      query: {'status': 'AVAILABLE'},
    );
    return (result as List<dynamic>)
        .map((value) => RemoteCase(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<RemoteCase>> listAssignedToMe(String token) async {
    final result = await _request(
      'GET',
      'cases',
      token,
      query: {'assignmentRelation': 'ASSIGNED_TO_ME'},
    );
    return (result as List<dynamic>)
        .map((value) => RemoteCase(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<RemoteCase>> listForCitizen(String token) async {
    final result = await _request('GET', 'cases/me', token);
    return (result as List<dynamic>)
        .map((value) => RemoteCase(value as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteCase> get(String token, String id) async => RemoteCase(
    await _request('GET', 'cases/$id', token) as Map<String, dynamic>,
  );

  Future<Map<String, dynamic>> consultation(String token, String id) async =>
      await _request('GET', 'consultation-submissions/$id', token)
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> history(String token, String id) async =>
      (await _request('GET', 'cases/$id/history', token) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<RemoteCase> assign(String token, String id) async => RemoteCase(
    await _request('POST', 'cases/$id/assign', token) as Map<String, dynamic>,
  );

  Future<RemoteCase> changeStatus(
    String token,
    String id,
    String status,
  ) async => RemoteCase(
    await _request(
          'PATCH',
          'cases/$id/status',
          token,
          body: {'newStatus': status},
        )
        as Map<String, dynamic>,
  );

  Future<RemoteCase> close(String token, String id, String observation) async =>
      RemoteCase(
        await _request(
              'POST',
              'cases/$id/close',
              token,
              body: {'observation': observation},
            )
            as Map<String, dynamic>,
      );

  Future<dynamic> _request(
    String method,
    String path,
    String token, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = http.Request(method, _url(path, query))
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
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == HttpStatus.conflict) {
        throw const CaseApiException(
          'El caso cambió en el servidor. Actualiza la pantalla antes de intentar otra acción.',
          conflict: true,
        );
      }
      if (response.statusCode == HttpStatus.forbidden) {
        throw const CaseApiException(
          'No tienes acceso a este caso o tu perfil profesional no está verificado.',
        );
      }
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const CaseApiException(
          'La sesión venció. Inicia sesión de nuevo.',
        );
      }
      throw CaseApiException(
        'No se pudo completar la solicitud (${response.statusCode}).',
      );
    } on CaseApiException {
      rethrow;
    } on SocketException {
      throw const CaseApiException(
        'Sin conexión con el servidor. Revisa internet e inténtalo de nuevo.',
      );
    } on FormatException {
      throw const CaseApiException(
        'El servidor devolvió una respuesta inválida.',
      );
    } catch (_) {
      throw const CaseApiException(
        'No se pudo conectar con el servidor. Inténtalo de nuevo.',
      );
    }
  }
}
