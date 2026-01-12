import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/screens/shared/energy_goal.dart';
import 'package:smartmeter/screens/staffs/manage_block.dart';
import 'package:smartmeter/screens/staffs/verification_screen.dart';
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

// --- 1. STAFF DASHBOARD (UPDATED) ---
class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // --- TODO: INTEGRATION POINTS ---
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
                  offset: const Offset(0, 4)
              )
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
                        border: Border.all(color: campusLoadKw > 0 ? Colors.redAccent.withValues(alpha: 0.5) : Colors.grey)
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: campusLoadKw > 0 ? Colors.redAccent : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                            campusLoadKw > 0 ? "LIVE" : "OFFLINE",
                            style: TextStyle(color: campusLoadKw > 0 ? Colors.redAccent : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)
                        ),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  "${campusLoadKw.toStringAsFixed(1)} kW",
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)
              ),
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
        const Text("Energy Plan & Alerts", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),

        // Energy Goal Card 
        const EnergyGoalCard(title: "Campus Monthly Plan"),

        const SizedBox(height: 24),
        const Text("Infrastructure", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),

        // Manage Blocks (
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
                        Text("Manage Blocks & Rooms", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("Configure dormitory layout", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
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

// --- 2. REPORTS PAGE ---
class StaffReportsPage extends StatefulWidget {
  const StaffReportsPage({super.key});

  @override
  State<StaffReportsPage> createState() => _StaffReportsPageState();
}

class _StaffReportsPageState extends State<StaffReportsPage> {
  // --- SELECTION STATE ---
  String _selectedScope = 'Campus'; 
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String? _selectedBlockId;
  String? _selectedUnitId;

  // --- DATA VARIABLES (To be populated by Backend) ---
  // TODO: Fetch these lists from Firestore
  List<Map<String, dynamic>> _availableBlocks = []; 
  List<Map<String, dynamic>> _availableUnits = []; 
  List<Map<String, dynamic>> _reportHistory = [];

  final List<String> _scopes = ['Campus', 'Block', 'Unit'];
  final List<int> _months = List.generate(12, (index) => index + 1);
  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    // -------------------------------------------------------------------------
    // TODO: BACKEND INTEGRATION
    // -------------------------------------------------------------------------
    // 1. Fetch available Blocks/Units based on permissions
    // 2. Fetch Report History
    // -------------------------------------------------------------------------
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark Background
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. REPORT CONFIGURATION CARD
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface, // Using dark surface color
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Report Parameters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 20),
                
                // A. SCOPE SELECTOR
                DropdownButtonFormField<String>(
                  initialValue: _selectedScope,
                  decoration: _inputDecor("Report Scope", Icons.radar),
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: Colors.white),
                  items: _scopes.map((s) => DropdownMenuItem(
                    value: s, 
                    child: Text("$s Level Report", style: const TextStyle(color: Colors.white))
                  )).toList(),
                  onChanged: (val) => setState(() {
                    _selectedScope = val!;
                    _selectedBlockId = null;
                    _selectedUnitId = null;
                  }),
                ),
                const SizedBox(height: 16),

                // B. CONDITIONAL DROPDOWNS (Dynamic Data)
                if (_selectedScope == 'Block' || _selectedScope == 'Unit') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedBlockId,
                    decoration: _inputDecor("Select Block", Icons.apartment),
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: Colors.white),
                    items: _availableBlocks.map((b) => DropdownMenuItem(
                      value: b['id'] as String, 
                      child: Text(b['name'] as String, style: const TextStyle(color: Colors.white))
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedBlockId = val),
                    hint: const Text("Choose a block...", style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_selectedScope == 'Unit') ...[
                   DropdownButtonFormField<String>(
                    initialValue: _selectedUnitId,
                    decoration: _inputDecor("Select Unit", Icons.holiday_village),
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: Colors.white),
                    items: _availableUnits.map((u) => DropdownMenuItem(
                      value: u['id'] as String, 
                      child: Text(u['name'] as String, style: const TextStyle(color: Colors.white))
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedUnitId = val),
                    hint: const Text("Choose a unit...", style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 16),
                ],

                // C. DATE SELECTOR
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedMonth,
                        decoration: _inputDecor("Month", Icons.calendar_month),
                        dropdownColor: AppTheme.surface,
                        style: const TextStyle(color: Colors.white),
                        items: _months.map((m) => DropdownMenuItem(
                          value: m, 
                          child: Text(_getMonthName(m), style: const TextStyle(color: Colors.white))
                        )).toList(),
                        onChanged: (val) => setState(() => _selectedMonth = val!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedYear,
                        decoration: _inputDecor("Year", Icons.calendar_today),
                        dropdownColor: AppTheme.surface,
                        style: const TextStyle(color: Colors.white),
                        items: _years.map((y) => DropdownMenuItem(
                          value: y, 
                          child: Text(y.toString(), style: const TextStyle(color: Colors.white))
                        )).toList(),
                        onChanged: (val) => setState(() => _selectedYear = val!),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // D. GENERATE BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // TODO: Implement Generate Report Logic
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.ecoTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.print),
                    label: const Text("GENERATE REPORT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text("Report History", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),

          // 2. HISTORY LIST (Dynamic)
          if (_reportHistory.isEmpty)
             const Padding(
               padding: EdgeInsets.all(20.0),
               child: Center(child: Text("No reports generated yet.", style: TextStyle(color: Colors.white24))),
             )
          else
            ..._reportHistory.map((report) => _buildHistoryItem(
              title: report['title'] ?? 'Untitled',
              type: report['scope'] ?? 'General',
              size: report['size'] ?? '-',
              date: report['date'] ?? '-',
            )),
        ],
      ),
    );
  }

  // --- HELPERS ---

  InputDecoration _inputDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05), 
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.ecoTeal),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  String _getMonthName(int month) {
    const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return names[month - 1];
  }

  Widget _buildHistoryItem({required String title, required String type, required String size, required String date}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4)
              ),
              child: Text(type, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            const SizedBox(height: 4),
            Text("$date • $size", style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download_rounded, color: AppTheme.ecoTeal),
          onPressed: () {
            // TODO: Implement Download Logic
          },
        ),
      ),
    );
  }
}

