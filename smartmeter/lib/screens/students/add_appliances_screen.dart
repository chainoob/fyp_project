import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../controllers/provider.dart';

// NOTE: If you haven't implemented the real ImageClassifier yet,
// you can comment out this import and the specific lines in _processImage.
// import '../../services/image_classifier.dart';

class AddApplianceScreen extends StatefulWidget {
  final String userId;

  const AddApplianceScreen({
    super.key,
    required this.userId
  });

  @override
  State<AddApplianceScreen> createState() => _AddApplianceScreenState();
}

class _AddApplianceScreenState extends State<AddApplianceScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _wattCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();

  String? _selectedType;

  final List<String> _allowedTypes = [
    'Fan',
    'Laptop',
    'Charger',
    'Lamp',
    'Iron',
    'Kettle',
    'Printer'
  ];

  File? _image;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _wattCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 600,
      );

      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _isProcessing = true;
        });

        // Trigger the AI processing
        await _processImage(_image!);
      }
    } catch (e) {
      debugPrint("Camera Error: $e");
      _showSnackBar("Camera failed: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processImage(File image) async {
    // TODO: Connect this to your real 'ImageClassifier' service.

    await Future.delayed(const Duration(seconds: 1));

    final detectedLabel = "kettle";

    _applyAiResults(detectedLabel);
  }

  void _applyAiResults(String label) {
    // Normalize to Title Case
    String formattedLabel = label.isNotEmpty
        ? label[0].toUpperCase() + label.substring(1).toLowerCase()
        : '';

    setState(() {
      // Logic to enforce allowed types
      if (_allowedTypes.contains(formattedLabel)) {
        _selectedType = formattedLabel;
        _showSnackBar("AI Detected: $formattedLabel", isError: false);
      } else {
        _selectedType = null;
        _showSnackBar("Detected '$formattedLabel' is prohibited in hostels.", isError: true);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() => _isProcessing = true);

    try {
      await context.read<ApplianceProvider>().add(
        _nameCtrl.text.trim(),
        _selectedType!, // Value guaranteed by validator
        int.parse(_wattCtrl.text.trim()),
        _roomCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context); // Return to list
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Device submitted for verification"),
              backgroundColor: AppTheme.ecoTeal,
            )
        );
      }
    } catch (e) {
      _showSnackBar("Submission Failed: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : AppTheme.ecoTeal,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register Device")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCameraArea(),

              const SizedBox(height: 24),
              const Text("Device Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                items: _allowedTypes.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type),
                )).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedType = val;
                  });
                },
                decoration: InputDecoration(
                  labelText: "Appliance Type",
                  prefixIcon: const Icon(Icons.category_outlined),
                  suffixIcon: _selectedType != null
                      ? const Icon(Icons.check_circle, color: AppTheme.ecoTeal, size: 20)
                      : null,
                  helperText: "Only approved hostel appliances allowed",
                ),
                validator: (v) => v == null ? "Required: Item prohibited or not selected" : null,
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Custom Name",
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) => v!.length < 3 ? "Name too short" : null,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _wattCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: "Wattage",
                        suffixText: "W",
                        prefixIcon: Icon(Icons.bolt),
                      ),
                      validator: (v) {
                        final val = int.tryParse(v ?? '0') ?? 0;
                        if (val <= 0) return "Invalid";
                        if (val > 5000) return "Max 5000W";
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _roomCtrl,
                      decoration: const InputDecoration(
                        labelText: "Location",
                        prefixIcon: Icon(Icons.room_outlined),
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isProcessing ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.ecoTeal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  disabledBackgroundColor: AppTheme.ecoTeal.withValues(alpha: 0.5),
                ),
                child: _isProcessing
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("SUBMIT FOR APPROVAL", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea() {
    return GestureDetector(
      onTap: _isProcessing ? null : _pickImage,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
          image: _image != null
              ? DecorationImage(image: FileImage(_image!), fit: BoxFit.cover)
              : null,
        ),
        child: _image == null
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black.withValues(alpha: 0.1))]),
              child: const Icon(Icons.camera_alt, size: 32, color: AppTheme.ecoTeal),
            ),
            const SizedBox(height: 12),
            const Text("Tap to Scan Appliance", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            if (_isProcessing) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ]
          ],
        )
            : Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _pickImage,
              ),
            ),
          ),
        ),
      ),
    );
  }
}