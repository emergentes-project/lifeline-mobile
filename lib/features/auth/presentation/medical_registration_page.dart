import 'package:flutter/material.dart';
import 'registration_page.dart';

class MedicalRegistrationPage extends StatelessWidget {
  const MedicalRegistrationPage({super.key});
  @override
  Widget build(BuildContext context) => const RegistrationPage(medical: true);
}
