import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/models/managed_case.dart';
import '../domain/repositories/case_repository.dart';

class CaseApiException implements Exception {
  const CaseApiException(this.message, {this.conflict = false});
  final String message;
  final bool conflict;
  @override
  String toString() => message;
}

class CaseApiService implements CaseRepository {
  CaseApiService(this.client);
  final http.Client client;

  Uri _url(String path, [Map<String, String>? query]) => Uri.parse(
    '${ApiConfig.baseUrl}/api/v1/$path',
  ).replace(queryParameters: query);

  @override
  Future<List<ManagedCase>> listAvailable(String token) async => _caseList(
    await _request('GET', 'cases', token, query: {'status': 'AVAILABLE'}),
  );

  @override
  Future<List<ManagedCase>> listAssignedToMe(String token) async => _caseList(
    await _request(
      'GET',
      'cases',
      token,
      query: {'assignmentRelation': 'ASSIGNED_TO_ME'},
    ),
  );

  @override
  Future<List<ManagedCase>> listForCitizen(String token) async =>
      _caseList(await _request('GET', 'cases/me', token));

  @override
  Future<ManagedCase> get(String token, String id) async =>
      _case(await _request('GET', 'cases/$id', token) as Map<String, dynamic>);

  @override
  Future<CaseConsultation> consultation(String token, String id) async =>
      _consultation(
        await _request('GET', 'consultation-submissions/$id', token)
            as Map<String, dynamic>,
      );

  @override
  Future<List<CaseStatusChange>> history(String token, String id) async =>
      (await _request('GET', 'cases/$id/history', token) as List<dynamic>)
          .map((value) => _history(value as Map<String, dynamic>))
          .toList(growable: false);

  @override
  Future<ManagedCase> assign(String token, String id) async => _case(
    await _request('POST', 'cases/$id/assign', token) as Map<String, dynamic>,
  );

  @override
  Future<ManagedCase> changeStatus(
    String token,
    String id,
    CaseStatus status,
  ) async => _case(
    await _request(
          'PATCH',
          'cases/$id/status',
          token,
          body: {'newStatus': _statusWire(status)},
        )
        as Map<String, dynamic>,
  );

  @override
  Future<ManagedCase> close(
    String token,
    String id,
    String observation,
  ) async => _case(
    await _request(
          'POST',
          'cases/$id/close',
          token,
          body: {'observation': observation},
        )
        as Map<String, dynamic>,
  );

  List<ManagedCase> _caseList(dynamic body) => (body as List<dynamic>)
      .map((value) => _case(value as Map<String, dynamic>))
      .toList(growable: false);

  ManagedCase _case(Map<String, dynamic> json) => ManagedCase(
    id: json['id'] as String,
    consultationId: json['consultationId'] as String,
    status: _status(json['status'] as String),
    assignedProfessionalUserId: json['assignedProfessionalUserId'] as String?,
    observation: json['observation'] as String?,
    createdAt: _date(json['createdAt']),
    closedAt: _date(json['closedAt']),
  );

  CaseConsultation _consultation(Map<String, dynamic> json) {
    final patient = json['patient'] as Map<String, dynamic>?;
    final answer = json['answer'] as Map<String, dynamic>?;
    return CaseConsultation(
      inputText: json['inputText'] as String?,
      requesterPhone: json['requesterPhone'] as String?,
      helpRequested: json['helpRequested'] == true,
      hasPhoto: json['hasPhoto'] == true,
      patient: patient == null
          ? null
          : CasePatient(
              name: patient['name'] as String?,
              ageYears: patient['ageYears'] as int?,
              locationDescription: patient['locationDescription'] as String?,
              province: patient['province'] as String?,
              latitude: (patient['latitude'] as num?)?.toDouble(),
              longitude: (patient['longitude'] as num?)?.toDouble(),
            ),
      answer: answer == null
          ? null
          : CaseAnswer(
              guidanceStatus: answer['guidanceStatus'] as String?,
              guidanceText: answer['guidanceText'] as String?,
              preliminaryPriority: answer['preliminaryPriority'] as String?,
              professionalHelpRecommended:
                  answer['professionalHelpRecommended'] as bool?,
              sources:
                  (answer['sourceReferences'] as List<dynamic>? ?? const [])
                      .whereType<Map<String, dynamic>>()
                      .map(
                        (source) => CaseSource(
                          institution: source['institution'] as String?,
                          title: source['title'] as String?,
                          url: source['url'] as String?,
                        ),
                      )
                      .toList(growable: false),
            ),
    );
  }

  CaseStatusChange _history(Map<String, dynamic> json) => CaseStatusChange(
    toStatus: _status(json['toStatus'] as String),
    actorType: json['actorType'] as String?,
    occurredAt: _date(json['occurredAt']),
  );

  CaseStatus _status(String value) => switch (value) {
    'AVAILABLE' => CaseStatus.available,
    'ASSIGNED' => CaseStatus.assigned,
    'IN_PROGRESS' => CaseStatus.inProgress,
    'CLOSED' => CaseStatus.closed,
    _ => throw FormatException('Estado de caso desconocido: $value'),
  };

  String _statusWire(CaseStatus status) => switch (status) {
    CaseStatus.available => 'AVAILABLE',
    CaseStatus.assigned => 'ASSIGNED',
    CaseStatus.inProgress => 'IN_PROGRESS',
    CaseStatus.closed => 'CLOSED',
  };

  DateTime? _date(Object? value) {
    if (value is! String) return null;
    final hasZone = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value);
    return DateTime.tryParse(hasZone ? value : '${value}Z');
  }

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
