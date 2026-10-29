import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../core/config/api_config.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/saved_consultation.dart';

class ConsultationSyncAttempt {
  const ConsultationSyncAttempt({
    required this.localId,
    required this.syncStatus,
    this.backendConsultationId,
    this.errorMessage,
  });

  final int localId;
  final String syncStatus;
  final String? backendConsultationId;
  final String? errorMessage;
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

  Future<List<ConsultationSyncAttempt>> syncPending({
    required String ownerKey,
    String? citizenUserId,
  }) async {
    final rows = await repository.list(ownerKey: ownerKey);
    final attempts = <ConsultationSyncAttempt>[];
    for (final row in rows) {
      if (row.syncStatus != 'pending') continue;
      if (row.guidance?.isReady != true) continue;
      if (row.mobileConsultationId.isEmpty || row.idempotencyKey.isEmpty) {
        continue;
      }
      attempts.add(await _syncOne(row, ownerKey, citizenUserId));
    }
    return attempts;
  }

  Future<ConsultationSyncAttempt> _syncOne(
    SavedConsultation row,
    String ownerKey,
    String? citizenUserId,
  ) async {
    var backendId = row.backendConsultationId;
    if (backendId == null || backendId.isEmpty) {
      final sent = await _postConsultation(row, citizenUserId);
      if (sent.backendId == null) {
        return ConsultationSyncAttempt(
          localId: row.id,
          syncStatus: 'pending',
          errorMessage: sent.errorMessage,
        );
      }
      backendId = sent.backendId;
      await repository.updateDelivery(
        row.id,
        ownerKey: ownerKey,
        syncStatus: 'pending',
        backendConsultationId: backendId,
      );
    }

    final photoPath = row.draft.photoPath;
    if (photoPath == null || photoPath.isEmpty) {
      await repository.updateDelivery(
        row.id,
        ownerKey: ownerKey,
        syncStatus: 'confirmed',
        backendConsultationId: backendId,
      );
      return ConsultationSyncAttempt(
        localId: row.id,
        syncStatus: 'confirmed',
        backendConsultationId: backendId,
      );
    }

    final photoProblem = await _photoProblem(photoPath);
    if (photoProblem != null) {
      return ConsultationSyncAttempt(
        localId: row.id,
        syncStatus: 'pending',
        backendConsultationId: backendId,
        errorMessage: photoProblem,
      );
    }

    final uploaded = await _postPhoto(backendId!, photoPath);
    if (!uploaded.accepted) {
      return ConsultationSyncAttempt(
        localId: row.id,
        syncStatus: 'pending',
        backendConsultationId: backendId,
        errorMessage: uploaded.errorMessage,
      );
    }

    await repository.updateDelivery(
      row.id,
      ownerKey: ownerKey,
      syncStatus: 'confirmed',
      backendConsultationId: backendId,
    );
    return ConsultationSyncAttempt(
      localId: row.id,
      syncStatus: 'confirmed',
      backendConsultationId: backendId,
    );
  }

  Future<_HttpResult> _postConsultation(
    SavedConsultation row,
    String? citizenUserId,
  ) async {
    try {
      final response = await client
          .post(
            _uri('/api/v1/consultation-submissions'),
            headers: {
              'Content-Type': 'application/json',
              'Idempotency-Key': row.idempotencyKey,
            },
            body: jsonEncode(_body(row, citizenUserId)),
          )
          .timeout(timeout);
      if (response.statusCode == HttpStatus.ok ||
          response.statusCode == HttpStatus.created) {
        final backendId = _readBackendId(response.body);
        if (backendId == null) {
          return const _HttpResult(
            errorMessage:
                'El servidor no devolvió el identificador de la consulta.',
          );
        }
        return _HttpResult(backendId: backendId);
      }
      if (response.statusCode == HttpStatus.badRequest ||
          response.statusCode == HttpStatus.conflict) {
        return _HttpResult(errorMessage: _rejection(response));
      }
      return const _HttpResult();
    } on TimeoutException {
      return const _HttpResult();
    } on SocketException {
      return const _HttpResult();
    } on http.ClientException {
      return const _HttpResult();
    } catch (_) {
      return const _HttpResult();
    }
  }

  Future<_HttpResult> _postPhoto(String backendId, String photoPath) async {
    final contentType = _imageContentType(photoPath);
    if (contentType == null) {
      return const _HttpResult(
        errorMessage: 'La foto debe ser JPEG, PNG o WEBP.',
      );
    }
    try {
      final bytes = await File(photoPath).readAsBytes();
      final request = http.MultipartRequest(
        'POST',
        _uri('/api/v1/consultation-submissions/$backendId/photo'),
      );
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
        return const _HttpResult(
          errorMessage:
              'La foto no se adjuntó. Se reintentará sobre la misma consulta.',
        );
      }
      if (response.statusCode == HttpStatus.badRequest ||
          response.statusCode == HttpStatus.conflict) {
        return _HttpResult(errorMessage: _rejection(response));
      }
      return const _HttpResult();
    } on TimeoutException {
      return const _HttpResult();
    } on SocketException {
      return const _HttpResult();
    } on http.ClientException {
      return const _HttpResult();
    } catch (_) {
      return const _HttpResult();
    }
  }

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
        'guidanceText': guidance.message,
        'guidanceStatus': 'GENERATED',
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
  const _HttpResult({this.backendId, this.errorMessage, this.accepted = false});

  final String? backendId;
  final String? errorMessage;
  final bool accepted;
}
