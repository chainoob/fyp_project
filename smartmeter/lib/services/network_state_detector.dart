import 'dart:async';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkStateDetector {
  final NetworkInfo _networkInfo = NetworkInfo();
  final int targetPort = 80;

  final Map<String, String> registeredDeviceIPs = {
    "Laptop": "192.168.1.105",
    "Printer": "192.168.1.200",
    "Fan": "192.168.1.50"
  };

  Future<Map<String, double?>> evaluateApplianceNetworkStates() async {
    // High-level functionality: Scan local network to map active device states.
    Map<String, double?> states = {
      "Laptop": null, "Printer": null, "Fan": null, 
      "Charger": null, "Lamp": null, "Iron": null, "Kettle": null
    };

    try {
      String? localIP = await _networkInfo.getWifiIP();
      String? subnetMask = await _networkInfo.getWifiSubmask();

      if (localIP == null || subnetMask == null) {
        // Developer expectation: Null IP indicates mobile data or disconnected state; fallback to null matrix.
        return _applyNullFallback(states);
      }

      for (String appliance in registeredDeviceIPs.keys) {
        String? targetIP = registeredDeviceIPs[appliance];
        if (targetIP == null) continue;

        try {
          // Developer expectation: 500ms timeout prevents UI thread blocking during socket verification.
          final socket = await Socket.connect(targetIP, targetPort, timeout: const Duration(milliseconds: 500));
          socket.destroy();
          states[appliance] = 1.0;
        } catch (_) {
          states[appliance] = 0.0;
        }
      }
    } catch (_) {
      return _applyNullFallback(states);
    }
    return states;
  }

  Map<String, double?> _applyNullFallback(Map<String, double?> stateMatrix) {
    // High-level functionality: Clear state matrix to force backend FHMM model reliance.
    for (String key in stateMatrix.keys) {
      stateMatrix[key] = null;
    }
    return stateMatrix;
  }
}