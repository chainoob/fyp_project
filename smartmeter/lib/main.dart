import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Core authentication import
import 'config/theme.dart';
import 'services/energy_repo.dart';
import 'controllers/provider.dart';
import 'routes/app_router.dart';
import 'dart:developer' as developer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // High-level: Stream auth state modifications to trap active security context vectors.
 FirebaseAuth.instance.authStateChanges().listen((User? user) async {
  if (user != null) {
    final String? token = await user.getIdToken(true);
    // developer.log bypasses standard console chunking limitations completely
    developer.log('RAW_TOKEN_DATA:$token', name: 'PRODUCTION_AUTH');
    debugPrint("TARGET_UID: ${user.uid}");
  }
});

  final EnergyRepository repository = FirestoreRepository();
  final authProvider = AppAuthProvider(repository);
  final applianceProvider = ApplianceProvider(repository);
  final goalProvider = GoalProvider(repository);
  final reportProvider = ReportProvider(repository);
  final energyProvider = EnergyProvider(repository);

  final GoRouter router = AppRouter.create(authProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: applianceProvider),
        ChangeNotifierProvider.value(value: goalProvider),
        ChangeNotifierProvider.value(value: reportProvider),
        ChangeNotifierProvider.value(value: energyProvider),
      ],
      child: EnergyApp(router: router),
    ),
  );
}

class EnergyApp extends StatelessWidget {
  final GoRouter router;

  const EnergyApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SmartMeter',
      theme: AppTheme.universityDark(),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}