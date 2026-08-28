import 'package:androidircx/core/models/app_settings.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

abstract class MediaAutoDownloadPolicy {
  Future<bool> canAutoDownload(MediaAutoDownloadMode mode);
}

class ConnectivityMediaAutoDownloadPolicy implements MediaAutoDownloadPolicy {
  ConnectivityMediaAutoDownloadPolicy({
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
  }) : _checkConnectivity =
           checkConnectivity ?? Connectivity().checkConnectivity;

  final Future<List<ConnectivityResult>> Function() _checkConnectivity;

  @override
  Future<bool> canAutoDownload(MediaAutoDownloadMode mode) async {
    switch (mode) {
      case MediaAutoDownloadMode.never:
        return false;
      case MediaAutoDownloadMode.always:
        return true;
      case MediaAutoDownloadMode.wifiOnly:
        final results = await _checkConnectivity();
        return results.contains(ConnectivityResult.wifi) ||
            results.contains(ConnectivityResult.ethernet);
    }
  }
}
