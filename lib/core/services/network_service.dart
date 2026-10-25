import 'package:network_info_plus/network_info_plus.dart';

class NetworkService {
  static final NetworkInfo _networkInfo = NetworkInfo();

  static Future<String?> getCurrentBSSID() async {
    try {
      return await _networkInfo.getWifiBSSID();
    } catch (_) {
      return null;
    }
  }

  static bool isAuthorizedWifi(String? currentBssid, List<dynamic> allowedBssids) {
    if (currentBssid == null) return false;
    return allowedBssids
        .map((e) => e.toString().toLowerCase())
        .contains(currentBssid.toLowerCase());
  }
}