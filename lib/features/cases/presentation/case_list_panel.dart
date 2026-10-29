import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../../core/presentation/app_message_view.dart';
import '../data/case_api_service.dart';
import '../application/case_management_service.dart';
import '../domain/models/managed_case.dart';
import 'cases_page.dart'
    show CaseDetailPage, caseDate, caseStatusLabel, casePriorityLabel;

class CaseListPanel extends StatefulWidget {
  const CaseListPanel({
    super.key,
    required this.citizen,
    required this.assignedToMe,
  });
  final bool citizen;
  final bool assignedToMe;

  @override
  State<CaseListPanel> createState() => _CaseListPanelState();
}

class _CaseListPanelState extends State<CaseListPanel> {
  final province = TextEditingController();
  CaseStatus? status;
  String? priority;
  int page = 0;
  CasePage<CaseListItem>? result;
  String? error;
  bool verificationRequired = false;
  bool loading = true;
  int requestVersion = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    province.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final version = ++requestVersion;
    setState(() {
      loading = true;
      error = null;
      verificationRequired = false;
    });
    try {
      final token = context.read<AuthCubit>().state.user!.token;
      final data = await context.read<CaseManagementService>().loadPage(
        token,
        citizen: widget.citizen,
        assignedToMe: widget.assignedToMe,
        filters: CaseFilters(
          status: widget.citizen || widget.assignedToMe
              ? status
              : CaseStatus.available,
          priority: priority,
          province: province.text,
        ),
        page: page,
      );
      if (!mounted || version != requestVersion) return;
      if (data.items.isEmpty && page > 0 && page >= data.totalPages) {
        page = data.totalPages == 0 ? 0 : data.totalPages - 1;
        await load();
        return;
      }
      setState(() => result = data);
    } on ProfessionalVerificationRequired catch (e) {
      if (mounted && version == requestVersion) {
        setState(() {
          error = '$e';
          verificationRequired = true;
        });
      }
    } on CaseApiException catch (e) {
      if (mounted && version == requestVersion) {
        setState(() => error = e.message);
      }
    } catch (_) {
      if (mounted && version == requestVersion) {
        setState(
          () => error = 'No se pudieron cargar los casos. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted && version == requestVersion) setState(() => loading = false);
    }
  }

  void applyFilters() {
    page = 0;
    load();
  }

  Widget statusBadge(CaseStatus value) {
    final (background, foreground) = switch (value) {
      CaseStatus.available => (
        const Color(0xFFE5F4FA),
        const Color(0xFF07506C),
      ),
      CaseStatus.assigned => (const Color(0xFFFFF0CC), const Color(0xFF755000)),
      CaseStatus.inProgress => (
        const Color(0xFFDDF3EC),
        const Color(0xFF075C47),
      ),
      CaseStatus.closed => (const Color(0xFFE9EDF2), const Color(0xFF344054)),
    };
    return Semantics(
      label: 'Estado: ${caseStatusLabel(value)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ExcludeSemantics(
          child: Text(
            caseStatusLabel(value),
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExpansionTile(
        title: const Text('Filtros'),
        subtitle: Text(
          widget.citizen || widget.assignedToMe
              ? 'Estado, prioridad y provincia'
              : 'Prioridad y provincia',
        ),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (widget.citizen || widget.assignedToMe)
            DropdownButtonFormField<CaseStatus?>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [
                const DropdownMenuItem<CaseStatus?>(
                  value: null,
                  child: Text('Todos'),
                ),
                for (final value in CaseStatus.values)
                  DropdownMenuItem<CaseStatus?>(
                    value: value,
                    child: Text(caseStatusLabel(value)),
                  ),
              ],
              onChanged: (value) => setState(() => status = value),
            ),
          DropdownButtonFormField<String?>(
            initialValue: priority,
            decoration: const InputDecoration(
              labelText: 'Prioridad preliminar',
            ),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Todas')),
              DropdownMenuItem<String?>(value: 'HIGH', child: Text('Alta')),
              DropdownMenuItem<String?>(value: 'MEDIUM', child: Text('Media')),
              DropdownMenuItem<String?>(value: 'LOW', child: Text('Baja')),
            ],
            onChanged: (value) => setState(() => priority = value),
          ),
          TextField(
            controller: province,
            decoration: const InputDecoration(labelText: 'Provincia'),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => applyFilters(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: loading ? null : applyFilters,
              child: const Text('Aplicar filtros'),
            ),
          ),
        ],
      ),
      if (loading)
        const LinearProgressIndicator(semanticsLabel: 'Cargando casos'),
      if (error != null)
        Expanded(
          child: AppMessageView(
            icon: verificationRequired
                ? Icons.verified_user_outlined
                : Icons.wifi_off_outlined,
            title: verificationRequired
                ? 'Habilitación profesional pendiente'
                : 'No se pudo mostrar la lista',
            message: error!,
            actionLabel: 'Reintentar',
            onAction: load,
          ),
        ),
      if (!loading && error == null && result?.items.isEmpty == true)
        Expanded(
          child: AppMessageView(
            icon: Icons.inbox_outlined,
            title: widget.citizen
                ? 'Aún no tienes casos'
                : widget.assignedToMe
                ? 'No hay casos en tu lista'
                : 'No hay casos disponibles',
            message: 'Prueba con otros filtros o actualiza la lista.',
            actionLabel: 'Actualizar',
            onAction: load,
          ),
        ),
      if (!loading && error == null && result?.items.isNotEmpty == true)
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: result?.items.length ?? 0,
              itemBuilder: (context, index) {
                final entry = result!.items[index];
                final item = entry.caseRecord;
                final patient = entry.consultation?.patient;
                final answer = entry.consultation?.answer;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      patient?.name ?? 'Caso ${item.id.substring(0, 8)}',
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          statusBadge(item.status),
                          const SizedBox(height: 6),
                          Text(
                            'Prioridad ${casePriorityLabel(answer?.preliminaryPriority)} · ${caseDate(item.createdAt)}',
                          ),
                          Text(
                            patient?.province ??
                                patient?.locationDescription ??
                                'Ubicación no disponible',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
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
          ),
        ),
      if (!loading && error == null && result != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Página anterior',
                onPressed: page > 0
                    ? () {
                        page--;
                        load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  'Página ${result!.page + 1} de ${result!.totalPages == 0 ? 1 : result!.totalPages} · ${result!.totalElements} casos',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Página siguiente',
                onPressed: page + 1 < result!.totalPages
                    ? () {
                        page++;
                        load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
    ],
  );
}
