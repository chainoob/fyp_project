import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/models/app_model.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});

  /// Groups appliances by their ownerId (UID)
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
    // 1. Listen to the provider
    final provider = context.watch<ApplianceProvider>();
    final pending = provider.appliances;

    // 2. Empty State
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

    // 3. Group Data
    final groupedData = _groupByStudent(pending);
    final ownerIds = groupedData.keys.toList();

    // 4. Build List
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ownerIds.length,
      itemBuilder: (ctx, index) {
        final uid = ownerIds[index];
        final studentApps = groupedData[uid]!;

        // Use the dedicated Student Group Widget
        return _StudentGroupCard(uid: uid, studentApps: studentApps);
      },
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET 1: Student Group Card (Expandable Header)
// -----------------------------------------------------------------------------
class _StudentGroupCard extends StatefulWidget {
  final String uid;
  final List<Appliance> studentApps;

  const _StudentGroupCard({
    required this.uid,
    required this.studentApps,
  });

  @override
  State<_StudentGroupCard> createState() => _StudentGroupCardState();
}

class _StudentGroupCardState extends State<_StudentGroupCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // --- CLICKABLE HEADER ---
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: _isExpanded ? Radius.zero : const Radius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: _isExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.navyBlue,
                    child: Icon(Icons.person, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  
                  // Name & ID
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Student Request", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        FutureBuilder<String>(
                          future: context.read<ApplianceProvider>().getStudentName(widget.uid),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Text("Loading...", style: TextStyle(fontSize: 12, color: Colors.grey));
                            }
                            return Text(
                              snapshot.data ?? "Unknown",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${widget.studentApps.length} Pending",
                      style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                    ),
                  ),

                  const SizedBox(width: 8),
                  
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // --- EXPANDABLE BODY ---
          if (_isExpanded) ...[
            const Divider(height: 1, thickness: 1),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.studentApps.length,
              padding: EdgeInsets.zero,
              itemBuilder: (context, i) {
                return _VerificationCard(app: widget.studentApps[i]);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET 2: Individual Appliance Card (Approve/Reject Logic)
// -----------------------------------------------------------------------------
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
    final messenger = ScaffoldMessenger.of(context); 

    try {
      if (isApprove) {
        await provider.approve(widget.app.ownerId, widget.app.id);
      } else {
        await provider.reject(widget.app.ownerId, widget.app.id);
      }

      if (mounted) {
        setState(() => _isProcessing = false);
      }

      messenger.showSnackBar(SnackBar(
        content: Text(isApprove ? "Device Approved" : "Application Rejected"),
        backgroundColor: isApprove ? AppTheme.ecoTeal : Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));

    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(SnackBar(
          content: Text("Action Failed: $e"),
          backgroundColor: Colors.red,
        ));
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