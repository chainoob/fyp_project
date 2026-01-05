import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../controllers/provider.dart';

class RegisterScreen extends StatefulWidget {
  final String? initialMatric;
  final String? initialEmail;

  const RegisterScreen({
    super.key,
    this.initialMatric,
    this.initialEmail,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _matricCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _selectedRole = 'student';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppAuthProvider>();
    if (widget.initialMatric != null) _matricCtrl.text = provider.pendingGoogleUser!.email;
    if (widget.initialEmail != null) _emailCtrl.text = provider.pendingGoogleUser!.displayName ?? '';
  }

  @override
  void dispose() {
    _matricCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userData = {
        'displayName': _usernameCtrl.text.trim(),
        'role': _selectedRole,
        'studentId': _matricCtrl.text.trim(),
      };

      await context.read<AppAuthProvider>().signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        additionalData: userData,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account created successfully")),
        );
        await context.read<AppAuthProvider>().signOut();
        if (!mounted) return;
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGoogleLinked = widget.initialEmail != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_add, size: 64, color: AppTheme.navyBlue),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Username",
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => v!.isEmpty ? "Username is required" : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  readOnly: isGoogleLinked, 
                  decoration: InputDecoration(
                    labelText: "Email Address",
                    prefixIcon: const Icon(Icons.email),
                    fillColor: isGoogleLinked ? Colors.white10 : null,
                    helperText: isGoogleLinked ? "Linked to your Google account" : null,
                  ),
                  validator: (v) => !v!.contains('@') ? "Invalid email" : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _matricCtrl,
                  decoration: const InputDecoration(
                    labelText: "Matric Number",
                    prefixIcon: Icon(Icons.badge),
                  ),
                  validator: (v) => v!.isEmpty ? "Matric Number is required" : null,
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: "Role",
                    prefixIcon: Icon(Icons.shield),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'student', child: Text("Student")),
                    DropdownMenuItem(value: 'staff', child: Text("Staff")),
                  ],
                  onChanged: (val) => setState(() => _selectedRole = val!),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Password",
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (v) => v!.length < 6 ? "Min 6 characters" : null,
                ),
                const SizedBox(height: 32),

                _isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _handleRegister,
                    child: const Text("CREATE ACCOUNT"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}