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

// --- 1. STAFF DASHBOARD ---
class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  // --- LOGIC: SHOW ADD BILL DIALOG ---
  void _showAddBillDialog(BuildContext context) {
    final kwhController = TextEditingController();
    final costController = TextEditingController();

    // Local state for UI selection
    String? selectedBlockId;
    String? selectedUnitId;
    bool localLoading = false;

    // Roadmap Item 4: Implement dynamic block/unit fetching from Firestore collection groups.
    final List<String> demoBlocks = ['Block A', 'Block B', 'Block C'];
    final List<String> demoUnits = ['Unit 101', 'Unit 102', 'Unit 201', 'Unit 205'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Upload Monthly Bill"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Select the target Block/Unit and enter total consumption. Data will be used for AI Disaggregation.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // Block Selector: UI context for targeted disaggregation.
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: "Block",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.apartment),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    value: selectedBlockId,
                    items: demoBlocks.map((b) => DropdownMenuItem(
                      value: b,
                      child: Text(b),
                    )).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedBlockId = val;
                        // Roadmap Item 4: Integrate reactive unit filtering based on block selection.
                        selectedUnitId = null; 
                      });
                    },
                    validator: (v) => v == null ? "Required" : null,
                  ),
                  const SizedBox(height: 16),

                  // Unit Selector: Granular target for FHMM execution.
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: "Unit",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.door_front_door),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    value: selectedUnitId,
                    items: demoUnits.map((u) => DropdownMenuItem(
                      value: u,
                      child: Text(u),
                    )).toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedUnitId = val);
                    },
                    // Disable if no block selected
                    hint: const Text("Select Unit"),
                    disabledHint: const Text("Select Block First"),
                  ),
                  const SizedBox(height: 16),

                  // Consumption Inputs: Telemetry seed for disaggregation.
                  TextField(
                    controller: kwhController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Total Consumption (kWh)",
                      suffixText: "kWh",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.flash_on),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: costController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Total Cost (RM)",
                      prefixText: "RM ",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: localLoading
                    ? null
                    : () async {
                        // Basic UI Validation
                        if (selectedBlockId == null || selectedUnitId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please select a Block and Unit"), backgroundColor: Colors.red),
                          );
                          return;
                        }
                        if (kwhController.text.isEmpty || costController.text.isEmpty) return;

                        setDialogState(() => localLoading = true);

                        // Simulate network delay
                        await Future.delayed(const Duration(seconds: 1));

                        // Roadmap Item 4: Implement Cloud Function trigger via triggerDisaggregation() repo call.
                        // Finalize payload mapping (kwh, month, year) before production release.

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("UI Test: Analysis for $selectedUnitId Triggered (Logic Pending)"),
                              backgroundColor: AppTheme.ecoTeal,
                            )
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.ecoTeal, foregroundColor: Colors.white),
                child: localLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text("Analyze Bill"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Roadmap Item 4: Bind campusLoadKw and dailyTotalKwh to the global telemetry stream.
    final double campusLoadKw = 0.0;
    final double dailyTotalKwh = 0.0;
    // --------------------------------

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // A. Real-Time Monitor
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
                        color: campusLoadKw > 0 ? Colors.redAccent.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: campusLoadKw > 0 ? Colors.redAccent.withValues(alpha: 0.5) : Colors.grey)),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: campusLoadKw > 0 ? Colors.redAccent : Colors.grey),
                        const SizedBox(width: 6),
                        Text(campusLoadKw > 0 ? "LIVE" : "OFFLINE",
                            style: TextStyle(color: campusLoadKw > 0 ? Colors.redAccent : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Text("${campusLoadKw.toStringAsFixed(1)} kW",
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.history, color: Colors.white54, size: 16),
                  const SizedBox(width: 4),
                  Text("Total Today: ${dailyTotalKwh.toStringAsFixed(0)} kWh", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text("Energy Plan & Alerts", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 12),

        // Energy Goal Card
        const EnergyGoalCard(title: "Campus Monthly Plan"),

        // --- UPLOAD BILL CARD ---
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _showAddBillDialog(context),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long, color: Colors.orange),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Upload Monthly Bill", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("Trigger AI analysis for Block/Unit", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        // -----------------------------

        const SizedBox(height: 24),
        const Text("Infrastructure", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 12),

        // Manage Blocks
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