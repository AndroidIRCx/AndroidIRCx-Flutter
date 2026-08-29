import 'package:androidircx/monetization/monetization_config.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class MobileAdsBootstrap {
  const MobileAdsBootstrap._();

  static Future<void>? _initialization;

  static Future<void> ensureInitialized({Future<void> Function()? initialize}) {
    if (!MonetizationConfig.mobileAdsRuntimeSupported) {
      return Future<void>.value();
    }

    final current = _initialization;
    if (current != null) {
      return current;
    }

    final starter =
        initialize ??
        () async {
          await MobileAds.instance.initialize();
        };
    final next = Future<void>.sync(starter).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _initialization = next;
    return next;
  }
}
