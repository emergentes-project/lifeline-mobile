import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../core/config/api_config.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/saved_consultation.dart';
import '../domain/models/consultation_guidance.dart';

class ConsultationSyncAttempt {
  const ConsultationSyncAttempt({
    required this.localId,
    required this.syncStatus,
    this.backendConsultationId,
    this.errorMessage,
    this.retryable = true,
  });

  final int localId;
  final String syncStatus;
  final String? backendConsultationId;
  final String? errorMessage;
  final bool retryable;
}

class ConsultationSyncService {
  ConsultationSyncService({
    required this.repository,
    required this.client,
    this.baseUrl = ApiConfig.baseUrl,
    this.timeout = const Duration(seconds: 20),
  });

  static const maxPhotoBytes = 10 * 1024 * 1024;

  final LocalConsultationRepository repository;
  final http.Client client;
  final String baseUrl;
  final Duration timeout;
  final _inFlight = <String, Future<List<ConsultationSyncAttempt>>>{};
  final _guestRefreshAfter = <String, DateTime>{};

  Future<List<ConsultationSyncAttempt>> syncPending({
    required String ownerKey,
    String? citizenUserId,
    String? accessToken,
    bool forceRetry = true,
  }) => _inFlight.putIfAbsent(
    ownerKey,
    () =>
        _run(
          ownerKey: ownerKey,
          citizenUserId: citizenUserId,
          accessToken: accessToken,
          forceRetry: forceRetry,
        ).whenComplete(() {
          _inFlight.remove(ownerKey);
        }),
  );

  Future<List<ConsultationSyncAttempt>> _run({
    required String ownerKey,
    String? citizenUserId,
    String? accessToken,
    required bool forceRetry,
  }) async {
    await repository.recoverInterrupted(ownerKey);
    final rows = await repository.list(ownerKey: ownerKey);
    final attempts = <ConsultationSyncAttempt>[];
    for (final row in rows) {
      if (!_isFinalized(row, forceRetry: forceRetry)) continue;
      if (!forceRetry &&
          row.nextSyncAt?.isAfter(DateTime.now().toUtc()) == true) {
        continue;
      }
      await repository.updateDelivery(
        row.id,
        ownerKey: ownerKey,
        syncStatus: 'sending',
      );
      ConsultationSyncAttempt result;
      try {
        result = await _syncOne(row, ownerKey, citizenUserId, accessToken);
      } catch (_) {
        result = ConsultationSyncAttempt(
          localId: row.id,
          syncStatus: 'pending',
          backendConsultationId: row.backendConsultationId,
          errorMessage: 'No se pudo completar el envío. Se volverá a intentar.',
        );
      }
      final confirmed = result.syncStatus == 'confirmed';
      final status = confirmed
          ? 'confirmed'
          : result.retryable
          ? 'pending'
          : 'failed';
      final attemptCount = row.syncAttempts + 1;
      final delaySeconds = (5 * (1 << attemptCount.clamp(0, 8).toInt()))
          .clamp(5, 900)
          .toInt();
      await repository.updateDelivery(
        row.id,
        ownerKey: ownerKey,
        syncStatus: status,
        backendConsultationId: result.backendConsultationId,
        syncAttempts: attemptCount,
        nextSyncAt: confirmed || !result.retryable
            ? null
            : DateTime.now().toUtc().add(Duration(seconds: delaySeconds)),
        syncError: confirmed
            ? null
            : result.errorMessage ?? 'Pendiente de conexión con el servidor.',
      );
      attempts.add(
        ConsultationSyncAttempt(
          localId: row.id,
          syncStatus: status,
          backendConsultationId: result.backendConsultationId,
          errorMessage: result.errorMessage,
          retryable: result.retryable,
        ),
      );
    }
    return attempts;
  }

  bool _isFinalized(SavedConsultation row, {bool forceRetry = false}) =>
      (row.syncStatus == 'pending' ||
          (forceRetry && row.syncStatus == 'failed')) &&
      (row.guidance?.isReady == true ||
          (row.draft.helpRequested && row.guidance != null)) &&
      row.mobileConsultationId.isNotEmpty &&
      row.idempotencyKey.isNotEmpty;

  Future<ConsultationSyncAttempt> _syncOne(
    SavedConsultation row,
    String ownerKey,
    String? citizenUserId,
    String? accessToken,
  ) async {
    var backendId = row.backendConsultationId;
    if (backendId == null || backendId.isEmpty) {
      final sent = await _postConsultation(row, citizenUserId, accessToken);
      if (sent.backendId == null) {
        await _remember(row, 'post_consultation', sent);
        return ConsultationSyncAttempt(
          localId: row.id,
          syncStatus: 'pending',
          errorMessage: sent.errorMessage,
          retryable: sent.retryable,
        );
      }
      backendId = sent.backendId;
      final saved = await _saveDelivery(
        row,
        ownerKey: ownerKey,
        syncStatus: 'sending',
        backendConsultationId: backendId,
        guestAccessToken: sent.guestAccessToken,
      );
      if (!saved) {
        return ConsultationSyncAttempt(
          localId: row.id,
          syncStatus: 'pending',
          errorMessage: 'No se pudo guardar el estado del envío.',
        );
      }
    }

    final photoPath = row.draft.photoPath;
    if (photoPath == null || photoPath.isEmpty) {
      final saved = await _saveDelivery(
        row,
        ownerKey: ownerKey,
        syncStatus: 'confirmed',
        backendConsultationId: backendId,
      );
      if (!saved) {
        return ConsultationSyncAttempt(
          localId: row.id,
          syncStatus: 'pending',
          backendConsultationId: backendId,
          errorMessage: 'No se pudo guardar el estado del envío.',
        );
      }
      return ConsultationSyncAttempt(
        localId: row.id,
        syncStatus: 'confirmed',
        backendConsultationId: backendId,
      );
    }

    final photoProblem = await _photoProblem(photoPath);
    if (photoProblem != null) {
      await _rememberMessage(
        row,
        operation: 'post_photo',
        type: photoProblem == 'La foto ya no está en el dispositivo.'
            ? 'missing_photo'
            : 'invalid_response',
        message: photoProblem,
      );
      return ConsultationSyncAttempt(
        localId: row.id,
        syncStatus: 'pending',
        backendConsultationId: backendId,
        errorMessage: photoProblem,
        retryable: false,
      );
    }

    final uploaded = await _postPhoto(
      backendId!,
      photoPath,
      row.idempotencyKey,
    );
    if (!uploaded.accepted) {
      await _remember(row, 'post_photo', uploaded);
      return ConsultationSyncAttempt(
        localId: row.id,
        syncStatus: 'pending',
        backendConsultationId: backendId,
        errorMessage: uploaded.errorMessage,
        retryable: uploaded.retryable,
      );
    }

    final saved = await _saveDelivery(
      row,
      ownerKey: ownerKey,
      syncStatus: 'confirmed',
      backendConsultationId: backendId,
    );
    if (!saved) {
      return ConsultationSyncAttempt(
        localId: row.id,
        syncStatus: 'pending',
        backendConsultationId: backendId,
        errorMessage: 'No se pudo guardar el estado del envío.',
      );
    }
    return ConsultationSyncAttempt(
      localId: row.id,
      syncStatus: 'confirmed',
      backendConsultationId: backendId,
    );
  }

  Future<void> refreshTracking({
    required String ownerKey,
    String? citizenUserId,
    String? accessToken,
  }) async {
    final rows = await repository.list(ownerKey: ownerKey);
    for (final row in rows) {
      if (row.syncStatus != 'confirmed' ||
          !row.draft.helpRequested ||
          row.backendConsultationId == null) {
        continue;
      }
      try {
        String? guestToken;
        final headers = <String, String>{};
        if (citizenUserId != null) {
          if (accessToken == null || accessToken.isEmpty) continue;
          headers['Authorization'] = 'Bearer $accessToken';
        } else {
          guestToken = await _guestToken(row, ownerKey);
          if (guestToken == null) continue;
          headers['X-Consultation-Token'] = guestToken;
        }
        final uri = _uri(
          '/api/v1/consultation-submissions/${row.backendConsultationId}/tracking',
        );
        var response = await client.get(uri, headers: headers).timeout(timeout);
        if (citizenUserId == null &&
            (response.statusCode == 404 || response.statusCode == 401)) {
          guestToken = await _guestToken(row, ownerKey, renew: true);
          if (guestToken == null) continue;
          headers['X-Consultation-Token'] = guestToken;
          response = await client.get(uri, headers: headers).timeout(timeout);
        }
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        if (data is! Map || data['consultationId'] != row.backendConsultationId) {
          continue;
        }
        final status = data['caseStatus'];
        if (status != null &&
            !const [
              'AVAILABLE',
              'ASSIGNED',
              'IN_PROGRESS',
              'CLOSED',
            ].contains(status)) {
          continue;
        }
        final rawStamp = data['updatedAt'];
        if (rawStamp is! String) continue;
        final stamp = DateTime.tryParse(
          RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(rawStamp)
              ? rawStamp
              : '${rawStamp}Z',
        );
        if (stamp == null) continue;
        await repository.updateTracking(
          row.id,
          ownerKey: ownerKey,
          caseId: data['caseId'] as String?,
          caseStatus: status as String?,
          updatedAt: stamp,
        );
      } on TimeoutException {
        break;
      } on SocketException {
        break;
      } on http.ClientException {
        break;
      } catch (_) {
        // The last confirmed server state remains readable offline.
      }
    }
  }

  Future<String?> _guestToken(
    SavedConsultation row,
    String ownerKey, {
    bool renew = false,
  }) async {
    if (!renew && row.guestAccessToken?.isNotEmpty == true) {
      return row.guestAccessToken;
    }
    final next = _guestRefreshAfter[row.mobileConsultationId];
    if (next != null && next.isAfter(DateTime.now().toUtc())) return null;
    _guestRefreshAfter[row.mobileConsultationId] = DateTime.now().toUtc().add(
      const Duration(minutes: 5),
    );
    final receipt = await _postConsultation(row, null, null);
    if (receipt.backendId != row.backendConsultationId ||
        receipt.guestAccessToken?.isNotEmpty != true) {
      return null;
    }
    await repository.updateDelivery(
      row.id,
      ownerKey: ownerKey,
      syncStatus: row.syncStatus,
      guestAccessToken: receipt.guestAccessToken,
    );
    return receipt.guestAccessToken;
  }

  Future<_HttpResult> _postConsultation(
    SavedConsultation row,
    String? citizenUserId,
    String? accessToken,
  ) async {
    try {
      final response = await client
          .post(
            _uri('/api/v1/consultation-submissions'),
            headers: {
              'Content-Type': 'application/json',
              'Idempotency-Key': row.idempotencyKey,
              if (accessToken != null && accessToken.isNotEmpty)
                'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(_body(row, citizenUserId)),
          )
          .timeout(timeout);
      if (response.statusCode == HttpStatus.ok ||
          response.statusCode == HttpStatus.created) {
        final backendId = _readBackendId(response.body);
        if (backendId == null) {
          return _failed(
            'invalid_response',
            httpStatus: response.statusCode,
            errorMessage:
                'El servidor no devolvió el identificador de la consulta.',
          );
        }
        final payload = jsonDecode(response.body);
        return _HttpResult(
          backendId: backendId,
          guestAccessToken: payload is Map
              ? payload['guestAccessToken'] as String?
              : null,
        );
      }
      if (response.statusCode == HttpStatus.badRequest ||
          response.statusCode == HttpStatus.conflict) {
        return _failed(
          _httpType(response.statusCode),
          httpStatus: response.statusCode,
          errorMessage: _rejection(response),
        );
      }
      return _failed(
        _httpType(response.statusCode),
        httpStatus: response.statusCode,
      );
    } on TimeoutException {
      return _failed('timeout');
    } on SocketException {
      return _failed('network');
    } on http.ClientException {
      return _failed('network');
    } catch (_) {
      return _failed('invalid_response');
    }
  }

  Future<_HttpResult> _postPhoto(
    String backendId,
    String photoPath,
    String idempotencyKey,
  ) async {
    final contentType = _imageContentType(photoPath);
    if (contentType == null) {
      return _failed(
        'invalid_response',
        errorMessage: 'La foto debe ser JPEG, PNG o WEBP.',
      );
    }
    try {
      final bytes = await File(photoPath).readAsBytes();
      final request = http.MultipartRequest(
        'POST',
        _uri('/api/v1/consultation-submissions/$backendId/photo'),
      );
      request.headers['Idempotency-Key'] = idempotencyKey;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: path.basename(photoPath),
          contentType: http.MediaType.parse(contentType),
        ),
      );
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);
      if (response.statusCode == HttpStatus.ok ||
          response.statusCode == HttpStatus.created) {
        return const _HttpResult(accepted: true);
      }
      if (response.statusCode == HttpStatus.notFound) {
        return _failed(
          'invalid_response',
          httpStatus: response.statusCode,
          errorMessage:
              'La foto no se adjuntó. Se reintentará sobre la misma consulta.',
          retryable: true,
        );
      }
      if (response.statusCode == HttpStatus.badRequest ||
          response.statusCode == HttpStatus.conflict) {
        return _failed(
          _httpType(response.statusCode),
          httpStatus: response.statusCode,
          errorMessage: _rejection(response),
        );
      }
      return _failed(
        _httpType(response.statusCode),
        httpStatus: response.statusCode,
      );
    } on TimeoutException {
      return _failed('timeout');
    } on SocketException {
      return _failed('network');
    } on http.ClientException {
      return _failed('network');
    } catch (_) {
      return _failed('invalid_response');
    }
  }

  Future<bool> _saveDelivery(
    SavedConsultation row, {
    required String ownerKey,
    required String syncStatus,
    String? backendConsultationId,
    String? guestAccessToken,
  }) async {
    try {
      await repository.updateDelivery(
        row.id,
        ownerKey: ownerKey,
        syncStatus: syncStatus,
        backendConsultationId: backendConsultationId,
        guestAccessToken: guestAccessToken,
      );
      return true;
    } catch (_) {
      await _rememberMessage(
        row,
        operation: 'update_delivery',
        type: 'invalid_response',
        message: 'No se pudo guardar el estado del envío.',
      );
      return false;
    }
  }

  Future<void> _remember(
    SavedConsultation row,
    String operation,
    _HttpResult result,
  ) async {
    if (result.failureType == null) return;
    await _rememberMessage(
      row,
      operation: operation,
      type: result.failureType!,
      httpStatus: result.httpStatus,
      message:
          result.failureMessage ??
          _defaultFailureMessage(result.failureType!, result.httpStatus),
    );
  }

  Future<void> _rememberMessage(
    SavedConsultation row, {
    required String operation,
    required String type,
    int? httpStatus,
    required String message,
  }) async {
    try {
      await repository.recordSyncFailure(
        operation: operation,
        type: type,
        httpStatus: httpStatus,
        localConsultationId: row.id,
        mobileConsultationId: row.mobileConsultationId,
        message: message,
      );
    } catch (_) {
      // El envío sigue pendiente aunque el registro del fallo no se guarde.
    }
  }

  _HttpResult _failed(String type, {int? httpStatus, String? errorMessage, bool? retryable}) {
    final keepsScreenText =
        type == 'timeout' || type == 'network' || type == 'http_5xx';
    return _HttpResult(
      errorMessage: keepsScreenText ? null : errorMessage,
      failureType: type,
      httpStatus: httpStatus,
      failureMessage: _defaultFailureMessage(type, httpStatus),
      retryableOverride: retryable,
    );
  }

  String _httpType(int status) {
    if (status == HttpStatus.badRequest) return 'http_400';
    if (status == HttpStatus.conflict) return 'http_409';
    if (status >= 500 && status <= 599) return 'http_5xx';
    return 'invalid_response';
  }

  String _defaultFailureMessage(String type, int? status) => switch (type) {
    'timeout' => 'Se agotó el tiempo de envío.',
    'network' => 'No hubo conexión con el servidor.',
    'http_400' || 'http_409' =>
      'El servidor rechazó el envío${status == null ? '' : ' ($status)'}.',
    'http_5xx' =>
      'El servidor no completó el envío${status == null ? '' : ' ($status)'}.',
    'missing_photo' => 'La foto ya no está en el dispositivo.',
    _ => 'La respuesta del servidor no se pudo usar.',
  };

  Future<String?> _photoProblem(String photoPath) async {
    if (_imageContentType(photoPath) == null) {
      return 'La foto debe ser JPEG, PNG o WEBP.';
    }
    final file = File(photoPath);
    if (!await file.exists()) return 'La foto ya no está en el dispositivo.';
    if (await file.length() > maxPhotoBytes) return 'La foto supera 10 MB.';
    return null;
  }

  Map<String, dynamic> _body(SavedConsultation row, String? citizenUserId) {
    final guidance = row.guidance!;
    final text = row.draft.description.trim();
    final patient = row.draft.helpRequested ? row.patient : null;
    return {
      'mobileConsultationId': row.mobileConsultationId,
      'citizenUserId': citizenUserId,
      'inputText': text.isEmpty ? null : text,
      'photoStorageKey': null,
      'helpRequested': row.draft.helpRequested,
      if (patient != null && patient.requesterPhone != null)
        'requesterPhone': patient.requesterPhone,
      'patient': patient == null
          ? null
          : {
              'name': patient.name,
              'ageYears': patient.ageYears,
              'locationDescription': patient.locationDescription,
              'province': patient.province,
              'latitude': patient.latitude,
              'longitude': patient.longitude,
              'phone': patient.requesterPhone,
            },
      'answer': {
        'guidanceText': guidance.fullTextForProfessional,
        'guidanceStatus': switch (guidance.status) {
          GuidanceStatus.ready => 'GENERATED',
          GuidanceStatus.needsDescription ||
          GuidanceStatus.noEvidence => 'INSUFFICIENT_INFO',
          GuidanceStatus.modelUnavailable || GuidanceStatus.failed => 'FAILED',
        },
        'preliminaryPriority': guidance.preliminaryPriority?.name.toUpperCase(),
        'professionalHelpRecommended':
            guidance.professionalHelpRecommended ?? false,
        'sourceReferences': [
          for (final source in guidance.sources)
            {
              'institution': source.institution,
              'title': source.title,
              'url': source.url,
            },
        ],
      },
      'consultationRecordedAt': _recordedAt(row.createdAt),
      'idempotencyKey': row.idempotencyKey,
    };
  }

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path');
  }

  String? _readBackendId(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final id = decoded['id'];
      if (id is! String || id.isEmpty) return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  String _rejection(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        for (final key in ['message', 'detail', 'error']) {
          final value = decoded[key];
          if (value is String && value.trim().isNotEmpty) return value.trim();
        }
      }
    } catch (_) {}
    return 'El servidor rechazó el envío (${response.statusCode}).';
  }

  String? _imageContentType(String photoPath) {
    final lower = photoPath.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }

  String _recordedAt(DateTime createdAt) {
    final utc = createdAt.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final year = utc.year.toString().padLeft(4, '0');
    return '$year-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }
}

class _HttpResult {
  const _HttpResult({
    this.backendId,
    this.errorMessage,
    this.accepted = false,
    this.failureType,
    this.httpStatus,
    this.failureMessage,
    this.guestAccessToken,
    this.retryableOverride,
  });

  final String? backendId;
  final String? errorMessage;
  final bool accepted;
  final String? failureType;
  final int? httpStatus;
  final String? failureMessage;
  final String? guestAccessToken;
  final bool? retryableOverride;
  bool get retryable =>
      retryableOverride ?? (httpStatus == null ||
      httpStatus == 408 ||
      httpStatus == 429 ||
      (httpStatus! >= 500 && httpStatus! <= 599) ||
      httpStatus == 200 ||
      httpStatus == 201);
}
