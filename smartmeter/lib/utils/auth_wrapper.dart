import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../screens/staffs/staff_shell.dart';
import '../screens/students/student_shell.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {

        // State: Waiting for Firebase Auth to initialize
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // State: User is NOT logged in
        if (!authSnapshot.hasData) {
          return const LoginScreen();
        }

        // State: User IS logged in -> Now fetch their Role
        final User user = authSnapshot.data!;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, roleSnapshot) {

            // State: Waiting for Firestore data
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Verifying Profile..."),
                    ],
                  ),
                ),
              );
            }

            if (roleSnapshot.hasError || !roleSnapshot.hasData || !roleSnapshot.data!.exists) {

              return const LoginScreen();
            }

            final userData = roleSnapshot.data!.data() as Map<String, dynamic>;
            final String role = userData['role'] ?? 'student';

            if (role == 'staff') {
              return const StaffShell();
            } else {
              return const StudentShell();
            }
          },
        );
      },
    );
  }
}