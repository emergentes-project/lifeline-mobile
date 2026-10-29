import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/data/remote/profile_api_service.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../auth/presentation/profile_page.dart';
import '../data/case_api_service.dart';

String caseStatusLabel(String status) => switch (status) {
  'AVAILABLE' => 'Disponible',
  'ASSIGNED' => 'Asignado',
  'IN_PROGRESS' => 'En atención',
  'CLOSED' => 'Cerrado',
  _ => status,
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
  List<RemoteCase> available = [];
  List<RemoteCase> mine = [];
  final details = <String, Map<String, dynamic>>{};

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      verification = null;
    });
    final token = context.read<AuthCubit>().state.user!.token;
    final api = context.read<CaseApiService>();
    try {
      if (!widget.citizen) {
        final profile = await context.read<ProfileApiService>().roleProfile(
          token,
          citizen: false,
        );
        if (profile['verificationStatus'] != 'APPROVED') {
          if (mounted) {
            setState(
              () => verification =
                  profile['verificationStatus'] as String? ?? 'PENDING',
            );
          }
          return;
        }
      }
      final lists = widget.citizen
          ? [await api.listForCitizen(token)]
          : await Future.wait([
              api.listAvailable(token),
              api.listAssignedToMe(token),
            ]);
      if (!mounted) return;
      final all = widget.citizen ? lists.first : [...lists[0], ...lists[1]];
      final fetched = await Future.wait(
        all.map((item) async {
          try {
            return MapEntry(
              item.id,
              await api.consultation(token, item.consultationId),
            );
          } catch (_) {
            return MapEntry(item.id, <String, dynamic>{});
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        available = widget.citizen ? [] : lists[0];
        mine = widget.citizen ? lists[0] : lists[1];
        details
          ..clear()
          ..addEntries(fetched);
      });
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

  Widget list(List<RemoteCase> cases) => RefreshIndicator(
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
              final item = cases[index];
              final consultation = details[item.id] ?? {};
              final patient =
                  consultation['patient'] as Map<String, dynamic>? ?? {};
              final answer =
                  consultation['answer'] as Map<String, dynamic>? ?? {};
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(
                    patient['name'] as String? ??
                        'Caso ${item.id.substring(0, 8)}',
                  ),
                  subtitle: Text(
                    '${caseStatusLabel(item.status)} · ${caseDate(item.createdAt)}\n'
                    'Prioridad: ${answer['preliminaryPriority'] ?? 'No disponible'} · '
                    '${patient['province'] ?? patient['locationDescription'] ?? 'Ubicación no disponible'}',
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
  RemoteCase? item;
  Map<String, dynamic>? consultation;
  List<Map<String, dynamic>> history = [];

  String get token => context.read<AuthCubit>().state.user!.token;
  CaseApiService get api => context.read<CaseApiService>();

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final fresh = await api.get(token, widget.caseId);
      final values = await Future.wait([
        api.consultation(token, fresh.consultationId),
        api.history(token, widget.caseId),
      ]);
      if (!mounted) return;
      setState(() {
        item = fresh;
        consultation = values[0] as Map<String, dynamic>;
        history = values[1] as List<Map<String, dynamic>>;
      });
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

  Future<void> act(Future<RemoteCase> Function() operation) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      await operation();
      if (mounted) await load();
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
      await act(() => api.close(token, widget.caseId, observation));
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
    final current = item;
    final data = consultation ?? {};
    final patient = data['patient'] as Map<String, dynamic>? ?? {};
    final answer = data['answer'] as Map<String, dynamic>? ?? {};
    final mine = current?.assignee == context.read<AuthCubit>().state.user?.id;
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
                      row(
                        'Prioridad preliminar',
                        answer['preliminaryPriority'],
                      ),
                    ],
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      const ListTile(title: Text('Paciente y solicitud')),
                      row('Nombre', patient['name']),
                      row('Edad', patient['ageYears']),
                      row('Ubicación', patient['locationDescription']),
                      row('Provincia', patient['province']),
                      if (patient['latitude'] != null &&
                          patient['longitude'] != null)
                        row(
                          'Coordenadas',
                          '${patient['latitude']}, ${patient['longitude']}',
                        ),
                      row('Descripción', data['inputText']),
                      row(
                        'Teléfono de quien solicita ayuda',
                        data['requesterPhone'],
                      ),
                      row(
                        'Ayuda solicitada',
                        data['helpRequested'] == true ? 'Sí' : 'No',
                      ),
                      row(
                        'Foto adjunta',
                        data['hasPhoto'] == true ? 'Sí' : 'No',
                      ),
                    ],
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      const ListTile(title: Text('Orientación registrada')),
                      row('Estado', answer['guidanceStatus']),
                      row('Respuesta', answer['guidanceText']),
                      row(
                        'Ayuda profesional recomendada',
                        answer['professionalHelpRecommended'] == true
                            ? 'Sí'
                            : 'No',
                      ),
                      if (answer['sourceReferences']
                          case final List<dynamic> sources)
                        for (final source in sources)
                          row(
                            'Fuente',
                            source is Map
                                ? '${source['institution'] ?? ''}: ${source['title'] ?? ''}\n${source['url'] ?? ''}'
                                : '$source',
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
                      for (final entry in history)
                        row(
                          caseStatusLabel(entry['toStatus'] as String? ?? ''),
                          '${entry['actorType'] ?? ''} · ${entry['occurredAt'] ?? ''}',
                        ),
                    ],
                  ),
                ),
                if (!widget.citizen && !acting && current.status == 'AVAILABLE')
                  FilledButton(
                    onPressed: () => act(() => api.assign(token, current.id)),
                    child: const Text('Asumir caso'),
                  ),
                if (!widget.citizen &&
                    !acting &&
                    mine &&
                    current.status == 'ASSIGNED') ...[
                  FilledButton(
                    onPressed: () => act(
                      () => api.changeStatus(token, current.id, 'IN_PROGRESS'),
                    ),
                    child: const Text('Iniciar atención'),
                  ),
                  OutlinedButton(
                    onPressed: () => act(
                      () => api.changeStatus(token, current.id, 'AVAILABLE'),
                    ),
                    child: const Text('Liberar caso'),
                  ),
                ],
                if (!widget.citizen &&
                    !acting &&
                    mine &&
                    current.status == 'IN_PROGRESS')
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
