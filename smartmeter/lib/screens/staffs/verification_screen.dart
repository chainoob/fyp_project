// smartmeter/lib/screens/staff/verification_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/models/app_model.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Synchronize UI with reactive appliance queue state.
    final provider = context.watch<ApplianceProvider>();
    final pendingEntries = provider.pendingQueue;

    if (pendingEntries.isEmpty) {
      return const _EmptyStateView();
    }

    final Map<String, List<Appliance>> groupedData = {};
    for (var entry in pendingEntries) {
      groupedData.putIfAbsent(entry.key, () => []).add(entry.value);
    }

    final ownerIds = groupedData.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ownerIds.length,
      itemBuilder: (ctx, index) {
        final uid = ownerIds[index];
        return _StudentGroupCard(
          key: ValueKey(uid), 
          uid: uid,
          unitId: uid, 
          studentApps: groupedData[uid]!,
        );
      },
    );
  }
}

class _StudentGroupCard extends StatefulWidget {
  final String uid;
  final String unitId; // Placeholder for dynamic unit context.
  final List<Appliance> studentApps;

  const _StudentGroupCard({super.key, required this.uid, required this.unitId, required this.studentApps});

  @override
  State<_StudentGroupCard> createState() => _StudentGroupCardState();
}

class _StudentGroupCardState extends State<_StudentGroupCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Encapsulate expansion logic within student groupings.
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: .2)),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: Column(
        children: [
          _GroupHeader(
            uid: widget.uid,
            count: widget.studentApps.length,
            isExpanded: _isExpanded,
            onToggle: () => setState(() => _isExpanded = !_isExpanded),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            ...widget.studentApps.map((app) => _ApplianceActionTile(
              key: ValueKey(app.id),
              app: app, 
              userId: widget.uid,
              unitId: widget.unitId,
            )),
          ],
        ],
      ),
    );
  }
}
class _ApplianceActionTile extends StatefulWidget {
  final Appliance app;
  final String userId;
  final String unitId; // Dynamic unit context for telemetry generation.

  const _ApplianceActionTile({super.key, required this.app, required this.userId, required this.unitId});

  @override
  State<_ApplianceActionTile> createState() => _ApplianceActionTileState();
}

class _ApplianceActionTileState extends State<_ApplianceActionTile> {
  bool _isProcessing = false;

  Future<void> _handleAction(BuildContext context, bool isApprove) async {
  if (_isProcessing) return;

  setState(() => _isProcessing = true);
  final provider = context.read<ApplianceProvider>();

  try {
    if (isApprove) {
      // Execute appliance approval and trigger unit-level telemetry generation
      await provider.approve(widget.userId, widget.app.id, widget.unitId);
    } else {
      await provider.reject(widget.userId, widget.app.id);
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (context.mounted){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isApprove ? "Device Approved" : "Application Rejected"),
        backgroundColor: isApprove ? AppTheme.ecoTeal : Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  } catch (e) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if(context.mounted){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}

  void _showImageDialog(BuildContext context, String base64Str) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(widget.app.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                )
              ],
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Image.memory(
                  base64Decode(base64Str),
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => Container(
                    height: 200,
                    alignment: Alignment.center,
                    child: const Text("Failed to load image"),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Map appliance attributes to discrete UI components.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: .1))),
      ),
      child: Row(
        children: [
          if (widget.app.imageBase64 != null)
            GestureDetector(
              onTap: () => _showImageDialog(context, widget.app.imageBase64!),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(widget.app.imageBase64!),
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, size: 20, color: Colors.red),
                  ),
                ),
              ),
            )
          else
            const Icon(Icons.electrical_services, color: Colors.grey, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.app.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  "${widget.app.wattage}W • ${widget.app.maxDurationHr}h max usage",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (_isProcessing)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => _handleAction(context, false),
            ),
            IconButton(
              icon: const Icon(Icons.check, color: AppTheme.ecoTeal),
              onPressed: () => _handleAction(context, true),
            ),
          ]
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String uid;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _GroupHeader({
    required this.uid, 
    required this.count, 
    required this.isExpanded, 
    required this.onToggle
  });

  @override
  Widget build(BuildContext context) {
    // Render student metadata and queue summary.
    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: .05)),
        child: Row(
          children: [
            const CircleAvatar(radius: 14, backgroundColor: AppTheme.navyBlue, child: Icon(Icons.person, size: 16, color: Colors.white)),
            const SizedBox(width: 10),
            Expanded(
              child: FutureBuilder<String>(
                future: context.read<ApplianceProvider>().getStudentName(uid),
                builder: (context, snap) => Text(
                  snap.data ?? "Loading...",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
                ),
              ),
            ),
            Text("$count Pending", style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
            Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateView extends StatelessWidget {
  const _EmptyStateView();
  @override
  Widget build(BuildContext context) {
    // Structural placeholder for empty verification queue.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: AppTheme.ecoTeal.withValues(alpha: .5)),
          const SizedBox(height: 16),
          const Text("All Caught Up!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}