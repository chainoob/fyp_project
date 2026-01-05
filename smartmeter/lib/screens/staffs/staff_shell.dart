// ignore_for_file: prefer_final_fields

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/screens/shared/energy_goal.dart';
import 'package:smartmeter/screens/staffs/manage_block.dart';
import '../../config/theme.dart';
import '../shared/profile_screen.dart';
import 'package:smartmeter/models/app_model.dart';

class StaffShell extends StatefulWidget {
  const StaffShell({super.key});
  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  int _idx = 0;

  final _pages = const [
    StaffDashboard(),
    VerificationQueue(),
    StaffReportsPage(),
    ProfileScreen()
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ApplianceProvider>().subscribeToQueue();
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
          NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Campus'),
          NavigationDestination(icon: Icon(Icons.playlist_add_check), label: 'Verify'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
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

        // B. Energy Goal Card (Replaces "Set Energy Plan" & "Overload Alerts")
        // This card now serves as the notification center
        const EnergyGoalCard(title: "Campus Monthly Plan"),

        const SizedBox(height: 24),
        const Text("Infrastructure", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),

        // C. Manage Blocks (Full Width Action Card)
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
  String _selectedScope = 'Campus'; // Campus, Block, Unit
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String? _selectedBlockId;
  String? _selectedUnitId;

  // --- DATA VARIABLES (To be populated by Backend) ---
  // TODO: Fetch these lists from Firestore on init or scope change
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
    // 1. Fetch available Blocks/Units based on staff permissions or hierarchy.
    //    _availableBlocks = await _repo.getBlocks();
    // 2. Fetch Report History.
    //    _reportHistory = await _repo.getReportHistory();
    // 3. SetState to update UI.
    // -------------------------------------------------------------------------
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. REPORT CONFIGURATION CARD
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))
            ),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Report Parameters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // A. SCOPE SELECTOR
                  DropdownButtonFormField<String>(
                    initialValue: _selectedScope,
                    decoration: _inputDecor("Report Scope", Icons.radar),
                    items: _scopes.map((s) => DropdownMenuItem(value: s, child: Text("$s Level Report"))).toList(),
                    onChanged: (val) => setState(() {
                      _selectedScope = val!;
                      _selectedBlockId = null;
                      _selectedUnitId = null;
                      // TODO: Trigger fetch for sub-units if needed
                    }),
                  ),
                  const SizedBox(height: 16),

                  // B. CONDITIONAL DROPDOWNS (Dynamic Data)
                  if (_selectedScope == 'Block' || _selectedScope == 'Unit') ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedBlockId,
                      decoration: _inputDecor("Select Block", Icons.apartment),
                      // TODO: Map _availableBlocks variable here
                      items: _availableBlocks.map((b) => DropdownMenuItem(
                        value: b['id'] as String, 
                        child: Text(b['name'] as String)
                      )).toList(),
                      onChanged: (val) => setState(() => _selectedBlockId = val),
                      hint: const Text("Choose a block..."),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_selectedScope == 'Unit') ...[
                     DropdownButtonFormField<String>(
                      initialValue: _selectedUnitId,
                      decoration: _inputDecor("Select Unit", Icons.holiday_village),
                      // TODO: Map _availableUnits variable here
                      items: _availableUnits.map((u) => DropdownMenuItem(
                        value: u['id'] as String, 
                        child: Text(u['name'] as String)
                      )).toList(),
                      onChanged: (val) => setState(() => _selectedUnitId = val),
                      hint: const Text("Choose a unit..."),
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
                          items: _months.map((m) => DropdownMenuItem(
                            value: m, 
                            child: Text(_getMonthName(m))
                          )).toList(),
                          onChanged: (val) => setState(() => _selectedMonth = val!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          decoration: _inputDecor("Year", Icons.calendar_today),
                          items: _years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
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
                        backgroundColor: AppTheme.navyBlue,
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
          ),

          const SizedBox(height: 32),
          const Text("Report History", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),

          // 2. HISTORY LIST (Dynamic)
          if (_reportHistory.isEmpty)
             const Padding(
               padding: EdgeInsets.all(20.0),
               child: Center(child: Text("No reports generated yet.", style: TextStyle(color: Colors.grey))),
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
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.picture_as_pdf, color: Colors.red),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4)
              ),
              child: Text(type, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            const SizedBox(height: 4),
            Text("$date • $size", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download_rounded, color: AppTheme.navyBlue),
          onPressed: () {
            // TODO: Implement Download Logic
          },
        ),
      ),
    );
  }
}

// --- 3. VERIFICATION QUEUE (Unchanged Logic) ---
class VerificationQueue extends StatelessWidget {
  const VerificationQueue({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ApplianceProvider>();
    final pending = provider.appliances;

    if (pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: AppTheme.ecoTeal.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text("All Caught Up!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("No appliances waiting for verification.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pending.length,
      itemBuilder: (ctx, i) => _VerificationCard(app: pending[i]),
    );
  }
}

class _VerificationCard extends StatefulWidget {
  final Appliance app;
  const _VerificationCard({required this.app});

  @override
  State<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends State<_VerificationCard> {
  bool _isProcessing = false;

  Future<void> _handleAction(BuildContext context, bool isApprove) async {
    setState(() => _isProcessing = true);
    
    final provider = context.read<ApplianceProvider>();

    try {
      if (isApprove) {
        await provider.approve(widget.app.ownerId, widget.app.id);
      } else {
        await provider.reject(widget.app.ownerId, widget.app.id);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isApprove ? "Device Approved" : "Application Rejected"),
          backgroundColor: isApprove ? AppTheme.ecoTeal : Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Action Failed: $e"),
          backgroundColor: Colors.red,
        ));
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                  child: const Text("PENDING REVIEW", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(widget.app.type.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text(widget.app.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("${widget.app.wattage} Watts • ${widget.app.room ?? 'Unknown Room'}", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isProcessing ? null : () => _handleAction(context, false),
                  child: const Text("REJECT", style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isProcessing ? null : () => _handleAction(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.ecoTeal,
                    disabledBackgroundColor: AppTheme.ecoTeal.withValues(alpha: 0.5),
                  ),
                  child: _isProcessing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("APPROVE"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
