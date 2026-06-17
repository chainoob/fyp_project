import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/controllers/theme_provider.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String? photoUrl = appUser?.photoUrl;
    if (appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final String uid = appUser.uid;
    final List<Appliance> registeredAppliances = applianceProvider.appliances;

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        key: ValueKey(uid),
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
                            const SizedBox(height: 24),
                            const Text("App Preferences", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Card(
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                              ),
                              child: SwitchListTile(
                                title: Text("Dark Mode", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
                                subtitle: Text("Toggle dark or light application theme", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
                                value: context.watch<ThemeProvider>().isDarkMode,
                                activeThumbColor: AppTheme.ecoTeal,
                                onChanged: (bool val) {
                                  context.read<ThemeProvider>().toggleTheme(val);
                                },
                              ),
                            ),
                          ],
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: ListTile(
                            tileColor: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)
                              ),
                              child: const Icon(Icons.logout, color: Colors.red),
                            ),
                            title: Text("Log Out", style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
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

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'fan': return Icons.air_rounded;
      case 'laptop': return Icons.laptop_chromebook_rounded;
      case 'charger': return Icons.battery_charging_full_rounded;
      case 'lamp': case 'light': return Icons.lightbulb_outline_rounded;
      case 'iron': return Icons.iron_rounded;
      case 'kettle': return Icons.coffee_maker_rounded;
      case 'printer': return Icons.print_rounded;
      default: return Icons.power_rounded;
    }
  }

  Widget _buildManualToggleCard(Map<String, dynamic> dbOverrides, List<Appliance> appliances, EnergyProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (appliances.isEmpty) {
      return Card(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(child: Text("No registered appliances discovered.", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13))),
        ),
      );
    }

    return Card(
      color: Colors.transparent,
      elevation: 0,
      child: Column(
        children: appliances.map((app) {
          final String appName = app.name;
          final String appType = app.type;
          if (!provider.localSwitches.containsKey(appName)) {
            provider.localSwitches[appName] = (dbOverrides[appName] ?? 0.0) == 1.0;
          }
          final bool isCurrentlyOn = provider.localSwitches[appName]!;

          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.03) 
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isCurrentlyOn 
                        ? AppTheme.ecoTeal.withValues(alpha: 0.1) 
                        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIconForType(appType),
                    color: isCurrentlyOn ? AppTheme.ecoTeal : (isDark ? Colors.white38 : Colors.black38),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : Colors.black12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              appType.toUpperCase(),
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCurrentlyOn ? "Forced: ON" : "Forced: OFF",
                            style: TextStyle(
                              color: isCurrentlyOn ? AppTheme.ecoTeal : (isDark ? Colors.white38 : Colors.black38),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isCurrentlyOn,
                  activeTrackColor: AppTheme.ecoTeal.withValues(alpha: 0.3),
                  activeThumbColor: AppTheme.ecoTeal,
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: isDark ? Colors.white10 : Colors.black12,
                  onChanged: (bool value) async {
                    try {
                      await provider.updateManualOverride(appName, appType, value);
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("$appName ($appType) forced to ${value ? 'ON' : 'OFF'}.", 
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
                            ),
                            backgroundColor: AppTheme.ecoTeal,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Sync Failure: Database update rejected.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}