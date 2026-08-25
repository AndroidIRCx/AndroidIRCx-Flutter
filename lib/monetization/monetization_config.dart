import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class MonetizationConfig {
  const MonetizationConfig._();

  static const admobAppId = 'ca-app-pub-5116758828202889~8896612072';

  static const productionBannerAdUnitId =
      'ca-app-pub-5116758828202889/3084997712';
  static const productionRewardedAdUnitId =
      'ca-app-pub-5116758828202889/3979276988';

  static const testBannerAdUnitId = 'ca-app-pub-3940256099942544/9214589741';
  static const testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  static const rewardAdFreeMinutes = 60;

  static const productRemoveAds = 'remove_ads';
  static const productProUnlimited = 'pro_unlimited';
  static const productSupporterPro = 'supporter_pro';

  static const productIds = <String>{
    productRemoveAds,
    productProUnlimited,
    productSupporterPro,
  };

  static const products = <MonetizationProduct>[
    MonetizationProduct(
      id: productRemoveAds,
      title: 'Remove Ads',
      description: 'Remove all banner advertisements from the app.',
      features: <String>[
        'No banner ads',
        'One-time purchase',
        'Lifetime access',
      ],
    ),
    MonetizationProduct(
      id: productProUnlimited,
      title: 'Pro: Unlimited',
      description: 'No ads now, plus future unlimited scripting entitlement.',
      recommended: true,
      features: <String>[
        'No banner ads',
        'Future unlimited scripting',
        'One-time purchase',
        'Lifetime access',
      ],
    ),
    MonetizationProduct(
      id: productSupporterPro,
      title: 'Supporter Pro',
      description: 'All Pro features plus a supporter entitlement.',
      features: <String>[
        'No banner ads',
        'Future unlimited scripting',
        'Supporter status',
        'Supports open-source development',
        'One-time purchase',
        'Lifetime access',
      ],
    ),
  ];

  static String get bannerAdUnitId =>
      kReleaseMode ? productionBannerAdUnitId : testBannerAdUnitId;

  static String get rewardedAdUnitId =>
      kReleaseMode ? productionRewardedAdUnitId : testRewardedAdUnitId;

  static bool get usesProductionAds => kReleaseMode;

  static bool get mobileAdsRuntimeSupported {
    if (kIsWeb || _isWidgetTestBinding()) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool get storeRuntimeSupported {
    if (kIsWeb || _isWidgetTestBinding()) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}

class MonetizationProduct {
  const MonetizationProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.features,
    this.recommended = false,
  });

  final String id;
  final String title;
  final String description;
  final List<String> features;
  final bool recommended;
}

bool _isWidgetTestBinding() {
  var isTest = false;
  assert(() {
    isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    return true;
  }());
  return isTest;
}
