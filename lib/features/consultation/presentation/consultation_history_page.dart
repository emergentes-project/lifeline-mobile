import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/system_status_bar.dart';
import '../../../core/presentation/wireframe_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../medical_bases/data/index/local_medical_knowledge_repository.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/consultation_guidance.dart';
import '../domain/models/saved_consultation.dart';
import 'patient_fields_page.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/blocs/auth_state.dart';
import '../../auth/presentation/profile_page.dart';
import '../application/consultation_owner.dart';
import '../application/consultation_sync_service.dart';
import '../../notifications/application/delivery_confirmation_notices.dart';
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
  List<SyncFailureCount> failureCounts = const [];
  bool onlyPending = false;
  StreamSubscription<({String ownerKey, bool needsSync})>? _localChanges;

  @override
  void initState() {
    super.initState();
    consultations = load();
    _localChanges = context.read<LocalConsultationRepository>().changes.listen((change) {
      if (!mounted) return;
      final auth = context.read<AuthCubit>().state;
      if (auth.status != AuthStatus.guest && auth.status != AuthStatus.authenticated) return;
      if (change.ownerKey != consultationOwnerKey(auth)) return;
      final local = context.read<LocalConsultationRepository>().list(ownerKey: change.ownerKey,
        knowledge: context.read<LocalMedicalKnowledgeRepository>());
      setState(() { consultations = local; });
    });
  }

  @override
  void dispose() {
    unawaited(_localChanges?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Future<List<SavedConsultation>> load() async {
    final auth = context.read<AuthCubit>().state;
    final ownerKey = consultationOwnerKey(auth);
    final repository = context.read<LocalConsultationRepository>();
    final knowledge = context.read<LocalMedicalKnowledgeRepository>();
    final notices = _provided<DeliveryConfirmationNotices>(context);
    final sync = _provided<ConsultationSyncService>(context);
    List<SavedConsultation>? before;
    if (sync != null) {
      try {
        before = await repository.list(ownerKey: ownerKey);
      } catch (_) {
        before = null;
      }
      try {
        final outcomes = await sync.syncPending(
          ownerKey: ownerKey,
          citizenUserId: auth.status == AuthStatus.authenticated
              && auth.user?.isCitizen == true ? auth.user?.id
              : null,
          accessToken: auth.user?.token,
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
    final items = await repository.list(
      ownerKey: ownerKey,
      knowledge: knowledge,
    );
    if (before != null && notices != null) {
      await notices.announce(before, items);
    }
    if (!mounted) return items;
    try {
      failureCounts = await repository.syncFailureCounts(ownerKey: ownerKey);
    } catch (_) {
      failureCounts = const [];
    }
    if (!mounted) return items;
    await publishNotificationToken(context, auth: auth, consultations: items);
    return items;
  }

  String statusLabel(SavedConsultation item) {
    if (item.syncStatus == 'pending') return 'Por sincronizar';
    if (item.syncStatus == 'sending') return 'Enviando';
    if (item.syncStatus == 'failed') return 'Envío fallido';
    if (item.syncStatus == 'confirmed') return 'Envío confirmado';
    final guidance = item.guidance;
    if (guidance == null) return 'Orientación pendiente';
    return switch (guidance.status) {
      GuidanceStatus.ready => 'Orientación lista',
      GuidanceStatus.needsDescription => 'Falta descripción',
      GuidanceStatus.noEvidence => 'Faltan datos',
      GuidanceStatus.modelUnavailable => 'Modelo no disponible',
      GuidanceStatus.failed => 'Orientación fallida',
    };
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final isYesterday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day - 1;
    final timeStr =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    if (isToday) return 'Hoy · $timeStr';
    if (isYesterday) return 'Ayer · $timeStr';
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} · $timeStr';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Historial'),
      bottom: const SystemStatusBar(mode: SystemStatusMode.offline),
    ),
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
        final allItems = snapshot.data ?? const <SavedConsultation>[];
        final pendingCount = allItems.where((c) => c.deliveryPending || c.syncStatus == 'failed').length;
        final items = onlyPending
            ? allItems.where((c) => c.deliveryPending || c.syncStatus == 'failed').toList()
            : allItems;

        return Column(
          children: [
            // Filter Chips (Wireframe C-07)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => onlyPending = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: !onlyPending ? const Color(0xFF475569) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: !onlyPending ? Colors.transparent : AppTheme.border,
                        ),
                      ),
                      child: Text(
                        'Todas',
                        style: TextStyle(
                          fontFamily: AppTheme.fontHeading,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: !onlyPending ? Colors.white : AppTheme.slate,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => setState(() => onlyPending = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: onlyPending ? const Color(0xFF475569) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: onlyPending ? Colors.transparent : AppTheme.border,
                        ),
                      ),
                      child: Text(
                        'Pendientes ($pendingCount)',
                        style: TextStyle(
                          fontFamily: AppTheme.fontHeading,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: onlyPending ? Colors.white : AppTheme.slateMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: AppMessageView(
                        icon: Icons.history,
                        title: onlyPending
                            ? 'No hay consultas pendientes'
                            : 'Sin consultas guardadas',
                        message: onlyPending
                            ? 'Todas tus consultas han sido sincronizadas.'
                            : 'Las consultas que guardes aparecerán aquí.',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        final future = load();
                        setState(() {
                          consultations = future;
                        });
                        await future;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24, top: 4),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final hasDescription = item.draft.description.trim().isNotEmpty;
                          final snippet = hasDescription
                              ? item.draft.description.trim()
                              : item.patient?.name != null
                              ? 'Consulta de ${item.patient!.name}'
                              : 'Consulta sin descripción';

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.borderLight, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
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
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header: Date/Time (Wireframe C-07)
                                    Text(
                                      _formatDate(item.createdAt),
                                      style: const TextStyle(
                                        fontFamily: AppTheme.fontHeading,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.slate,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    // Description preview
                                    Text(
                                      snippet,
                                      style: const TextStyle(
                                        fontFamily: AppTheme.fontBody,
                                        fontSize: 13.5,
                                        color: AppTheme.slateMuted,
                                        height: 1.35,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 12),
                                    // Badges row: Status pill + "Apoyo solicitado" (Wireframe C-07)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        StatusPill(
                                          label: statusLabel(item),
                                        ),
                                        if (item.draft.helpRequested) ...[
                                          const StatusPill(
                                            label: 'Apoyo solicitado',
                                            isUrgent: true,
                                            isOutlined: true,
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (item.caseStatusLabel != null) Padding(
                                      padding: const EdgeInsets.only(top: 8), child: Text(item.caseStatusLabel!),
                                    ),
                                    if (item.syncStatus != 'confirmed' && item.syncError != null) Padding(
                                      padding: const EdgeInsets.only(top: 8), child: Text(item.syncError!),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    ),
    // BottomNavigationBar matching Wireframe C-07
    bottomNavigationBar: Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderLight, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) {
            Navigator.pop(context);
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: 'Nueva consulta',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Historial / Outbox',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
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
