import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/widgets/reusable_widget.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppAuthProvider>().currentUser;
    final energyProvider = context.watch<EnergyProvider>();
    final applianceProvider = context.watch<ApplianceProvider>();
    final isStaffFromAuth = context.watch<AppAuthProvider>().isStaff;

    final String? photoUrl = appUser?.photoUrl;
    if (appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final String uid = appUser.uid;
    final List<String> registeredAppliances = applianceProvider.appliances.map((a) => a.name).toList();

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error loading profile"));

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final Map<String, dynamic> dbOverrides = data['manualOverrides'] ?? {};

          // Fix: Ensure we use the most accurate name source for both staff and students.
          String? nameFromDb = data['displayName'] ?? data['name'];

          if (nameFromDb == null || nameFromDb.isEmpty) {
            nameFromDb = appUser.name; // Use the name from the provider/Users model
          }

          final String displayName = nameFromDb.isNotEmpty ? nameFromDb : "Authenticated User";
          final String? studentId = data['studentId'] ?? data['matricNumber'];
          
          // Cross-verify role from both the document and the auth provider to ensure consistency.
          final String roleFromDb = data['role'] ?? 'student';
          final bool isStaff = isStaffFromAuth || roleFromDb.toLowerCase() == 'staff';
          final String roleDisplay = isStaff ? 'STAFF' : 'STUDENT';
          
          final String initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : "?";

          return LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [AppTheme.navyBlue, Color(0xFF1A237E)]
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  )
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.white12,
                                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                    child: photoUrl == null
                                        ? Text(initial, style: const TextStyle(fontSize: 24, color: Colors.white))
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.ecoTeal.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                roleDisplay,
                                                style: const TextStyle(
                                                    color: AppTheme.ecoTeal,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.1
                                                ),
                                              ),
                                            ),
                                            if (studentId != null && studentId.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                "ID: $studentId",
                                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),

                            // Evaluates role constraint logic to conditionally render manual tier injection widgets
                            if (!isStaff) ...[
                              const SizedBox(height: 24),
                              const Text("Hardware Override Constraints", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              _buildManualToggleCard(dbOverrides, registeredAppliances, energyProvider),
                            ],
                          ],
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: ListTile(
                            tileColor: AppTheme.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)
                              ),
                              child: const Icon(Icons.logout, color: Colors.red),
                            ),
                            title: const Text("Log Out", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AppAlertDialog(
                                  title: "Log Out?",
                                  content: "Are you sure you want to sign out?",
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false), 
                                      child: const Text("Cancel")
                                    ),
                                    TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text("Log Out")
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true && context.mounted) {
                                await context.read<AppAuthProvider>().signOut(context);
                              }
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildManualToggleCard(Map<String, dynamic> dbOverrides, List<String> appliances, EnergyProvider provider) {
    if (appliances.isEmpty) {
      return Card(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: Text("No registered appliances discovered.", style: TextStyle(color: Colors.white54, fontSize: 13))),
        ),
      );
    }

    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: appliances.map((appName) {
            final bool isCurrentlyOn = (dbOverrides[appName] ?? 0.0) == 1.0;

            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(appName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(
                isCurrentlyOn ? "Forced State: ON" : "Forced State: OFF",
                style: TextStyle(color: isCurrentlyOn ? AppTheme.ecoTeal : Colors.white38, fontSize: 11),
              ),
              value: isCurrentlyOn,
              activeThumbColor: AppTheme.ecoTeal,
              onChanged: (bool value) {
                provider.updateManualOverride(appName, value); 
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$appName sequence forced to ${value ? 'ON' : 'OFF'}.")),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}