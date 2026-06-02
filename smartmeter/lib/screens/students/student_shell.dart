import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/screens/students/analytics_screen.dart';
import '../../config/theme.dart';
import '../shared/profile_screen.dart';
import 'appliances_screen.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _idx = 0;
  bool _isInitialized = false;

  final List<Widget> _screens = [
    const StudentDashboard(),    
    const AppliancesScreen(),    
    const AnalyticsScreen(),     
    const ProfileScreen(),       
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AppAuthProvider>().currentUser;
    if (user != null) {
      context.read<ApplianceProvider>().subscribeToUser(user.uid);
      context.read<GoalProvider>().subscribeToStudent(user.uid);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AppAuthProvider>().currentUser;
    
    if (user != null && !_isInitialized) {
      _isInitialized = true;
      final now = DateTime.now();
      
      // STRUCTURAL FIX: IoT Telemetry Removed. Proceed strictly to the identity-bound batch fetch.
      context.read<EnergyProvider>().loadReport(
        scope: 'Personal',
        month: now.month,
        year: now.year,
        unitId: user.uid,
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens), 
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

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final Color _bgDark = const Color(0xFF121212);
  final Color _cardDark = const Color(0xFF1E1E1E);
  final Color _textPrimary = Colors.white;

  void _showEditGoalDialog(BuildContext context, GoalProvider goalProvider) {
    final TextEditingController controller = TextEditingController(
      text: goalProvider.target > 0 ? goalProvider.target.toStringAsFixed(0) : "10"
    );
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
        title: Text("Edit Monthly Budget", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: _textPrimary),
          cursorColor: const Color(0xFF00E5FF),
          decoration: const InputDecoration(
            labelText: "Target Goal (kWh)",
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final double? newGoal = double.tryParse(controller.text);
              if (newGoal != null && newGoal > 0) {
                goalProvider.setGoal(newGoal);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            child: const Text("Save", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showTariffModal(BuildContext context, double currentKwh) {
    double block1 = currentKwh > 200 ? 200 : currentKwh;
    double block2 = currentKwh > 200 ? (currentKwh > 300 ? 100 : currentKwh - 200) : 0;
    double block3 = currentKwh > 300 ? (currentKwh > 600 ? 300 : currentKwh - 300) : 0;
    
    double cost1 = block1 * 0.218;
    double cost2 = block2 * 0.334;
    double cost3 = block3 * 0.516;
    double totalCost = cost1 + cost2 + cost3;

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Tariff Breakdown", style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildTariffRow("First 200 kWh (RM 0.218)", block1, cost1),
            _buildTariffRow("Next 100 kWh (RM 0.334)", block2, cost2),
            _buildTariffRow("Next 300 kWh (RM 0.516)", block3, cost3),
            const Divider(color: Colors.white24, height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Estimate", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
                Text("RM ${totalCost.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTariffRow(String label, double kwh, double cost) {
    if (kwh <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text("RM ${cost.toStringAsFixed(2)}", style: TextStyle(color: _textPrimary, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goalProvider = context.watch<GoalProvider>();
    final energyProvider = context.watch<EnergyProvider>();
    
    final report = energyProvider.currentReport;
    
    // Dynamically fold the actual usage from the AI report
    final double currentTotalKwh = report != null 
        ? report.applianceBreakdown.values.fold(0.0, (sum, value) => sum + value) 
        : 0.0;
        
    final double targetGoalKwh = goalProvider.target > 0 ? goalProvider.target : 10.0; 
    final double safePercentage = targetGoalKwh > 0 ? (currentTotalKwh / targetGoalKwh).clamp(0.0, 1.0) : 0.0;
    
    // TNB Calculation approximation
    double block1 = currentTotalKwh > 200 ? 200 : currentTotalKwh;
    double block2 = currentTotalKwh > 200 ? (currentTotalKwh > 300 ? 100 : currentTotalKwh - 200) : 0;
    double block3 = currentTotalKwh > 300 ? (currentTotalKwh > 600 ? 300 : currentTotalKwh - 300) : 0;
    final double currentBillEstimate = (block1 * 0.218) + (block2 * 0.334) + (block3 * 0.516);

    final String displayCarbon = report != null 
        ? "${report.carbonFootprint.toStringAsFixed(1)} kg" 
        : "0.0 kg";

    return Scaffold(
      backgroundColor: _bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _showTariffModal(context, currentTotalKwh),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: const Color(0xFF5C6BC0), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Current Bill Estimate", style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 8),
                      Text("RM ${currentBillEstimate.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text("Monthly Insights", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.analytics, color: energyProvider.isLoading ? Colors.white54 : const Color(0xFF00E5FF), size: 24),
                          const SizedBox(height: 12),
                          Text(report != null ? "Synced" : (energyProvider.isLoading ? "Loading" : "Pending"), style: TextStyle(color: _textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                          const Text("AI Batch Status", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("CO₂", style: TextStyle(color: AppTheme.ecoTeal, fontWeight: FontWeight.bold, fontSize: 20)),
                          const SizedBox(height: 12),
                          Text(displayCarbon, style: TextStyle(color: _textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                          const Text("Monthly Footprint", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text("My Goal", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _showEditGoalDialog(context, goalProvider),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Monthly Budget", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                            Icon(Icons.edit, color: Colors.grey, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text("${(safePercentage * 100).toStringAsFixed(0)}%", style: const TextStyle(color: AppTheme.ecoTeal, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: safePercentage,
                        backgroundColor: Colors.grey.shade200,
                        color: AppTheme.ecoTeal,
                        minHeight: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${currentTotalKwh.toStringAsFixed(1)} kWh used", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        Text("Goal: ${targetGoalKwh.toStringAsFixed(0)} kWh", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}