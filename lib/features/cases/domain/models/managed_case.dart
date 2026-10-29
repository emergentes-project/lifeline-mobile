enum CaseStatus { available, assigned, inProgress, closed }

enum CaseAction { assign, start, release, close }

class ManagedCase {
  const ManagedCase({
    required this.id,
    required this.consultationId,
    required this.status,
    this.assignedProfessionalUserId,
    this.observation,
    this.createdAt,
    this.closedAt,
  });

  final String id;
  final String consultationId;
  final CaseStatus status;
  final String? assignedProfessionalUserId;
  final String? observation;
  final DateTime? createdAt;
  final DateTime? closedAt;

  bool canPerform(CaseAction action, String professionalUserId) {
    final mine = assignedProfessionalUserId == professionalUserId;
    return switch (action) {
      CaseAction.assign => status == CaseStatus.available,
      CaseAction.start ||
      CaseAction.release => status == CaseStatus.assigned && mine,
      CaseAction.close => status == CaseStatus.inProgress && mine,
    };
  }
}

class CasePatient {
  const CasePatient({
    this.name,
    this.ageYears,
    this.locationDescription,
    this.province,
    this.latitude,
    this.longitude,
  });
  final String? name;
  final int? ageYears;
  final String? locationDescription;
  final String? province;
  final double? latitude;
  final double? longitude;
}

class CaseSource {
  const CaseSource({this.institution, this.title, this.url});
  final String? institution;
  final String? title;
  final String? url;
}

class CaseAnswer {
  const CaseAnswer({
    this.guidanceStatus,
    this.guidanceText,
    this.preliminaryPriority,
    this.professionalHelpRecommended,
    this.sources = const [],
  });
  final String? guidanceStatus;
  final String? guidanceText;
  final String? preliminaryPriority;
  final bool? professionalHelpRecommended;
  final List<CaseSource> sources;
}

class CaseConsultation {
  const CaseConsultation({
    this.patient,
    this.answer,
    this.inputText,
    this.requesterPhone,
    required this.helpRequested,
    required this.hasPhoto,
  });
  final CasePatient? patient;
  final CaseAnswer? answer;
  final String? inputText;
  final String? requesterPhone;
  final bool helpRequested;
  final bool hasPhoto;
}

class CaseStatusChange {
  const CaseStatusChange({
    required this.toStatus,
    this.actorType,
    this.occurredAt,
  });
  final CaseStatus toStatus;
  final String? actorType;
  final DateTime? occurredAt;
}

class CaseListItem {
  const CaseListItem(this.caseRecord, this.consultation);
  final ManagedCase caseRecord;
  final CaseConsultation? consultation;
}

class CaseLists {
  const CaseLists({required this.available, required this.mine});
  final List<CaseListItem> available;
  final List<CaseListItem> mine;
}

class CaseFilters {
  const CaseFilters({this.status, this.priority, this.province});
  final CaseStatus? status;
  final String? priority;
  final String? province;
}

class CasePage<T> {
  const CasePage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });
  final List<T> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
}

class CaseDetail {
  const CaseDetail({
    required this.caseRecord,
    required this.consultation,
    required this.history,
  });
  final ManagedCase caseRecord;
  final CaseConsultation consultation;
  final List<CaseStatusChange> history;
}
