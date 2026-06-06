import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/theme.dart';
import 'firebase_options.dart';
import 'services/energy_repo.dart';
import 'controllers/provider.dart';
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF121212),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("FATAL EXCEPTION", style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(details.exceptionAsString(), style: const TextStyle(color: Colors.yellowAccent, fontSize: 14)),
              const SizedBox(height: 12),
              Text(details.stack?.toString() ?? "No stack trace", style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  };

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
