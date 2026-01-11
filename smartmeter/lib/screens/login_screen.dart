import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/routes/app_router.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';

String? clientId;
String? serverClientId;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _setupGoogleSignIn();
  }

  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  static const String _universityDomain = "@student.uthm.edu.my";
  static const String _staffDomain = "@uthm.edu.my";

  Future<void> _setupGoogleSignIn() async {
    await _googleSignIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  Future<void> _handleGoogleBtnClick() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final provider = context.read<AppAuthProvider>();

    try {
      final bool isExistingUser = await provider.googleLogin();
      final googleUser = provider.pendingGoogleUser;

      final isStudent = googleUser?.email.endsWith(_universityDomain); 
      final isStaff = googleUser?.email.endsWith(_staffDomain);

      if (!mounted) return;

      if (isExistingUser) {
        if (provider.isStaff) {
          context.go(AppRoutes.staffHome);
        } else {
          context.go(AppRoutes.studentHome);
        }
      } else {
        if ((!isStudent! && !isStaff!)) {
          await provider.signOut(); 
          throw Exception("Restricted Access: Please use a valid UTHM email (@student.uthm.edu.my or @uthm.edu.my)");
        }
        context.push(AppRoutes.register);
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogin() async {
    setState(() => _isLoading = true);
    String input = _idCtrl.text.trim();
    String emailToUse = input;

    if (!input.contains('@')) {
      emailToUse = "$input$_universityDomain";
    }

    try {
      await context.read<AppAuthProvider>().login(emailToUse, _passCtrl.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Login Failed: $e"))
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'asset/images/smartmeter_login_logo.png',
                  height: 160, 
                  width: 100,
              ),
              const SizedBox(height: 24),
              const Text("SmartMeter", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              Text("Energy Management System", style: TextStyle(color: Colors.grey[400])),
              const SizedBox(height: 48),

              if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                ),

              TextField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                    labelText: "Matric Number or Email",
                    prefixIcon: Icon(Icons.badge_outlined)
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock_outline)),
              ),
              const SizedBox(height: 32),

              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleLogin,
                  child: const Text("SECURE LOGIN"),
                ),
              ),

              const SizedBox(height: 24),

              const Row(children: <Widget>[
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("OR", style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ]),

              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: _isLoading ? null : _handleGoogleBtnClick,
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text("Sign in with Google"),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}