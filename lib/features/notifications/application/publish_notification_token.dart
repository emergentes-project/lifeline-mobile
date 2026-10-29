import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/presentation/blocs/auth_state.dart';
import '../../consultation/domain/models/saved_consultation.dart';
import '../data/firebase_device_notifications.dart';
import 'notification_registration.dart';

Future<void> publishNotificationToken(
  BuildContext context, {
  required AuthState auth,
  Iterable<SavedConsultation> consultations = const [],
}) async {
  final registration = _provided<NotificationRegistration>(context);
  final device = _provided<FirebaseDeviceNotifications>(context);
  if (registration == null || device == null) return;
  final deviceToken = await device.currentToken();
  if (deviceToken == null || deviceToken.isEmpty) return;
  try {
    if (auth.status == AuthStatus.authenticated &&
        auth.user?.isCitizen == true) {
      await registration.registerCitizen(
        deviceToken: deviceToken,
        userId: auth.user!.id,
        accessToken: auth.user!.token,
      );
      return;
    }
    if (auth.status != AuthStatus.guest) return;
    for (final item in consultations) {
      await registration.registerGuest(
        deviceToken: deviceToken,
        helpRequested: item.draft.helpRequested,
        confirmed: item.syncStatus == 'confirmed',
        consultationId: item.backendConsultationId,
      );
    }
  } catch (_) {}
}

T? _provided<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
