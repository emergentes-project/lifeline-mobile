import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/system_status_bar.dart';
import '../../../core/presentation/wireframe_components.dart';
import '../../../core/theme/app_theme.dart';
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
  CaseStatus.inProgress => 'En progreso',
  CaseStatus.closed => 'Cerrado',
};

String caseDate(DateTime? date) => date == null
    ? 'Fecha no disponible'
    : '${date.toLocal().day}/${date.toLocal().month}/${date.toLocal().year}';

String casePriorityLabel(String? priority) => switch (priority) {
  'HIGH' => 'Alta',
  'MEDIUM' => 'Media',
  'LOW' => 'Baja',
  _ => 'Media',
};

class CasesPage extends StatefulWidget {
  const CasesPage({super.key, required this.citizen});
  final bool citizen;

  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  int revision = 0;
  int currentTab = 0; // 0: Casos disponibles, 1: Mis asignaciones, 2: Historial

  @override
  Widget build(BuildContext context) {
    if (widget.citizen) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Mis casos'),
          bottom: const SystemStatusBar(mode: SystemStatusMode.connected),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => revision++),
            ),
          ],
        ),
        body: CaseListPanel(
          key: ValueKey(revision),
          citizen: true,
          assignedToMe: false,
        ),
      );
    }

    // Medical Role (Wireframe M-01, M-04, M-06)
    final titles = ['Casos disponibles', 'Mis asignaciones', 'Historial'];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(titles[currentTab]),
        bottom: const SystemStatusBar(mode: SystemStatusMode.connected),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => revision++),
          ),
          // Avatar button leading to M-07 (Mi perfil)
          IconButton(
            tooltip: 'Abrir perfil profesional',
            icon: const Icon(Icons.account_circle_outlined, size: 28),
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
              if (mounted) setState(() => revision++);
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: currentTab,
        children: [
          // Tab 0: Casos disponibles (Wireframe M-01)
          CaseListPanel(
            key: ValueKey('available-$revision'),
            citizen: false,
            assignedToMe: false,
            initialStatus: CaseStatus.available,
          ),
          // Tab 1: Mis asignaciones (Wireframe M-04)
          CaseListPanel(
            key: ValueKey('mine-$revision'),
            citizen: false,
            assignedToMe: true,
            filterOutClosed: true,
          ),
          // Tab 2: Historial de casos atendidos (Wireframe M-06)
          CaseListPanel(
            key: ValueKey('history-$revision'),
            citizen: false,
            assignedToMe: true,
            onlyClosed: true,
          ),
        ],
      ),
      // Medical Bottom Navigation Bar (Wireframe M-01, M-04, M-06)
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.borderLight, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentTab,
          onTap: (index) => setState(() => currentTab = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted_outlined),
              activeIcon: Icon(Icons.format_list_bulleted),
              label: 'Casos disponibles',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_ind_outlined),
              activeIcon: Icon(Icons.assignment_ind),
              label: 'Mis asignaciones',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Historial',
            ),
          ],
        ),
      ),
    );
  }
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

  Future<void> confirmAssignModal() async {
    // Show Wireframe M-03 Modal Bottom Sheet
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '¿Autoasignarte este caso?',
              style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.slate,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Serás responsable de su atención. Otro profesional ya no podrá tomarlo.',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                color: AppTheme.slateMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF64748B),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Sí, autoasignar'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border, width: 1.4),
                  foregroundColor: AppTheme.slate,
                ),
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await act(CaseAction.assign);
    }
  }

  Future<void> close() async {
    // Show Wireframe M-05 Modal Bottom Sheet: Cierre de caso
    var observationText = '';
    final observation = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          MediaQuery.of(sheetContext).viewInsets.bottom + 28,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Cerrar caso',
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate,
                ),
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 16),
              const Text(
                'Observaciones de la atención',
                style: TextStyle(
                  fontFamily: AppTheme.fontHeading,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => setSheetState(() => observationText = value),
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Describe la atención realizada...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF64748B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: observationText.trim().isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, observationText.trim()),
                  child: const Text('Confirmar cierre'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border, width: 1.4),
                    foregroundColor: AppTheme.slate,
                  ),
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (observation != null && mounted) {
      await act(CaseAction.close, observation: observation);
    }
  }

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

    final caseCode = widget.caseId.length > 4
        ? widget.caseId.substring(0, 4).toUpperCase()
        : widget.caseId.toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Caso #$caseCode'),
        bottom: const SystemStatusBar(mode: SystemStatusMode.connected),
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canAssign)
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF64748B),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: acting ? null : confirmAssignModal,
                          child: const Text('Autoasignar caso'),
                        ),
                      ),
                    if (canStart) ...[
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF64748B),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: acting ? null : () => act(CaseAction.start),
                          child: const Text('Iniciar atención'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: acting ? null : () => act(CaseAction.release),
                          child: const Text('Liberar caso'),
                        ),
                      ),
                    ],
                    if (canClose)
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF64748B),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: acting ? null : close,
                          child: const Text('Cerrar caso'),
                        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Status Chips Row (Wireframe M-02)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(
                      label: caseStatusLabel(current!.status),
                      isOutlined: true,
                    ),
                    if (data?.helpRequested == true)
                      const StatusPill(
                        label: 'Apoyo urgente',
                        isUrgent: true,
                      ),
                    PriorityBadge(
                      label: 'Prioridad: ${casePriorityLabel(answer?.preliminaryPriority)}',
                      priorityLevel: answer?.preliminaryPriority,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Paciente Card (Wireframe M-02)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderLight, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paciente',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${patient?.name ?? 'No registrado'} · ${patient?.ageYears ?? '??'} años',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontHeading,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Descripción Card (Wireframe M-02)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderLight, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Descripción',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data?.inputText ?? 'Sin descripción proporcionada.',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 14,
                          color: AppTheme.slate,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Fotografías Section (Wireframe M-02)
                const Text(
                  'Fotografías',
                  style: TextStyle(
                    fontFamily: AppTheme.fontHeading,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Icon(
                        data?.hasPhoto == true
                            ? Icons.image_rounded
                            : Icons.hide_image_outlined,
                        color: AppTheme.slateMuted,
                        size: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Orientación generada Card (Wireframe M-02)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderLight, width: 1.2),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: const Text(
                      'Orientación generada',
                      style: TextStyle(
                        fontFamily: AppTheme.fontHeading,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      answer?.guidanceText != null && answer!.guidanceText!.isNotEmpty
                          ? answer.guidanceText!
                          : 'Vista preliminar · indicación local',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: AppTheme.slateMuted),
                  ),
                ),
                const SizedBox(height: 14),

                // Ubicación del paciente (Map preview - Wireframe M-02)
                const Text(
                  'Ubicación del paciente',
                  style: TextStyle(
                    fontFamily: AppTheme.fontHeading,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate,
                  ),
                ),
                const SizedBox(height: 8),
                MapPreviewCard(
                  height: 140,
                  coordinatesText: patient?.latitude != null && patient?.longitude != null
                      ? 'GPS: ${patient!.latitude}, ${patient.longitude} · ${patient.province ?? patient.locationDescription ?? 'Lima'}'
                      : (patient?.province ?? patient?.locationDescription ?? 'Coordenadas capturadas por GPS'),
                ),

                if (current.observation != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderLight, width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Observación de cierre',
                          style: TextStyle(
                            fontFamily: AppTheme.fontHeading,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          current.observation!,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 13.5,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
