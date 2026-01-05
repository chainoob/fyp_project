import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/models/app_model.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Users? appUser = context.watch<AppAuthProvider>().currentUser;
    final String? photoUrl = appUser?.photoUrl;

    if (appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final String uid = appUser.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Error loading profile"));

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

        String? nameFromDb = data['displayName'] ?? data['name'];

        if (nameFromDb == null || nameFromDb.isEmpty) {
          nameFromDb = appUser.name;
        }

        final String displayName = nameFromDb;

        final String? studentId = data['studentId'] ?? data['matricNumber'] ?? appUser.studentId;

        final String role = data['role'] ?? appUser.role ?? 'Student';
        final String initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : "?";

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- PROFILE CARD ---
            Container(
              padding: const EdgeInsets.all(24),
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
                    radius: 32,
                    backgroundColor: Colors.white12,
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? Text(initial, style: const TextStyle(fontSize: 24, color: Colors.white))
                        : null,
                  ),
                  const SizedBox(width: 16),

                  // Text Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.ecoTeal.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            role.toUpperCase(),
                            style: const TextStyle(
                                color: AppTheme.ecoTeal,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1
                            ),
                          ),
                        ),
                        if (studentId != null && studentId.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            "ID: $studentId",
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Text("Settings", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // --- LOGOUT BUTTON ---
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)
                ),
                child: const Icon(Icons.logout, color: Colors.red),
              ),
              title: const Text("Log Out", style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              onTap: () async {
                // Confirm dialog
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Log Out?"),
                    content: const Text("Are you sure you want to sign out?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text("Log Out")
                      ),
                    ],
                  ),
                );

                if (confirm == true && context.mounted) {
                  await context.read<AppAuthProvider>().signOut();
                }
              },
            )
          ],
        );
      },
    );
  }
}