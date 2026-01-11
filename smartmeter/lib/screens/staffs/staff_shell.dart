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

// --- 3. VERIFICATION QUEUE (Unchanged Logic) ---
class VerificationQueue extends StatelessWidget {
  const VerificationQueue({super.key});

  /// Groups appliances by their ownerId to create a sectioned list.
  Map<String, List<Appliance>> _groupByStudent(List<Appliance> list) {
    final Map<String, List<Appliance>> groups = {};
    for (var app in list) {
      final ownerId = app.ownerId.isEmpty ? 'Unknown' : app.ownerId;
      if (!groups.containsKey(ownerId)) {
        groups[ownerId] = [];
      }
      groups[ownerId]!.add(app);
    }
    return groups;
  }

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

    final groupedData = _groupByStudent(pending);
    final studentIds = groupedData.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: studentIds.length,
      itemBuilder: (ctx, index) {
        final studentId = studentIds[index];
        final studentApps = groupedData[studentId]!;

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: Column(
            children: [
              // Group Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.navyBlue.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 14,
                      backgroundColor: AppTheme.navyBlue,
                      child: Icon(Icons.person, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Student Request", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(
                          studentId, 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${studentApps.length} Pending",
                        style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // Items List
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: studentApps.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, i) {
                  return _VerificationCard(app: studentApps[i]);
                },
              ),
            ],
          ),
        );
      },
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
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.electrical_services, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.app.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      "${widget.app.type.toUpperCase()} • ${widget.app.wattage}W • ${widget.app.room ?? 'Unknown Room'}", 
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_isProcessing) ...[
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ] else ...[
                TextButton(
                  onPressed: () => _handleAction(context, false),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text("Reject"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _handleAction(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.ecoTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Approve"),
                ),
              ],
            ],
          )
        ],
      ),
    );
  }
}