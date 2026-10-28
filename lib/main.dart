import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'app/app.dart';
import 'features/auth/data/local/secure_session_storage.dart';
import 'features/auth/data/remote/auth_api_service.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/blocs/auth_cubit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = AuthRepositoryImpl(
    api: AuthApiService(http.Client()),
    sessions: SecureSessionStorage(const FlutterSecureStorage()),
  );
  runApp(
    BlocProvider(
      create: (_) => AuthCubit(repository)..restore(),
      child: const LifelineApp(),
    ),
  );
}
