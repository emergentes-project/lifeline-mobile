import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'app/app.dart';
import 'features/auth/data/local/secure_session_storage.dart';
import 'features/auth/data/remote/auth_api_service.dart';
import 'features/auth/data/remote/profile_api_service.dart';
import 'features/cases/data/case_api_service.dart';
import 'features/cases/data/professional_verification_adapter.dart';
import 'features/cases/application/case_management_service.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/blocs/auth_cubit.dart';
import 'features/consultation/application/consultation_sync_service.dart';
import 'features/consultation/data/ai/gemma4_on_device_inference.dart';
import 'features/consultation/data/local/local_consultation_repository.dart';
import 'features/medical_bases/data/index/local_medical_knowledge_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final medicalKnowledge = LocalMedicalKnowledgeRepository();
  try {
    await medicalKnowledge.load();
  } catch (error) {
    debugPrint('No se pudo instalar el conocimiento médico local: $error');
  }
  final repository = AuthRepositoryImpl(
    api: AuthApiService(http.Client()),
    sessions: SecureSessionStorage(const FlutterSecureStorage()),
  );
  final profileApi = ProfileApiService(http.Client());
  final caseApi = CaseApiService(http.Client());
  final caseManagement = CaseManagementService(
    cases: caseApi,
    verification: ProfessionalVerificationAdapter(profileApi),
  );
  final consultations = LocalConsultationRepository();
  final consultationSync = ConsultationSyncService(
    repository: consultations,
    client: http.Client(),
  );
  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<LocalMedicalKnowledgeRepository>.value(
          value: medicalKnowledge,
        ),
        RepositoryProvider<Gemma4OnDeviceInference>.value(
          value: Gemma4OnDeviceInference(),
        ),
        RepositoryProvider<LocalConsultationRepository>.value(
          value: consultations,
        ),
        RepositoryProvider<ConsultationSyncService>.value(
          value: consultationSync,
        ),
        RepositoryProvider<ProfileApiService>.value(value: profileApi),
        RepositoryProvider<CaseApiService>.value(value: caseApi),
        RepositoryProvider<CaseManagementService>.value(value: caseManagement),
      ],
      child: BlocProvider(
        create: (_) => AuthCubit(repository)..restore(),
        child: const LifelineApp(),
      ),
    ),
  );
}
