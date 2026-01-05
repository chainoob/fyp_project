import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/theme.dart';
import 'services/energy_repo.dart';
import 'controllers/provider.dart';
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final EnergyRepository repository = FirestoreRepository();
  final authProvider = AppAuthProvider(repository);
  final applianceProvider = ApplianceProvider(repository);
  final goalProvider = GoalProvider();

  final GoRouter router = AppRouter.create(authProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: applianceProvider),
        ChangeNotifierProvider.value(value: goalProvider),
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