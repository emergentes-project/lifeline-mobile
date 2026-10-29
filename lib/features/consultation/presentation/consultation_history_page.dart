import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../medical_bases/data/index/local_medical_knowledge_repository.dart';
import '../data/local/local_consultation_repository.dart';
import '../domain/models/consultation_guidance.dart';
import '../domain/models/saved_consultation.dart';
import 'patient_fields_page.dart';

class ConsultationHistoryPage extends StatefulWidget {
  const ConsultationHistoryPage({super.key});

  @override
  State<ConsultationHistoryPage> createState() =>
      _ConsultationHistoryPageState();
}

class _ConsultationHistoryPageState extends State<ConsultationHistoryPage> {
  late Future<List<SavedConsultation>> consultations;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    consultations = context.read<LocalConsultationRepository>().list(
      knowledge: context.read<LocalMedicalKnowledgeRepository>(),
    );
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Consultas guardadas')),
    body: FutureBuilder<List<SavedConsultation>>(
      future: consultations,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton(
              onPressed: () => setState(refresh),
              child: const Text('No se pudo cargar. Reintentar'),
            ),
          );
        }
        final items = snapshot.data ?? const <SavedConsultation>[];
        if (items.isEmpty) {
          return const Center(
            child: Text('Todavía no hay consultas guardadas.'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(refresh);
            await consultations;
          },
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(item.patient.name),
                  subtitle: Text(
                    '${item.createdAt.toLocal().day}/${item.createdAt.toLocal().month}/${item.createdAt.toLocal().year} · '
                    '${statusLabel(item)} · ${priorityLabel(item.guidance?.preliminaryPriority)}\n'
                    '${item.draft.description.isEmpty ? 'Sin descripción' : item.draft.description}',
                    maxLines: 3,
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
                        ),
                      ),
                    );
                    if (context.mounted) setState(refresh);
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
