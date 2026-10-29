class PatientDraft {
  const PatientDraft({
    required this.name,
    required this.ageYears,
    this.province,
    this.locationDescription,
    this.latitude,
    this.longitude,
    this.requesterPhone,
  });
  final String name;
  final int ageYears;
  final String? province;
  final String? locationDescription;
  final double? latitude;
  final double? longitude;
  final String? requesterPhone;
}
