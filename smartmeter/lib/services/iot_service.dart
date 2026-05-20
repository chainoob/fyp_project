// lib/services/iot_service.dart

import 'dart:async';

/// Abstract interface for IoT data sources.
/// This allows the system to switch between Firebase, MQTT, or Direct HTTP polling
/// without affecting the UI controllers.
abstract class IoTTelemetrySource {
  /// Unique identifier for the meter/device.
  String get deviceId;

  /// Stream of raw wattage readings (W).
  Stream<double> get wattageStream;

  /// Optional: Connection status of the physical sensor.
  Stream<bool> get connectionStatus;

  /// Close the connection to the source.
  Future<void> dispose();
}

/// Firebase Implementation of the IoT source (current production logic).
class FirebaseTelemetrySource implements IoTTelemetrySource {
  @override
  final String deviceId;
  final StreamController<double> _controller = StreamController<double>.broadcast();
  final StreamController<bool> _statusController = StreamController<bool>.broadcast();
  
  StreamSubscription? _subscription;

  FirebaseTelemetrySource(this.deviceId, Stream<List<double>> firestoreStream) {
    _subscription = firestoreStream.listen((readings) {
      if (readings.isNotEmpty) {
        _controller.add(readings.first);
        _statusController.add(true);
      } else {
        _statusController.add(false);
      }
    }, onError: (_) {
      _statusController.add(false);
    });
  }

  @override
  Stream<double> get wattageStream => _controller.stream;

  @override
  Stream<bool> get connectionStatus => _statusController.stream;

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
    await _statusController.close();
  }
}

/// Mock Implementation for future MQTT or local hardware integration.
class MqttTelemetrySource implements IoTTelemetrySource {
  @override
  final String deviceId;
  
  MqttTelemetrySource(this.deviceId);

  @override
  Stream<double> get wattageStream => Stream.periodic(
    const Duration(seconds: 5), 
    (_) => 200.0 + (100.0 * (0.5 - (DateTime.now().millisecond / 1000)))
  );

  @override
  Stream<bool> get connectionStatus => Stream.value(true);

  @override
  Future<void> dispose() async {}
}
