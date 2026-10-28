class PatientDraft {
  const PatientDraft({
    required this.name,
    required this.ageYears,
    this.province,
    this.locationDescription,
  });
  final String name;
  final int ageYears;
  final String? province;
  final String? locationDescription;
}
