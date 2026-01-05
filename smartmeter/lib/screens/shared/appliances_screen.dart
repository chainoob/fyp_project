import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/widgets/reusable_widget.dart';
import 'package:smartmeter/config/theme.dart';
import '../students/add_appliances_screen.dart';

class AppliancesScreen extends StatelessWidget {
  const AppliancesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Get Data
    final list = context.watch<ApplianceProvider>().appliances;
    final authProvider = context.read<AppAuthProvider>();
    final isStaff = authProvider.isStaff;
    final user = authProvider.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        title: const Text("My Appliances"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
            color: AppTheme.navyBlue,
            fontSize: 24,
            fontWeight: FontWeight.bold
        ),
        actions: [
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text("${list.length}", style: const TextStyle(color: Colors.white)),
                backgroundColor: AppTheme.ecoTeal,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
        ],
      ),

      floatingActionButton: isStaff
          ? null
          : FloatingActionButton.extended(
        onPressed: () {
          if (user != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddApplianceScreen(userId: user.uid),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please sign in to add devices.")),
            );
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add New Appliance"),
        backgroundColor: AppTheme.navyBlue,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      //Content Body
      body: list.isEmpty
          ? _buildFriendlyEmptyState(context)
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), // Extra bottom padding for FAB
        itemCount: list.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ApplianceCard(app: list[i]),
        ),
      ),
    );
  }

  Widget _buildFriendlyEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.ecoTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.outlet_outlined, size: 64, color: AppTheme.ecoTeal.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 24),
            const Text(
              "No appliances found",
              style: TextStyle(
                  color: AppTheme.navyBlue,
                  fontSize: 20,
                  fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Tap the button below to register your first appliance.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}