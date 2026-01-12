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
      context.read<ApplianceProvider>().subscribeToUser(uid);
      context.read<GoalProvider>().subscribeToStudent(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_idx],
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
    // Data Access
    final usedKwh = context.select<GoalProvider, double>((p) => p.current);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bill Estimate Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppTheme.navyBlue, Color(0xFF5C6BC0)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text("Current Bill Estimate", style: TextStyle(color: Colors.white70)),
               SizedBox(height: 8),
               Text("RM 0.00", style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
               // Additional bill details...
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text("Real-Time Metrics", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),

        // Metrics
        Row(
          children: [
            Expanded(child: MetricTile(
                label: "Current Load",
                value: "${usedKwh.toStringAsFixed(1)} kWh",
                icon: Icons.electric_bolt,
                color: Colors.amber
            )),
            const SizedBox(width: 16),
            const Expanded(child: MetricTile(label: "Carbon Footprint", value: "0 kg", icon: Icons.co2, color: AppTheme.ecoTeal)),
          ],
        ),

        const SizedBox(height: 24),
        const Text("My Goal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),

        // Energy Goal Widget
        const EnergyGoalCard(title: "Monthly Budget"),
        
        const SizedBox(height: 40),
      ],
    );
  }
}