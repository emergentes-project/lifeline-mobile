import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../medical_bases/data/index/local_medical_knowledge_repository.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/consultation_guidance.dart';
import '../domain/models/saved_consultation.dart';
import 'patient_fields_page.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/blocs/auth_state.dart';
import '../application/consultation_owner.dart';
import '../application/consultation_sync_service.dart';
import '../../notifications/application/publish_notification_token.dart';
import '../../../core/presentation/app_message_view.dart';

class ConsultationHistoryPage extends StatefulWidget {
  const ConsultationHistoryPage({super.key});

  @override
  State<ConsultationHistoryPage> createState() =>
      _ConsultationHistoryPageState();
}

class _ConsultationHistoryPageState extends State<ConsultationHistoryPage> {
  late Future<List<SavedConsultation>> consultations;
  final deliveryErrors = <int, String>{};

  @override
  void initState() {
    super.initState();
    consultations = load();
  }

  Future<List<SavedConsultation>> load() async {
    final auth = context.read<AuthCubit>().state;
    final ownerKey = consultationOwnerKey(auth);
    final sync = _provided<ConsultationSyncService>(context);
    if (sync != null) {
      try {
        final outcomes = await sync.syncPending(
          ownerKey: ownerKey,
          citizenUserId: auth.status == AuthStatus.authenticated
              ? auth.user?.id
              : null,
        );
        deliveryErrors
          ..clear()
          ..addAll({
            for (final outcome in outcomes)
              if (outcome.errorMessage != null)
                outcome.localId: outcome.errorMessage!,
          });
      } catch (_) {
        deliveryErrors.clear();
      }
    }
    if (!mounted) return const [];
    final items = await context.read<LocalConsultationRepository>().list(
      ownerKey: ownerKey,
      knowledge: context.read<LocalMedicalKnowledgeRepository>(),
    );
    if (!mounted) return items;
    await publishNotificationToken(context, auth: auth, consultations: items);
    return items;
  }

  String statusLabel(SavedConsultation item) {
    final guidance = item.guidance;
    if (guidance == null) return 'Orientación pendiente';
    return switch (guidance.status) {
      GuidanceStatus.ready => 'Orientación lista',
      GuidanceStatus.needsDescription => 'Falta descripción',
      GuidanceStatus.noEvidence => 'Faltan datos para orientar',
      GuidanceStatus.modelUnavailable => 'Modelo no disponible',
      GuidanceStatus.failed => 'Orientación fallida',
    };
  }

  String priorityLabel(PreliminaryPriority? value) => switch (value) {
    PreliminaryPriority.high => 'Prioridad alta',
    PreliminaryPriority.medium => 'Prioridad media',
    PreliminaryPriority.low => 'Prioridad baja',
    null => 'Prioridad pendiente',
  };

  String _deliveryLine(SavedConsultation item) {
    if (!item.draft.helpRequested) return '';
    final status = item.syncStatus == 'confirmed'
        ? 'Envío confirmado.'
        : 'Envío pendiente. Se reintentará con la misma consulta.';
    final error = deliveryErrors[item.id];
    return error == null ? '\n$status' : '\n$status\n$error';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Consultas guardadas')),
    body: FutureBuilder<List<SavedConsultation>>(
      future: consultations,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Cargando consultas guardadas',
            ),
          );
        }
        if (snapshot.hasError) {
          return AppMessageView(
            icon: Icons.error_outline,
            title: 'No se pudo abrir el historial',
            message: 'Las consultas siguen guardadas en este dispositivo.',
            actionLabel: 'Reintentar',
            onAction: () => setState(() {
              consultations = load();
            }),
          );
        }
        final items = snapshot.data ?? const <SavedConsultation>[];
        if (items.isEmpty) {
          return const AppMessageView(
            icon: Icons.history,
            title: 'Sin consultas guardadas',
            message: 'Las consultas que guardes aparecerán aquí.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final future = load();
            setState(() {
              consultations = future;
            });
            await future;
          },
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Icon(
                    item.canRetry
                        ? Icons.pending_actions_outlined
                        : Icons.assignment_turned_in_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    semanticLabel: item.canRetry
                        ? 'Orientación pendiente o fallida'
                        : 'Orientación disponible',
                  ),
                  title: Text(
                    item.patient?.name ?? 'Consulta sin solicitud de ayuda',
                  ),
                  subtitle: Text(
                    '${item.createdAt.toLocal().day}/${item.createdAt.toLocal().month}/${item.createdAt.toLocal().year} · '
                    '${statusLabel(item)} · ${priorityLabel(item.guidance?.preliminaryPriority)}\n'
                    '${item.draft.description.isEmpty ? 'Sin descripción' : item.draft.description}'
                    '${_deliveryLine(item)}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConsultationSummaryPage(
                          draft: item.draft,
                          patient: item.patient,
                          savedId: item.id,
                          initialGuidance: item.guidance,
                          fromHistory: true,
                          initialSyncStatus: item.syncStatus,
                          initialBackendConsultationId:
                              item.backendConsultationId,
                        ),
                      ),
                    );
                    if (context.mounted) {
                      setState(() {
                        consultations = load();
                      });
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

T? _provided<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
