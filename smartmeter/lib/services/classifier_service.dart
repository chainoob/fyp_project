// smartmeter/lib/services/classifier_service.dart

import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class ClassifierService {
  final Set<String> _allowedTypes = {
    'Fan',
    'Laptop',
    'Charger',
    'Lamp',
    'Iron',
    'Kettle',
    'Printer'
  };
  late ImageLabeler _labeler;

  ClassifierService() {
    _labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.70));
  }

  Future<String?> classifyDeviceImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    
    try {
      final List<ImageLabel> labels = await _labeler.processImage(inputImage);
      
      for (ImageLabel label in labels) {
        final String formattedLabel = _normalizeLabel(label.label);
        if (_allowedTypes.contains(formattedLabel)) {
          return formattedLabel;
        }
      }
      return null;
    } catch (e) {
      throw Exception('Image Core Processing Error: $e');
    }
  }

  String _normalizeLabel(String rawLabel) {
    final lowerLabel = rawLabel.toLowerCase();
    if (lowerLabel.contains('fan')) return 'Fan';
    if (lowerLabel.contains('laptop') || lowerLabel.contains('notebook') || lowerLabel.contains('computer')) return 'Laptop';
    if (lowerLabel.contains('charger') || lowerLabel.contains('adapter') || lowerLabel.contains('power supply')) return 'Charger';
    if (lowerLabel.contains('lamp') || lowerLabel.contains('light') || lowerLabel.contains('bulb')) return 'Lamp';
    if (lowerLabel.contains('iron')) return 'Iron';
    if (lowerLabel.contains('kettle') || lowerLabel.contains('teapot')) return 'Kettle';
    if (lowerLabel.contains('printer')) return 'Printer';
    return rawLabel;
  }

  void dispose() {
    _labeler.close();
  }
}