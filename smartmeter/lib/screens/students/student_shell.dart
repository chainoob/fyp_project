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
  String? _subscribedUid;

  final List<Widget> _screens = [
    const StudentDashboard(),    
    const AppliancesScreen(),    
    const AnalyticsScreen(),     
    const ProfileScreen(),       
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AppAuthProvider>().currentUser;
    
    if (user != null) {
      if (_subscribedUid != user.uid) {
        _subscribedUid = user.uid;
        _isInitialized = false;
      }

      if (!_isInitialized) {
        _isInitialized = true;
        final now = DateTime.now();
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.read<EnergyProvider>().loadReport(
              scope: 'Personal',
              month: now.month,
              year: now.year,
              unitId: user.uid,
            );
          }
        });
      }
    } else {
      _subscribedUid = null;
      _isInitialized = false;
    }
  }
  
  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens), 
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (index) => setState(() => _idx = index),
        backgroundColor: Theme.of(context).colorScheme.surface,
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
  void _showEditGoalDialog(BuildContext context, GoalProvider goalProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textPrimary = isDark ? Colors.white : Colors.black87;
    final Color accentCyan = isDark ? const Color(0xFF00E5FF) : const Color(0xFF0288D1);

    final TextEditingController controller = TextEditingController(
      text: goalProvider.target > 0 ? goalProvider.target.toStringAsFixed(0) : "10"
    );
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
        title: Text("Edit Monthly Budget", style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: textPrimary),
          cursorColor: accentCyan,
          decoration: InputDecoration(
            labelText: "Target Goal (kWh)",
            labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black26)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentCyan)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () {
              final double? newGoal = double.tryParse(controller.text);
              if (newGoal != null && newGoal > 0) {
                goalProvider.setGoal(newGoal);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: accentCyan),
            child: Text("Save", style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showTariffModal(BuildContext context, double currentKwh) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textPrimary = isDark ? Colors.white : Colors.black87;
    final Color accentCyan = isDark ? const Color(0xFF00E5FF) : const Color(0xFF0288D1);

    double block1 = currentKwh > 200 ? 200 : currentKwh;
    double block2 = currentKwh > 200 ? (currentKwh > 300 ? 100 : currentKwh - 200) : 0;
    double block3 = currentKwh > 300 ? (currentKwh > 600 ? 300 : currentKwh - 300) : 0;
    
    double cost1 = block1 * 0.218;
    double cost2 = block2 * 0.334;
    double cost3 = block3 * 0.516;
    double totalCost = cost1 + cost2 + cost3;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Tariff Breakdown", style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildTariffRow("First 200 kWh (RM 0.218)", block1, cost1, textPrimary),
            _buildTariffRow("Next 100 kWh (RM 0.334)", block2, cost2, textPrimary),
            _buildTariffRow("Next 300 kWh (RM 0.516)", block3, cost3, textPrimary),
            Divider(color: isDark ? Colors.white24 : Colors.black12, height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Estimate", style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
                Text("RM ${totalCost.toStringAsFixed(2)}", style: TextStyle(color: accentCyan, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTariffRow(String label, double kwh, double cost, Color textPrimary) {
    if (kwh <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text("RM ${cost.toStringAsFixed(2)}", style: TextStyle(color: textPrimary, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goalProvider = context.watch<GoalProvider>();
    final energyProvider = context.watch<EnergyProvider>();
    
    final report = energyProvider.currentReport;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color scaffoldBg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F6F9);
    final Color cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textPrimary = isDark ? Colors.white : Colors.black87;
    final Color textLabel = isDark ? Colors.white70 : Colors.black54;
    final Color accentCyan = isDark ? const Color(0xFF00E5FF) : const Color(0xFF0288D1);

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
      backgroundColor: scaffoldBg,
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
              Text("Monthly Insights", style: TextStyle(color: textLabel, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg, 
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.analytics, color: energyProvider.isLoading ? Colors.grey : accentCyan, size: 24),
                          const SizedBox(height: 12),
                          Text(report != null ? "Synced" : (energyProvider.isLoading ? "Loading" : "Pending"), style: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("AI Batch Status", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg, 
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("CO₂", style: TextStyle(color: AppTheme.ecoTeal, fontWeight: FontWeight.bold, fontSize: 20)),
                          const SizedBox(height: 12),
                          Text(displayCarbon, style: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("Monthly Footprint", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text("My Goal", style: TextStyle(color: textLabel, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg, 
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _showEditGoalDialog(context, goalProvider),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Monthly Budget", style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                            const Icon(Icons.edit, color: Colors.grey, size: 16),
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
                        backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
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