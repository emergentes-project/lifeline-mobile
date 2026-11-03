import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/wireframe_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/blocs/auth_cubit.dart';
import '../../../core/presentation/app_message_view.dart';
import '../data/case_api_service.dart';
import '../application/case_management_service.dart';
import '../domain/models/managed_case.dart';
import 'cases_page.dart'
    show CaseDetailPage, caseStatusLabel;

class CaseListPanel extends StatefulWidget {
  const CaseListPanel({
    super.key,
    required this.citizen,
    required this.assignedToMe,
    this.initialStatus,
    this.filterOutClosed = false,
    this.onlyClosed = false,
  });
  final bool citizen;
  final bool assignedToMe;
  final CaseStatus? initialStatus;
  final bool filterOutClosed;
  final bool onlyClosed;

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
    if (widget.onlyClosed) {
      status = CaseStatus.closed;
    } else if (widget.initialStatus != null) {
      status = widget.initialStatus;
    }
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
          status: widget.onlyClosed
              ? CaseStatus.closed
              : (widget.citizen || widget.assignedToMe
                  ? status
                  : (status ?? CaseStatus.available)),
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

  String _timeAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date.toLocal());
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return '${date.toLocal().day}/${date.toLocal().month}';
  }

  @override
  Widget build(BuildContext context) {
    var items = result?.items ?? <CaseListItem>[];
    if (widget.filterOutClosed) {
      items = items.where((i) => i.caseRecord.status != CaseStatus.closed).toList();
    }

    return Column(
      children: [
        // Horizontal Filter Chips (Wireframe M-01)
        if (!widget.citizen && !widget.onlyClosed)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(null, 'Todos'),
                  const SizedBox(width: 8),
                  _filterChip(CaseStatus.available, 'Disponible'),
                  const SizedBox(width: 8),
                  _filterChip(CaseStatus.assigned, 'Asignado'),
                  const SizedBox(width: 8),
                  _filterChip(CaseStatus.inProgress, 'En progreso'),
                  if (!widget.filterOutClosed) ...[
                    const SizedBox(width: 8),
                    _filterChip(CaseStatus.closed, 'Cerrado'),
                  ],
                ],
              ),
            ),
          ),

        // Optional Quick Province & Priority Filter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: province,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => applyFilters(),
                    decoration: InputDecoration(
                      hintText: 'Filtrar por provincia...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: province.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                province.clear();
                                applyFilters();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(40, 42),
                  ),
                  onPressed: loading ? null : applyFilters,
                  child: const Text('Filtrar'),
                ),
              ),
            ],
          ),
        ),

        if (loading)
          const LinearProgressIndicator(
            semanticsLabel: 'Cargando casos',
            color: AppTheme.cyan,
          ),

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

        if (!loading && error == null && items.isEmpty)
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

        if (!loading && error == null && items.isNotEmpty)
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 20),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final entry = items[index];
                  final item = entry.caseRecord;
                  final patient = entry.consultation?.patient;
                  final isUrgent = entry.consultation?.helpRequested == true;
                  final caseShortId = item.id.length > 4
                      ? item.id.substring(0, 4).toUpperCase()
                      : item.id.toUpperCase();

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
                            builder: (_) => CaseDetailPage(
                              caseId: item.id,
                              citizen: widget.citizen,
                            ),
                          ),
                        );
                        if (mounted) await load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Row: Status pill + Urgency pill + Time ago / ID (Wireframe M-01)
                            Row(
                              children: [
                                StatusPill(
                                  label: caseStatusLabel(item.status),
                                  isOutlined: item.status == CaseStatus.available,
                                ),
                                if (isUrgent) ...[
                                  const SizedBox(width: 8),
                                  const StatusPill(
                                    label: 'Apoyo urgente',
                                    isUrgent: true,
                                  ),
                                ],
                                const Spacer(),
                                if (item.status == CaseStatus.closed)
                                  Text(
                                    '#$caseShortId',
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontHeading,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slateMuted,
                                    ),
                                  )
                                else
                                  Text(
                                    _timeAgo(item.createdAt),
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontBody,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Patient Name · Age (Wireframe M-01)
                            Text(
                              patient != null
                                  ? 'Paciente · ${patient.ageYears ?? 0} años (${patient.name})'
                                  : 'Caso #$caseShortId',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontHeading,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slate,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Description snippet or Observation snippet
                            if (item.status == CaseStatus.closed && item.observation != null)
                              Text(
                                'Observaciones: ${item.observation!}',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 13,
                                  color: AppTheme.slateMuted,
                                  height: 1.35,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            else
                              Text(
                                entry.consultation?.inputText ??
                                    'Sin descripción del incidente.',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 13,
                                  color: AppTheme.slateMuted,
                                  height: 1.35,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),

                            const SizedBox(height: 10),

                            // Location Row with Pin Icon (Wireframe M-01)
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: AppTheme.slateMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  patient?.province ??
                                      patient?.locationDescription ??
                                      'Lima',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 12.5,
                                    color: AppTheme.slateMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: AppTheme.slateMuted,
                                ),
                              ],
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

        // Pagination row
        if (!loading && error == null && result != null && result!.totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                Text(
                  '${result!.page + 1} de ${result!.totalPages}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontHeading,
                    fontWeight: FontWeight.w600,
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

  Widget _filterChip(CaseStatus? chipStatus, String label) {
    final isSelected = status == chipStatus;
    return GestureDetector(
      onTap: () {
        setState(() => status = chipStatus);
        applyFilters();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF475569) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppTheme.border,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontHeading,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppTheme.slate,
          ),
        ),
      ),
    );
  }
}
