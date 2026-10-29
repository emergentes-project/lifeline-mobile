import '../../auth/data/remote/profile_api_service.dart';
import '../domain/repositories/case_repository.dart';

class ProfessionalVerificationAdapter
    implements ProfessionalVerificationRepository {
  const ProfessionalVerificationAdapter(this.profiles);

  final ProfileApiService profiles;

  @override
  Future<String> status(String token) async {
    final profile = await profiles.roleProfile(token, citizen: false);
    return profile['verificationStatus'] as String? ?? 'PENDING';
  }
}
