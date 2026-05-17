import 'package:cloud_functions/cloud_functions.dart';

class CloudService {
  // Region must explicitly match the deployed Cloud Function
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<void> triggerDisaggregation(String blockId, double billTotal, String month) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('triggerDisaggregation');
      await callable.call({
        'blockId': blockId,
        'totalBill': billTotal,
        'month': month,
        'trainModel': true,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Pipeline failure: ${e.code} - ${e.message}');
    }
  }
}