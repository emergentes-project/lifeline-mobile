import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/profile_page.dart';
import '../application/case_management_service.dart';
import '../domain/models/managed_case.dart';

String caseStatusLabel(CaseStatus status) => switch (status) {
  CaseStatus.available => 'Disponible',
  CaseStatus.assigned => 'Asignado',
  CaseStatus.inProgress => 'En atención',
  CaseStatus.closed => 'Cerrado',
};

String caseDate(DateTime? date) => date == null
    ? 'Fecha no disponible'
    : '${date.toLocal().day}/${date.toLocal().month}/${date.toLocal().year}';

class CasesPage extends StatefulWidget {
  const CasesPage({super.key, required this.citizen});
  final bool citizen;

  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  bool loading = true;
  String? error;
  String? verification;
  List<CaseListItem> available = [];
  List<CaseListItem> mine = [];

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      verification = null;
    });
    final token = context.read<AuthCubit>().state.user!.token;
    final service = context.read<CaseManagementService>();
    try {
      final lists = await service.loadLists(token, citizen: widget.citizen);
      if (!mounted) return;
      setState(() {
        available = lists.available;
        mine = lists.mine;
      });
    } on ProfessionalVerificationRequired catch (exception) {
      if (mounted) setState(() => verification = exception.status);
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Widget list(List<CaseListItem> cases) => RefreshIndicator(
    onRefresh: load,
    child: cases.isEmpty
        ? ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Text(
                  widget.citizen
                      ? 'Aún no tienes casos en el servidor.'
                      : 'No hay casos en esta sección.',
                ),
              ),
            ],
          )
        : ListView.builder(
            itemCount: cases.length,
            itemBuilder: (context, index) {
              final entry = cases[index];
              final item = entry.caseRecord;
              final patient = entry.consultation?.patient;
              final answer = entry.consultation?.answer;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(
                    patient?.name ?? 'Caso ${item.id.substring(0, 8)}',
                  ),
                  subtitle: Text(
                    '${caseStatusLabel(item.status)} · ${caseDate(item.createdAt)}\n'
                    'Prioridad: ${answer?.preliminaryPriority ?? 'No disponible'} · '
                    '${patient?.province ?? patient?.locationDescription ?? 'Ubicación no disponible'}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CaseDetailPage(
                          caseId: item.id,
                          citizen: widget.citizen,
                        ),
                      ),
                    );
                    if (mounted) await load();
                  },
                ),
              );
            },
          ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.citizen ? 'Mis casos' : 'Gestión de casos'),
      actions: [
        if (!widget.citizen)
          IconButton(
            tooltip: 'Mi perfil',
            icon: const Icon(Icons.person_outline),
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
              if (mounted) await load();
            },
          ),
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: load,
        ),
        if (!widget.citizen)
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthCubit>().signOut(),
          ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? _centerMessage(error!, load)
        : verification != null
        ? _centerMessage(
            'Tu perfil profesional requiere verificación para ver o gestionar casos. Estado: $verification.',
            load,
          )
        : widget.citizen
        ? list(mine)
        : DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Disponibles'),
                    Tab(text: 'Mis casos'),
                  ],
                ),
                Expanded(
                  child: TabBarView(children: [list(available), list(mine)]),
                ),
              ],
            ),
          ),
  );

  Widget _centerMessage(String text, VoidCallback retry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: retry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

class CaseDetailPage extends StatefulWidget {
  const CaseDetailPage({
    super.key,
    required this.caseId,
    required this.citizen,
  });
  final String caseId;
  final bool citizen;

  @override
  State<CaseDetailPage> createState() => _CaseDetailPageState();
}

class _CaseDetailPageState extends State<CaseDetailPage> {
  bool loading = true;
  bool acting = false;
  String? error;
  CaseDetail? detail;

  String get token => context.read<AuthCubit>().state.user!.token;
  CaseManagementService get service => context.read<CaseManagementService>();

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final fresh = await service.loadDetail(
        token,
        widget.caseId,
        citizen: widget.citizen,
      );
      if (!mounted) return;
      setState(() => detail = fresh);
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> act(CaseAction action, {String? observation}) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      final updated = await service.perform(
        token,
        context.read<AuthCubit>().state.user!.id,
        widget.caseId,
        action,
        observation: observation,
      );
      if (mounted) setState(() => detail = updated);
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$exception')));
      await load();
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> close() async {
    var observationText = '';
    final observation = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar caso'),
        content: TextField(
          onChanged: (value) => observationText = value,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Observación de atención',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (observationText.trim().isNotEmpty) {
                Navigator.pop(context, observationText.trim());
              }
            },
            child: const Text('Cerrar caso'),
          ),
        ],
      ),
    );
    if (observation != null && mounted) {
      await act(CaseAction.close, observation: observation);
    }
  }

  Widget row(String label, Object? value) => ListTile(
    title: Text(label),
    subtitle: Text(
      value == null || '$value'.trim().isEmpty ? 'No disponible' : '$value',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final current = detail?.caseRecord;
    final data = detail?.consultation;
    final patient = data?.patient;
    final answer = data?.answer;
    final mine =
        current?.assignedProfessionalUserId ==
        context.read<AuthCubit>().state.user?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del caso'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: acting ? null : load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!, textAlign: TextAlign.center),
                  FilledButton(
                    onPressed: load,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      row('Estado', caseStatusLabel(current!.status)),
                      row('Creado', caseDate(current.createdAt)),
                      if (current.closedAt != null)
                        row('Cerrado', caseDate(current.closedAt)),
                      row('Prioridad preliminar', answer?.preliminaryPriority),
                    ],
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      const ListTile(title: Text('Paciente y solicitud')),
                      row('Nombre', patient?.name),
                      row('Edad', patient?.ageYears),
                      row('Ubicación', patient?.locationDescription),
                      row('Provincia', patient?.province),
                      if (patient?.latitude != null &&
                          patient?.longitude != null)
                        row(
                          'Coordenadas',
                          '${patient!.latitude}, ${patient.longitude}',
                        ),
                      row('Descripción', data?.inputText),
                      row(
                        'Teléfono de quien solicita ayuda',
                        data?.requesterPhone,
                      ),
                      row(
                        'Ayuda solicitada',
                        data?.helpRequested == true ? 'Sí' : 'No',
                      ),
                      row('Foto adjunta', data?.hasPhoto == true ? 'Sí' : 'No'),
                    ],
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      const ListTile(title: Text('Orientación registrada')),
                      row('Estado', answer?.guidanceStatus),
                      row('Respuesta', answer?.guidanceText),
                      row(
                        'Ayuda profesional recomendada',
                        answer?.professionalHelpRecommended == true
                            ? 'Sí'
                            : 'No',
                      ),
                      for (final source in answer?.sources ?? <CaseSource>[])
                        row(
                          'Fuente',
                          '${source.institution ?? ''}: ${source.title ?? ''}\n${source.url ?? ''}',
                        ),
                    ],
                  ),
                ),
                if (current.observation != null)
                  Card(
                    child: row('Observación de cierre', current.observation),
                  ),
                Card(
                  child: Column(
                    children: [
                      const ListTile(title: Text('Historial de estados')),
                      for (final entry
                          in detail?.history ?? <CaseStatusChange>[])
                        row(
                          caseStatusLabel(entry.toStatus),
                          '${entry.actorType ?? ''} · ${caseDate(entry.occurredAt)}',
                        ),
                    ],
                  ),
                ),
                if (!widget.citizen &&
                    !acting &&
                    current.canPerform(
                      CaseAction.assign,
                      context.read<AuthCubit>().state.user!.id,
                    ))
                  FilledButton(
                    onPressed: () => act(CaseAction.assign),
                    child: const Text('Asumir caso'),
                  ),
                if (!widget.citizen &&
                    !acting &&
                    mine &&
                    current.status == CaseStatus.assigned) ...[
                  FilledButton(
                    onPressed: () => act(CaseAction.start),
                    child: const Text('Iniciar atención'),
                  ),
                  OutlinedButton(
                    onPressed: () => act(CaseAction.release),
                    child: const Text('Liberar caso'),
                  ),
                ],
                if (!widget.citizen &&
                    !acting &&
                    mine &&
                    current.status == CaseStatus.inProgress)
                  FilledButton(
                    onPressed: close,
                    child: const Text('Cerrar caso'),
                  ),
                if (acting) const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
