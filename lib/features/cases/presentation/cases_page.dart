import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/profile_page.dart';
import '../application/case_management_service.dart';
import '../domain/models/managed_case.dart';
import 'case_list_panel.dart';
import '../../../core/presentation/app_message_view.dart';
import '../data/case_api_service.dart';

String caseStatusLabel(CaseStatus status) => switch (status) {
  CaseStatus.available => 'Disponible',
  CaseStatus.assigned => 'Asignado',
  CaseStatus.inProgress => 'En atención',
  CaseStatus.closed => 'Cerrado',
};

String caseDate(DateTime? date) => date == null
    ? 'Fecha no disponible'
    : '${date.toLocal().day}/${date.toLocal().month}/${date.toLocal().year}';

String casePriorityLabel(String? priority) => switch (priority) {
  'HIGH' => 'Alta',
  'MEDIUM' => 'Media',
  'LOW' => 'Baja',
  _ => 'No disponible',
};

enum _CasesMenuAction { profile, signOut }

class CasesPage extends StatefulWidget {
  const CasesPage({super.key, required this.citizen});
  final bool citizen;

  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.citizen ? 'Mis casos' : 'Gestión de casos'),
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() => revision++),
        ),
        if (!widget.citizen)
          PopupMenuButton<_CasesMenuAction>(
            tooltip: 'Abrir menú de cuenta',
            icon: const Icon(Icons.menu),
            onSelected: (action) async {
              if (action == _CasesMenuAction.profile) {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
                if (mounted) setState(() => revision++);
              } else {
                await context.read<AuthCubit>().signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _CasesMenuAction.profile,
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Mi perfil'),
                ),
              ),
              PopupMenuItem(
                value: _CasesMenuAction.signOut,
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
      ],
    ),
    body: widget.citizen
        ? CaseListPanel(
            key: ValueKey(revision),
            citizen: true,
            assignedToMe: false,
          )
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
                  child: TabBarView(
                    children: [
                      CaseListPanel(
                        key: ValueKey('available-$revision'),
                        citizen: false,
                        assignedToMe: false,
                      ),
                      CaseListPanel(
                        key: ValueKey('mine-$revision'),
                        citizen: false,
                        assignedToMe: true,
                      ),
                    ],
                  ),
                ),
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
    } on ProfessionalVerificationRequired catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } on CaseApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo cargar el caso. Inténtalo de nuevo.',
        );
      }
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
      final message =
          exception is CaseApiException ||
              exception is CaseTransitionUnavailable ||
              exception is ProfessionalVerificationRequired
          ? '$exception'
          : 'No se pudo completar la acción. Inténtalo de nuevo.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await load();
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> close() async {
    var observationText = '';
    final observation = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cerrar caso'),
          content: TextField(
            onChanged: (value) => setDialogState(() => observationText = value),
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Observación de atención',
              helperText: 'Resume la atención brindada.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: observationText.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, observationText.trim()),
              child: const Text('Cerrar caso'),
            ),
          ],
        ),
      ),
    );
    if (observation != null && mounted) {
      await act(CaseAction.close, observation: observation);
    }
  }

  Widget row(String label, Object? value) => ListTile(
    title: Text(label),
    subtitle: SelectableText(
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
    final canAssign =
        current?.canPerform(
          CaseAction.assign,
          context.read<AuthCubit>().state.user?.id ?? '',
        ) ==
        true;
    final canStart = mine && current?.status == CaseStatus.assigned;
    final canClose = mine && current?.status == CaseStatus.inProgress;
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
      bottomNavigationBar:
          !widget.citizen &&
              !loading &&
              error == null &&
              (canAssign || canStart || canClose)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canAssign)
                      FilledButton(
                        onPressed: acting ? null : () => act(CaseAction.assign),
                        child: const Text('Asumir caso'),
                      ),
                    if (canStart) ...[
                      FilledButton(
                        onPressed: acting ? null : () => act(CaseAction.start),
                        child: const Text('Iniciar atención'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: acting
                            ? null
                            : () => act(CaseAction.release),
                        child: const Text('Liberar caso'),
                      ),
                    ],
                    if (canClose)
                      FilledButton(
                        onPressed: acting ? null : close,
                        child: const Text('Cerrar caso'),
                      ),
                    if (acting)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(
                          semanticsLabel: 'Actualizando caso',
                        ),
                      ),
                  ],
                ),
              ),
            )
          : null,
      body: loading
          ? const Center(
              child: CircularProgressIndicator(semanticsLabel: 'Cargando caso'),
            )
          : error != null
          ? AppMessageView(
              icon: Icons.error_outline,
              title: 'No se pudo abrir el caso',
              message: error!,
              actionLabel: 'Reintentar',
              onAction: load,
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
                      row(
                        'Prioridad preliminar',
                        casePriorityLabel(answer?.preliminaryPriority),
                      ),
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
              ],
            ),
    );
  }
}
