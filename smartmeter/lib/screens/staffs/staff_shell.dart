// smartmeter/lib/screens/staffs/staff_shell.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/screens/shared/energy_goal.dart';
import 'package:smartmeter/screens/staffs/manage_block.dart';
import 'package:smartmeter/screens/staffs/verification_screen.dart';
import 'package:smartmeter/screens/staffs/manage_report.dart';
import '../../config/theme.dart';
import '../shared/profile_screen.dart';

class StaffShell extends StatefulWidget {
  const StaffShell({super.key});
  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  int _idx = 0;

  final _pages = const [
    StaffDashboard(),
    VerificationScreen(),
    StaffReportsPage(),
    ProfileScreen()
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ApplianceProvider>().subscribeToQueue();
      context.read<GoalProvider>().subscribeToCampus();
      context.read<EnergyProvider>().subscribeToTelemetry('campus');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _idx == 3
          ? null
          : AppBar(
              title: Text(
                ['Campus Overview', 'Verification Queue', 'Reports'][_idx],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              centerTitle: false,
              backgroundColor: Colors.white,
              elevation: 0,
              titleTextStyle: const TextStyle(color: AppTheme.navyBlue, fontSize: 20, fontWeight: FontWeight.bold),
              iconTheme: const IconThemeData(color: AppTheme.navyBlue),
            ),
      body: IndexedStack(
        index: _idx,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: Colors.white,
        elevation: 3,
        indicatorColor: AppTheme.ecoTeal.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined), 
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: 'Campus'
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_add_check), 
            label: 'Verify'
          ),
          NavigationDestination(
            icon: Icon(Icons.assessment_outlined), 
            selectedIcon: Icon(Icons.assessment),
            label: 'Reports'
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline), 
            selectedIcon: Icon(Icons.person),
            label: 'Profile'
          ),
        ],
      ),
    );
  }
}

class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final energyProvider = context.watch<EnergyProvider>();
    final List<double> aggregateReadings = energyProvider.liveReadings;
    
    final double campusLoadKw = aggregateReadings.isNotEmpty ? aggregateReadings.last / 1000.0 : 0.0;
    final bool isLive = energyProvider.isConnected;

    final goalProvider = context.watch<GoalProvider>();
    final double totalUsageKwh = goalProvider.current;

    final Map<String, double> breakdown = energyProvider.applianceBreakdown;
    final List<String> anomalies = energyProvider.currentMlReport?.data.anomalies ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF263238), Color(0xFF37474F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Real-Time Campus Load", style: TextStyle(color: Colors.white70)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: isLive ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isLive ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.grey)),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: isLive ? Colors.greenAccent : Colors.grey),
                        const SizedBox(width: 6),
                        Text(isLive ? "IoT ONLINE" : "OFFLINE",
                            style: TextStyle(color: isLive ? Colors.greenAccent : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Text("${campusLoadKw.toStringAsFixed(2)} kW",
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.history, color: Colors.white54, size: 16),
                  const SizedBox(width: 4),
                  Text("Total Accumulated: ${totalUsageKwh.toStringAsFixed(0)} kWh", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),

        if (anomalies.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text("Recent System Alerts", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ],
          ),
          const SizedBox(height: 12),
          ...anomalies.map((a) => _AnomalyTile(message: a)),
        ],

        if (breakdown.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text("Detected Appliance Profiles", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 12),
          ...breakdown.entries.map((e) => _ApplianceUsageTile(name: e.key, value: e.value)),
        ],

        const SizedBox(height: 24),
        const Text("Energy Plan & Alerts", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 12),

        const EnergyGoalCard(title: "Campus Monthly Plan"),

        const SizedBox(height: 24),
        const Text("Infrastructure", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 12),

        Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ManageBlocksScreen()), 
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.navyBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.apartment, color: AppTheme.navyBlue),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Manage Blocks & Rooms", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("Configure dormitory layout", style: TextStyle(color: Colors.black, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _AnomalyTile extends StatelessWidget {
  final String message;
  const _AnomalyTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.orange, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Anomaly: High-load unregistered $message detected.",
              style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplianceUsageTile extends StatelessWidget {
  final String name;
  final double value;

  const _ApplianceUsageTile({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_getIconForAppliance(name), color: AppTheme.ecoTeal),
            const SizedBox(width: 16),
            Expanded(
              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text("${value.toStringAsFixed(3)} kWh", 
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navyBlue)),
          ],
        ),
      ),
    );
  }

  IconData _getIconForAppliance(String name) {
    switch (name.toLowerCase()) {
      case 'fan': return Icons.air;
      case 'light': return Icons.lightbulb_outline;
      case 'kettle': return Icons.coffee;
      case 'laptop': return Icons.laptop;
      default: return Icons.electrical_services;
    }
  }
}