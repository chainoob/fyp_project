// smartmeter/lib/screens/students/student_shell.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/screens/shared/energy_goal.dart';
import 'package:smartmeter/screens/students/analytics_screen.dart';
import '../../config/theme.dart';
import 'package:smartmeter/widgets/reusable_widget.dart';
import '../shared/profile_screen.dart';
import 'appliances_screen.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _idx = 0;
  final List<Widget> _screens = [
    const StudentDashboard(),    
    const AppliancesScreen(),    
    const AnalyticsScreen(),     
    const ProfileScreen(),       
  ];

  @override
  void initState() {
    super.initState();
    final uid = context.read<AppAuthProvider>().currentUser?.uid;
    if (uid != null) {
      final now = DateTime.now();
      
      // High-Level: Synchronize data fetching hooks on layout initialization
      context.read<ApplianceProvider>().subscribeToUser(uid);
      context.read<GoalProvider>().subscribeToStudent(uid);
      context.read<EnergyProvider>().subscribeToTelemetry(uid);
      
      // Developer Expectation: Hydrate the unified energy report container cache immediately
      context.read<EnergyProvider>().loadReport(
        scope: 'Unit',
        month: now.month,
        year: now.year,
        unitId: uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens), // Kept state intact via stack compilation mapping
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (index) => setState(() => _idx = index),
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.ecoTeal.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_other_outlined),
            selectedIcon: Icon(Icons.devices_other),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class StudentDashboard extends StatelessWidget {
  const StudentDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final goalProvider = context.watch<GoalProvider>();
    final energyProvider = context.watch<EnergyProvider>();
    
    // Fixed: Point directly to the core infrastructure database report container mapping
    final report = energyProvider.currentReport;
    
    final double usedKwh = goalProvider.current;
    final List<double> liveTelemetryBuffer = energyProvider.liveReadings;

    // Fixed: Map structural metrics string conversions directly to schema sub-objects
    final String displayCost = report != null 
        ? "RM ${report.summary.totalCost.toStringAsFixed(2)}" 
        : "RM 0.00";
        
    final String displayCarbon = report != null 
        ? "${report.carbonFootprint.toStringAsFixed(1)} kg" 
        : "0.0 kg";
        
    // Dynamic Fallback Selector: Show live hardware metric calculations if historical objects are uncommitted
    final String displayLoad = liveTelemetryBuffer.isNotEmpty
        ? "${liveTelemetryBuffer.last.toStringAsFixed(2)} kW"
        : (report != null ? "${report.summary.totalConsumption.toStringAsFixed(1)} kWh" : "${usedKwh.toStringAsFixed(1)} kWh");

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppTheme.navyBlue, Color(0xFF5C6BC0)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               const Text("Current Bill Estimate", style: TextStyle(color: Colors.white70)),
               const SizedBox(height: 8),
               Text(displayCost, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
               if (report == null)
                 const Padding(
                   padding: EdgeInsets.only(top: 8),
                   child: Text("Awaiting staff bill submission...", style: TextStyle(color: Colors.white54, fontSize: 12)),
                 ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text("Real-Time Metrics", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(child: MetricTile(
                label: liveTelemetryBuffer.isNotEmpty ? "Current Load" : "AI Est. Load",
                value: displayLoad,
                icon: Icons.electric_bolt,
                color: Colors.amber
            )),
            const SizedBox(width: 16),
            Expanded(child: MetricTile(
                label: "Carbon Footprint", 
                value: displayCarbon, 
                icon: Icons.co2, 
                color: AppTheme.ecoTeal
            )),
          ],
        ),

        const SizedBox(height: 24),
        const Text("My Goal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),

        const EnergyGoalCard(title: "Monthly Budget"),
        
        const SizedBox(height: 40),
      ],
    );
  }
}