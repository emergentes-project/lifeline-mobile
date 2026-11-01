class CaseNoticeDestination {
  const CaseNoticeDestination._(this.caseId);
  const CaseNoticeDestination.history() : this._(null);
  const CaseNoticeDestination.detail(String caseId) : this._(caseId);

  final String? caseId;
}

Future<CaseNoticeDestination> destinationForCaseNotice({
  required bool citizenSignedIn,
  required String? caseId,
  required Future<void> Function(String caseId) loadCase,
}) async {
  final id = caseId?.trim() ?? '';
  if (!citizenSignedIn || id.isEmpty) {
    return const CaseNoticeDestination.history();
  }
  try {
    await loadCase(id);
  } catch (_) {
    return const CaseNoticeDestination.history();
  }
  return CaseNoticeDestination.detail(id);
}
